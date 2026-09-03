import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';

import '../../app_scope.dart';
import '../../platform/playback_capability.dart';
import '../../theme/tokens.dart';
import '../diagnostics/player_diagnostics.dart';
import '../models/playback_media.dart';
import '../player_page.dart';
import '../state/source_priority_controller.dart';
import '../state/subtitle_preference_controller.dart';

Future<void> playItemV2(
  BuildContext context,
  MediaItemV2 item, {
  EpisodeGuide? episodeGuide,
  ContentRating contentRating = ContentRating.unknown,
  bool replaceCurrent = false,
  bool returnToDetail = false,
}) => _playMedia(
  context,
  PlaybackMedia(item),
  episodeGuide: episodeGuide,
  contentRating: contentRating,
  replaceCurrent: replaceCurrent,
  returnToDetail: returnToDetail,
);

Future<void> _playMedia(
  BuildContext context,
  PlaybackMedia item, {
  EpisodeGuide? episodeGuide,
  ContentRating contentRating = ContentRating.unknown,
  bool replaceCurrent = false,
  bool returnToDetail = false,
}) async {
  final scope = AppScope.of(context);
  final navigator = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);

  // Kicked off before source discovery so it overlaps with the resolve the
  // viewer is already waiting through, instead of adding to it.
  final externalSubtitles = _prefetchExternalSubtitles(scope, item);
  final playbackSegments = _prefetchPlaybackSegments(scope, item);

  // Live providers commonly sign URLs for a short window. Reusing a
  // resolved live stream after an extension update can hand the native player an old
  // URL even though source discovery itself is still valid.
  final canUseCache = canUseCachedPlaybackSources(item);
  final cached = canUseCache ? scope.sourceCache.peek(item.ref) : null;
  final enabledCached = cached
      ?.where(
        (source) =>
            source.hasAbsoluteHttpUrl &&
            scope.registry.isSourceEnabled(source.source),
      )
      .toList();
  if (enabledCached != null && enabledCached.isNotEmpty) {
    unawaited(
      _openPlayer(
        navigator,
        scope,
        item,
        enabledCached,
        replaceCurrent,
        contentRating: contentRating,
        episodeGuide: episodeGuide,
        externalSubtitles: externalSubtitles,
        playbackSegments: playbackSegments,
        returnToDetail: returnToDetail,
      ),
    );
    if (scope.sourceCache.isStale(item.ref)) {
      unawaited(_revalidate(scope, item));
    }
    return;
  }

  final cachedList = canUseCache
      ? scope.sourceCache.peekSourceList(item.ref)
      : null;
  final enabledCachedList = cachedList
      ?.where(scope.registry.isSourceEnabled)
      .toList();
  if (enabledCachedList != null && enabledCachedList.isNotEmpty) {
    final fast = await _resolveWithOverlay(
      context,
      navigator,
      (progress) => _resolveKnownSources(scope, item, [
        enabledCachedList.first,
      ], progress),
    );
    if (fast == null) return; // abandoned mid-resolve
    if (fast.isNotEmpty) {
      scope.sourceCache.store(item.ref, fast);
      final pendingSources = _sourcesFromFuture(_revalidate(scope, item));
      unawaited(
        _openPlayer(
          navigator,
          scope,
          item,
          fast,
          replaceCurrent,
          contentRating: contentRating,
          episodeGuide: episodeGuide,
          pendingSources: pendingSources,
          externalSubtitles: externalSubtitles,
          playbackSegments: playbackSegments,
          returnToDetail: returnToDetail,
        ),
      );
      return;
    }
  }

  final result = await _resolveWithOverlay(
    context,
    navigator,
    (progress) => _resolveFirstPlayableWithRetry(scope, item, progress),
  );
  if (result == null) return;

  if (result.first == null) {
    messenger.showSnackBar(
      const SnackBar(content: Text('No playable sources found.')),
    );
    return;
  }

  final first = result.first!;
  scope.sourceCache.store(item.ref, [first]);
  unawaited(
    _openPlayer(
      navigator,
      scope,
      item,
      [first],
      replaceCurrent,
      contentRating: contentRating,
      episodeGuide: episodeGuide,
      pendingSources: result.second,
      externalSubtitles: externalSubtitles,
      playbackSegments: playbackSegments,
      returnToDetail: returnToDetail,
    ),
  );
}

/// Resolved URLs for live events and channels are usually signed and short
/// lived, so live playback must begin from a fresh resolution.
bool canUseCachedPlaybackSources(PlaybackMedia item) => !item.isLive;

