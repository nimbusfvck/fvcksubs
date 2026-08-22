import 'dart:async';

import 'package:flutter/material.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';

import '../app_scope.dart';
import '../platform/playback_capability.dart';
import '../theme/tokens.dart';
import 'player_page.dart';
import 'playback_media.dart';
import 'source_priority_controller.dart';
import 'subtitle_preference_controller.dart';

Future<void> playItemV2(
  BuildContext context,
  MediaItemV2 item, {
  EpisodeGuide? episodeGuide,
  bool replaceCurrent = false,
  bool returnToDetail = false,
}) => _playMedia(
  context,
  PlaybackMedia(item),
  episodeGuide: episodeGuide,
  replaceCurrent: replaceCurrent,
  returnToDetail: returnToDetail,
);

Future<void> _playMedia(
  BuildContext context,
  PlaybackMedia item, {
  EpisodeGuide? episodeGuide,
  bool replaceCurrent = false,
  bool returnToDetail = false,
}) async {
  final scope = AppScope.of(context);
  final navigator = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);

  final cached = scope.sourceCache.peek(item.ref);
  final enabledCached = cached
      ?.where((source) => scope.registry.isSourceEnabled(source.source))
      .toList();
  if (enabledCached != null && enabledCached.isNotEmpty) {
    _openPlayer(
      navigator,
      scope,
      item,
      enabledCached,
      replaceCurrent,
      episodeGuide: episodeGuide,
      returnToDetail: returnToDetail,
    );
    if (scope.sourceCache.isStale(item.ref)) {
      unawaited(_revalidate(scope, item));
    }
    return;
  }

  final cachedList = scope.sourceCache.peekSourceList(item.ref);
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
      _openPlayer(
        navigator,
        scope,
        item,
        fast,
        replaceCurrent,
        episodeGuide: episodeGuide,
        pendingSources: pendingSources,
        returnToDetail: returnToDetail,
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
  _openPlayer(
    navigator,
    scope,
    item,
    [first],
    replaceCurrent,
    episodeGuide: episodeGuide,
    pendingSources: result.second,
    returnToDetail: returnToDetail,
  );
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

void _openPlayer(
  NavigatorState navigator,
  AppScope scope,
  PlaybackMedia item,
  List<ResolvedSource> sources,
  bool replaceCurrent, {
  EpisodeGuide? episodeGuide,
  Stream<ResolvedSource>? pendingSources,
  bool returnToDetail = false,
}) {
  final resolved = _preferredFirst(
    sources,
    scope.sourcePriorityController,
    scope.subtitlePreferenceController,
  );
  scope.sourceCache.promote(item.ref, resolved.first.source.id);
  scope.libraryController.recordWatched(item.item);
  final route = MaterialPageRoute<void>(
    builder: (_) => PlayerPage(
      item: item.item,
      resolvedSources: resolved,
      pendingSources: pendingSources,
      episodeGuide: episodeGuide,
      returnToDetail: returnToDetail,
    ),
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
  List<StreamSource> sources;
  try {
    sources = await scope.registry.sources(item.item);
  } catch (_) {
    return const [];
  }
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
  List<StreamSource> sources;
  try {
    sources = await scope.registry.sources(item.item);
  } catch (_) {
    return (first: null, second: const Stream<ResolvedSource>.empty());
  }
  if (sources.isEmpty) {
    return (first: null, second: const Stream<ResolvedSource>.empty());
  }

  scope.sourceCache.recordSourceList(item.ref, sources);
  final ordered = scope.sourcePriorityController.order(sources);
  progress.begin([for (final source in ordered) source.label]);
  final target = PlaybackTarget.detect();
  final futures = [
    for (final source in ordered) _resolveOne(scope, item, source, target),
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
) async {
  try {
    final stream = await scope.registry.resolveSource(item.ref, source.id);
    if (!target.canPlay(stream)) return null;
    return ResolvedSource(source: source, stream: stream);
  } catch (_) {
    return null;
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
    sources.map((source) async {
      try {
        final stream = await scope.registry.resolveSource(item.ref, source.id);
        if (!target.canPlay(stream)) return null;
        return ResolvedSource(source: source, stream: stream);
      } catch (_) {
        return null;
      } finally {
        progress.markSettled(source.label);
      }
    }),
  );
  return resolved.whereType<ResolvedSource>().toList();
}

class _ResolveProgress extends ChangeNotifier {
  final List<String> _outstanding = [];
  int _total = 0;
  int _settled = 0;

  List<String> get outstanding => List.unmodifiable(_outstanding);

  int get settledCount => _settled;
  int get total => _total;

  void begin(List<String> names) {
    _outstanding
      ..clear()
      ..addAll(names);
    _total = names.length;
    _settled = 0;
    notifyListeners();
  }

  void markSettled(String name) {
    _outstanding.remove(name);
    _settled++;
    notifyListeners();
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