/// Runs discovery and resolution again for [item], for the source picker's
/// refresh control.
///
/// Discovery is one call covering every provider on a single shared budget,
/// so a provider that is slow on the first attempt contributes nothing and
/// gets no second chance within that playback — the automatic retry only
/// fires when *no* source resolved at all. This is that second chance, asked
/// for explicitly. Returns what resolved; the caller merges rather than
/// replaces, so playback is never interrupted.
Future<List<ResolvedSource>> refetchPlayableSources(
  AppScope scope,
  PlaybackMedia item,
) async {
  final progress = _ResolveProgress();
  try {
    return await _playableSources(scope, item, progress);
  } finally {
    progress.dispose();
  }
}

Future<T?> _resolveWithOverlay<T>(
  BuildContext context,
  NavigatorState navigator,
  Future<T> Function(_ResolveProgress progress) resolve,
) async {
  final progress = _ResolveProgress();
  final overlay = DialogRoute<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black87,
    builder: (_) => _PlayLoadingOverlay(progress: progress),
  );

  var abandoned = false;
  unawaited(overlay.popped.whenComplete(() => abandoned = true));
  unawaited(navigator.push(overlay));

  final result = await resolve(progress);
  progress.dispose();

  if (abandoned) return null;
  navigator.removeRoute(overlay);
  return result;
}

Future<List<ResolvedSource>?> _revalidate(
  AppScope scope,
  PlaybackMedia item,
) async {
  final progress = _ResolveProgress();
  final sources = await _playableSourcesWithRetry(scope, item, progress);
  progress.dispose();
  if (sources.isEmpty) return null;
  scope.sourceCache.store(item.ref, sources);
  return sources;
}

const _sourceRetryDelay = Duration(milliseconds: 250);
const _subtitleSourceGrace = Duration(milliseconds: 300);
const _externalSubtitleGrace = Duration(seconds: 1);
const _sourceDiscoveryTimeout = Duration(seconds: 20);
const _sourceResolveTimeout = Duration(seconds: 20);

/// A live event can be visible before a provider's event feed or stream
/// endpoint has settled. Give that transient window one automatic retry so a
/// first tap does not incorrectly report that the event has no sources.
Future<List<ResolvedSource>> _playableSourcesWithRetry(
  AppScope scope,
  PlaybackMedia item,
  _ResolveProgress progress,
) async {
  final firstAttempt = await _playableSources(scope, item, progress);
  if (firstAttempt.isNotEmpty || !item.isLive) return firstAttempt;

  await Future<void>.delayed(_sourceRetryDelay);
  return _playableSources(scope, item, progress);
}

Future<void> _openPlayer(
  NavigatorState navigator,
  AppScope scope,
  PlaybackMedia item,
  List<ResolvedSource> sources,
  bool replaceCurrent, {
  required ContentRating contentRating,
  EpisodeGuide? episodeGuide,
  Stream<ResolvedSource>? pendingSources,
  Future<void>? externalSubtitles,
  Future<List<PlaybackSegment>>? playbackSegments,
  bool returnToDetail = false,
}) async {
  final stopwatch = Stopwatch()..start();
  // Started alongside source resolution, so by now it has almost always
  // landed. The grace is for when it has not: playback opens without it
  // rather than waiting on a subtitle the viewer may not even need.
  if (externalSubtitles != null) {
    _debugSourceLog('player_open_subtitle_wait_start');
    await Future.any([
      externalSubtitles,
      Future<void>.delayed(_externalSubtitleGrace),
    ]);
    _debugSourceLog(
      'player_open_subtitle_wait_done '
      'elapsed=${stopwatch.elapsedMilliseconds}ms',
    );
  }
  final resolved = _preferredFirst(
    sources,
    scope.sourcePriorityController,
    scope.subtitlePreferenceController,
  );
  scope.sourceCache.promote(item.ref, resolved.first.source.id);
  final savedRating = scope.libraryController
      .recordFor(item.ref)
      ?.contentRating;
  final effectiveRating = contentRating != ContentRating.unknown
      ? contentRating
      : savedRating != null && savedRating != ContentRating.unknown
      ? savedRating
      : scope.registry.contentRatingFor(item.ref);
  scope.libraryController.recordWatched(
    item.item,
    contentRating: effectiveRating,
  );
  final route = MaterialPageRoute<void>(
    builder: (_) => PlayerPage(
      item: item.item,
      resolvedSources: resolved,
      pendingSources: pendingSources,
      pendingSegments: playbackSegments,
      episodeGuide: episodeGuide,
      returnToDetail: returnToDetail,
    ),
  );
  _debugSourceLog(
    'player_route_push source=${_sourceLogName(resolved.first.source)} '
    'elapsed=${stopwatch.elapsedMilliseconds}ms',
  );
  unawaited(
    replaceCurrent ? navigator.pushReplacement(route) : navigator.push(route),
  );
}

List<ResolvedSource> _preferredFirst(
  List<ResolvedSource> sources,
  SourcePriorityController sourcePriority,
  SubtitlePreferenceController subtitlePreference,
) {
  final indexed = sources.indexed.toList();
  indexed.sort((a, b) {
    final aHasSubtitle = subtitlePreference.isSatisfiedBy(
      a.$2.stream.subtitles,
    );
    final bHasSubtitle = subtitlePreference.isSatisfiedBy(
      b.$2.stream.subtitles,
    );
    final subtitleResult = (bHasSubtitle ? 1 : 0).compareTo(
      aHasSubtitle ? 1 : 0,
    );
    if (subtitleResult != 0) return subtitleResult;
    final providerResult = sourcePriority
        .rankOf(a.$2.source.providerId)
        .compareTo(sourcePriority.rankOf(b.$2.source.providerId));
    return providerResult == 0 ? a.$1.compareTo(b.$1) : providerResult;
  });
  return [for (final entry in indexed) entry.$2];
}

Future<List<ResolvedSource>> _playableSources(
  AppScope scope,
  PlaybackMedia item,
  _ResolveProgress progress,
) async {
  final sources = await _loadSources(scope, item);
  if (sources.isEmpty) return const [];

  scope.sourceCache.recordSourceList(item.ref, sources);
  return _resolveKnownSources(scope, item, sources, progress);
}

Future<({ResolvedSource? first, Stream<ResolvedSource> second})>
_resolveFirstPlayableWithRetry(
  AppScope scope,
  PlaybackMedia item,
  _ResolveProgress progress,
) async {
  final firstAttempt = await _resolveFirstPlayable(scope, item, progress);
  if (firstAttempt.first != null || !item.isLive) return firstAttempt;
  await Future<void>.delayed(_sourceRetryDelay);
  return _resolveFirstPlayable(scope, item, progress);
}

Future<({ResolvedSource? first, Stream<ResolvedSource> second})>
_resolveFirstPlayable(
  AppScope scope,
  PlaybackMedia item,
  _ResolveProgress progress,
) async {
  final sources = await _loadSources(scope, item);
  if (sources.isEmpty) {
    return (first: null, second: const Stream<ResolvedSource>.empty());
  }

  scope.sourceCache.recordSourceList(item.ref, sources);
  final ordered = scope.sourcePriorityController.order(sources);
  progress.begin([for (final source in ordered) source.label]);
  final target = PlaybackTarget.detect();
  final futures = [
    for (final source in ordered)
      _resolveOne(scope, item, source, target, progress),
  ];
  final all = _resolvedAsTheySettle(futures);
  final first = await _firstNonNull(futures);
  final preferred = scope.subtitlePreferenceController;
  if (first == null ||
      preferred.languageCode == null ||
      preferred.isSatisfiedBy(first.stream.subtitles)) {
    return (first: first, second: all);
  }
  final subtitleMatch = await Future.any<ResolvedSource?>([
    _firstMatching(
      futures,
      (source) => preferred.isSatisfiedBy(source.stream.subtitles),
    ),
    Future<ResolvedSource?>.delayed(_subtitleSourceGrace, () => null),
  ]);
  return (first: subtitleMatch ?? first, second: all);
}

/// Looks up external subtitles for [item] while its sources resolve.
///
/// External subtitles belong to the *title*, not to a source, so this is one
/// lookup per item — and it runs here rather than inside a provider's
/// `resolve()`, which is where Nimora used to do it: a stream must never wait
/// on a subtitle addon to hand it back, and a source that is handed somebody
/// else's subtitles also stops being distinguishable from one that carries
/// its own, which is exactly what [_preferredFirst] ranks on.
///
/// Nothing is selected from the result here. A source's own tracks are timed
/// against that source's encode and still win; this only makes sure something
/// in the viewer's language exists for when no source carries one.
Future<void> _prefetchExternalSubtitles(
  AppScope scope,
  PlaybackMedia item,
) async {
  final preference = scope.subtitlePreferenceController;
  if (!needsExternalSubtitleLookup(preference, item)) return;

  try {
    final tracks = await scope.registry.externalSubtitles(item.item);
    preference.rememberExternalSubtitles(
      item.ref,
      tracks.where(isSupportedSubtitleTrack).toList(),
    );
  } catch (error) {
    // Playback is waiting on this future. A failed subtitle lookup has to
    // resolve like an empty one, never as an error that reaches the open.
    _debugSourceLog(
      'external_subtitles_error error=${redactPlaybackLogText(error)}',
    );
  }
}

/// Looks up episode skip markers alongside source discovery. This is optional
/// metadata: a failed lookup must never delay or fail playback.
Future<List<PlaybackSegment>> _prefetchPlaybackSegments(
  AppScope scope,
  PlaybackMedia item,
) async {
  if (!item.isEpisode || item.isLive) return const [];
  try {
    return await scope.registry.playbackSegments(item.item);
  } catch (error) {
    _debugSourceLog(
      'playback_segments_error error=${redactPlaybackLogText(error)}',
    );
    return const [];
  }
}

/// Whether [item] is worth an external-subtitle lookup before playback.
///
/// Nothing to look up when the viewer wants no particular language, and
/// nothing worth looking up for a live stream — a channel's tracks are its
/// own and there is no title to key an addon by. A lookup that already
/// produced the language for this item is not repeated: the tracks are kept
/// per item, so a re-play uses what the first play found.
bool needsExternalSubtitleLookup(
  SubtitlePreferenceController preference,
  PlaybackMedia item,
) =>
    preference.languageCode != null &&
    !item.isLive &&
    !preference.isSatisfiedBy(preference.rememberedExternalSubtitles(item.ref));

Future<List<StreamSource>> _loadSources(
  AppScope scope,
  PlaybackMedia item,
) async {
  final stopwatch = Stopwatch()..start();
  try {
    final sources = await scope.registry
        .sources(item.item)
        .timeout(_sourceDiscoveryTimeout);
    final providers = sources
        .map(
          (source) => source.providerId.isNotEmpty
              ? source.providerId
              : source.provider,
        )
        .where((provider) => provider.isNotEmpty)
        .toSet()
        .join(',');
    _debugSourceLog(
      'discovery_ok count=${sources.length} '
      'providers=${providers.isEmpty ? 'none' : providers} '
      'elapsed=${stopwatch.elapsedMilliseconds}ms',
    );
    return sources;
  } on TimeoutException {
    _debugSourceLog(
      'discovery_timeout after=${stopwatch.elapsedMilliseconds}ms',
    );
    return const [];
  } catch (error) {
    _debugSourceLog(
      'discovery_error error=${redactPlaybackLogText(error)} '
      'elapsed=${stopwatch.elapsedMilliseconds}ms',
    );
    return const [];
  }
}

Future<ResolvedSource?> _firstNonNull(List<Future<ResolvedSource?>> futures) =>
    _firstMatching(futures, (_) => true);

Future<ResolvedSource?> _firstMatching(
  List<Future<ResolvedSource?>> futures,
  bool Function(ResolvedSource source) matches,
) async {
  final completer = Completer<ResolvedSource?>();
  var remaining = futures.length;
  for (final future in futures) {
    unawaited(
      future.then((value) {
        if (value != null && matches(value) && !completer.isCompleted) {
          completer.complete(value);
        }
        remaining--;
        if (remaining == 0 && !completer.isCompleted) {
          completer.complete(null);
        }
      }),
    );
  }
  return completer.future;
}

/// Delivers each successful source immediately rather than making a usable
/// fallback wait for every provider in the fan-out to settle.
Stream<ResolvedSource> _resolvedAsTheySettle(
  List<Future<ResolvedSource?>> futures,
) {
  final controller = StreamController<ResolvedSource>();
  var remaining = futures.length;
  for (final future in futures) {
    unawaited(
      future
          .then((source) {
            if (source != null) controller.add(source);
          })
          .whenComplete(() {
            remaining--;
            if (remaining == 0) unawaited(controller.close());
          }),
    );
  }
  return controller.stream;
}

Stream<ResolvedSource> _sourcesFromFuture(
  Future<List<ResolvedSource>?> future,
) async* {
  final sources = await future;
  if (sources == null) return;
  yield* Stream<ResolvedSource>.fromIterable(sources);
}

Future<ResolvedSource?> _resolveOne(
  AppScope scope,
  PlaybackMedia item,
  StreamSource source,
  PlaybackTarget target,
  _ResolveProgress progress,
) async {
  final stopwatch = Stopwatch()..start();
  try {
    final stream = await scope.registry
        .resolveSource(item.ref, source.id)
        .timeout(_sourceResolveTimeout);
    final resolved = ResolvedSource(source: source, stream: stream);
    if (!resolved.hasAbsoluteHttpUrl) {
      _debugSourceLog(
        'resolve_rejected source=${_sourceLogName(source)} reason=relative_url',
      );
      return null;
    }
    if (!target.canPlay(stream)) {
      _debugSourceLog(
        'resolve_rejected source=${_sourceLogName(source)} '
        'reason=unsupported format=${stream.format.name} '
        'drm=${stream.drm?.scheme.name ?? 'none'}',
      );
      return null;
    }
    _debugSourceLog(
      'resolve_ok source=${_sourceLogName(source)} '
      'elapsed=${stopwatch.elapsedMilliseconds}ms',
    );
    return resolved;
  } on TimeoutException {
    _debugSourceLog(
      'resolve_timeout source=${_sourceLogName(source)} '
      'after=${stopwatch.elapsedMilliseconds}ms',
    );
    return null;
  } catch (error) {
    _debugSourceLog(
      'resolve_error source=${_sourceLogName(source)} '
      'error=${redactPlaybackLogText(error)} '
      'elapsed=${stopwatch.elapsedMilliseconds}ms',
    );
    return null;
  } finally {
    progress.markSettled(source.label);
  }
}

Future<List<ResolvedSource>> _resolveKnownSources(
  AppScope scope,
  PlaybackMedia item,
  List<StreamSource> sources,
  _ResolveProgress progress,
) async {
  sources = [
    for (final source in sources)
      if (scope.registry.isSourceEnabled(source)) source,
  ];
  if (sources.isEmpty) return const [];
  sources = scope.sourcePriorityController.order(sources);
  progress.begin([for (final source in sources) source.label]);

  final target = PlaybackTarget.detect();
  final resolved = await Future.wait(
    sources.map((source) => _resolveOne(scope, item, source, target, progress)),
  );
  return resolved.whereType<ResolvedSource>().toList();
}

String _sourceLogName(StreamSource source) {
  final provider = source.providerId.isNotEmpty
      ? source.providerId
      : source.provider;
  return provider.isEmpty ? source.label : '$provider/${source.label}';
}

void _debugSourceLog(String message) {
  if (kDebugMode) debugPrint('[PlaybackSources] $message');
}

class _ResolveProgress extends ChangeNotifier {
  final List<String> _outstanding = [];
  int _total = 0;
  int _settled = 0;
  bool _disposed = false;

  List<String> get outstanding => List.unmodifiable(_outstanding);

  int get settledCount => _settled;
  int get total => _total;

  void begin(List<String> names) {
    if (_disposed) return;
    _outstanding
      ..clear()
      ..addAll(names);
    _total = names.length;
    _settled = 0;
    notifyListeners();
  }

  void markSettled(String name) {
    // The first playable source can open the player while the remaining
    // resolves continue in the background. Those futures may settle after
    // the loading overlay has disposed this notifier.
    if (_disposed) return;
    _outstanding.remove(name);
    _settled++;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class _PlayLoadingOverlay extends StatefulWidget {
  const _PlayLoadingOverlay({required this.progress});

  final _ResolveProgress progress;

  @override
  State<_PlayLoadingOverlay> createState() => _PlayLoadingOverlayState();
}

class _PlayLoadingOverlayState extends State<_PlayLoadingOverlay> {
  Timer? _ticker;
  int _cursor = 0;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(milliseconds: 900), (_) {
      if (mounted) setState(() => _cursor++);
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Center(
    child: Material(
      color: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: ListenableBuilder(
          listenable: widget.progress,
          builder: (context, _) {
            final outstanding = widget.progress.outstanding;
            final total = widget.progress.total;
            final line = outstanding.isEmpty
                ? 'Finding sources…'
                : 'Checking ${outstanding[_cursor % outstanding.length]}…';

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 56,
                  height: 56,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.5,
                      ),
                      Icon(
                        Icons.travel_explore,
                        color: AppColors.onDark,
                        size: 22,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  line,
                  textAlign: TextAlign.center,
                  style: AppTypography.titleSm.copyWith(
                    color: AppColors.onDark,
                    letterSpacing: 0.5,
                  ),
                ),
                if (total > 0) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '${widget.progress.settledCount} of $total ready',
                    style: AppTypography.bodySm.copyWith(
                      color: AppColors.onDarkSoft,
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    ),
  );
}
