import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';

import '../../app_scope.dart';
import '../../platform/playback_capability.dart';
import '../../theme/tokens.dart';
import '../diagnostics/player_diagnostics.dart';
import '../models/playback_media.dart';
import '../models/resolved_source.dart';
import '../player_page.dart';
import '../state/source_priority_controller.dart';
import '../state/subtitle_preference_controller.dart';

/// A Play tap owns the navigator until its loading route has handed off to
/// the player. Without this, a quick second tap can stack another loading and
/// player route on top of the first workflow.
final Set<NavigatorState> _activePlayNavigators = <NavigatorState>{};

Future<void> playItemV2(
  BuildContext context,
  MediaItemV2 item, {
  EpisodeGuide? episodeGuide,
  ContentRating contentRating = ContentRating.unknown,
  bool replaceCurrent = false,
  bool returnToDetail = false,
  StreamSource? preferredSource,
}) async {
  final navigator = Navigator.of(context);
  if (!_activePlayNavigators.add(navigator)) return;
  try {
    await _playMedia(
      context,
      PlaybackMedia(item),
      episodeGuide: episodeGuide,
      contentRating: contentRating,
      replaceCurrent: replaceCurrent,
      returnToDetail: returnToDetail,
      preferredSource: preferredSource,
    );
  } finally {
    _activePlayNavigators.remove(navigator);
  }
}

Future<void> _playMedia(
  BuildContext context,
  PlaybackMedia item, {
  EpisodeGuide? episodeGuide,
  ContentRating contentRating = ContentRating.unknown,
  bool replaceCurrent = false,
  bool returnToDetail = false,
  StreamSource? preferredSource,
}) async {
  final scope = AppScope.of(context);
  final navigator = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final routeToReplace = replaceCurrent ? ModalRoute.of(context) : null;

  // Kicked off before source discovery so it overlaps with the resolve the
  // viewer is already waiting through, instead of adding to it.
  final externalSubtitles = _prefetchExternalSubtitles(scope, item);
  final playbackSegments = _prefetchPlaybackSegments(scope, item);

  // Live providers commonly sign URLs for a short window. Reusing a
  // resolved live stream after an extension update can hand the native player an old
  // URL even though source discovery itself is still valid.
  final canUseCache = canUseCachedPlaybackSources(item);
  // Episode transitions must resolve a fresh URL. The persisted stream is
  // for resume/Continue Watching and may be stale or belong to another
  // source variant than the one carried forward from the current episode.
  final lastPlayed = canUseCache && preferredSource == null
      ? await scope.sourceCache.loadLastResolved(item.ref)
      : null;
  final lastResolved = lastPlayed?.resolved;
  if (lastResolved != null &&
      lastResolved.hasAbsoluteHttpUrl &&
      scope.registry.isSourceEnabled(lastResolved.source) &&
      PlaybackTarget.detect().canPlay(lastResolved.stream)) {
    await _openPlayer(
      navigator,
      scope,
      item,
      [lastResolved],
      replaceCurrent,
      contentRating: contentRating,
      episodeGuide: episodeGuide,
      externalSubtitles: externalSubtitles,
      playbackSegments: playbackSegments,
      returnToDetail: returnToDetail,
    );
    return;
  }

  final cachedList = canUseCache
      ? scope.sourceCache.peekSourceList(item.ref)
      : null;
  final enabledCachedList = cachedList
      ?.where(scope.registry.isSourceEnabled)
      .toList();
  if (enabledCachedList != null && enabledCachedList.isNotEmpty) {
    final orderedCachedList = _orderSourcesForPlayback(
      enabledCachedList,
      scope.sourcePriorityController,
      preferredSource,
    );
    _ResolvedSourceBatch? cachedBatch;
    final fast = await _resolveWithOverlay(
      navigator,
      (progress) async {
        final batch = _resolveKnownSourcesAsTheySettle(
          scope,
          item,
          orderedCachedList,
          progress,
          preferredSource: preferredSource,
        );
        cachedBatch = batch;
        final first = await batch.first;
        return first == null ? const <ResolvedSource>[] : [first];
      },
      onResolved: (resolved, loadingRoute) async {
        if (resolved.isEmpty) return false;
        final refresh = _revalidate(
          scope,
          item,
          preferredSource: preferredSource,
          excludeSourceKeys: {
            for (final source in orderedCachedList) sourceDescriptorKey(source),
          },
        );
        await _openPlayer(
          navigator,
          scope,
          item,
          resolved,
          replaceCurrent,
          loadingRoute: loadingRoute,
          routeToReplace: routeToReplace,
          contentRating: contentRating,
          episodeGuide: episodeGuide,
          pendingSources: _appendResolvedSources(cachedBatch!.stream, refresh),
          externalSubtitles: externalSubtitles,
          playbackSegments: playbackSegments,
          returnToDetail: returnToDetail,
        );
        return true;
      },
    );
    if (fast == null) return; // abandoned mid-resolve
    if (fast.isNotEmpty) return;
  }

  final result = await _resolveWithOverlay(
    navigator,
    (progress) => _resolveFirstPlayableWithRetry(
      scope,
      item,
      progress,
      preferredSource: preferredSource,
    ),
    onResolved: (resolved, loadingRoute) async {
      final first = resolved.first;
      if (first == null) return false;
      await _openPlayer(
        navigator,
        scope,
        item,
        [first],
        replaceCurrent,
        loadingRoute: loadingRoute,
        routeToReplace: routeToReplace,
        contentRating: contentRating,
        episodeGuide: episodeGuide,
        pendingSources: _appendResolvedSources(
          resolved.second,
          resolved.refresh,
        ),
        externalSubtitles: externalSubtitles,
        playbackSegments: playbackSegments,
        returnToDetail: returnToDetail,
      );
      return true;
    },
  );
  if (result == null) return;

  if (result.first == null) {
    messenger.showSnackBar(
      const SnackBar(content: Text('No playable sources found.')),
    );
    return;
  }
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
) => _revalidate(scope, item).done;

Future<T?> _resolveWithOverlay<T>(
  NavigatorState navigator,
  Future<T> Function(_ResolveProgress progress) resolve, {
  Future<bool> Function(T result, Route<void> loadingRoute)? onResolved,
}) async {
  final progress = _ResolveProgress();
  final loadingReady = Completer<void>();
  final launchKey = GlobalKey<_PlayerLaunchPageState>();
  var abandoned = false;
  late final PageRouteBuilder<void> overlay;
  void abandon() {
    abandoned = true;
    if (overlay.isActive) navigator.removeRoute(overlay);
  }

  overlay = PageRouteBuilder<void>(
    opaque: false,
    pageBuilder: (_, _, _) => _PlayerLaunchPage(
      key: launchKey,
      progress: progress,
      onBack: abandon,
      onMounted: () {
        if (!loadingReady.isCompleted) loadingReady.complete();
      },
    ),
  );

  unawaited(overlay.popped.whenComplete(() => abandoned = true));
  _debugSourceLog('player_route_loading');
  unawaited(navigator.push(overlay));

  final result = await resolve(progress);

  // A very fast source can resolve before the route gets its first build.
  // Keep the notifier alive until the loading page is mounted or abandoned.
  await Future.any([loadingReady.future, overlay.popped]);
  if (abandoned) {
    progress.dispose();
    return null;
  }
  var handedOff = false;
  try {
    handedOff = onResolved == null ? false : await onResolved(result, overlay);
  } finally {
    if (!handedOff && overlay.isActive) navigator.removeRoute(overlay);
    progress.dispose();
  }
  return result;
}

class _ResolvedSourceBatch {
  const _ResolvedSourceBatch({
    required this.stream,
    required this.done,
    required this.first,
  });

  final Stream<ResolvedSource> stream;
  final Future<List<ResolvedSource>> done;
  final Future<ResolvedSource?> first;
}

_ResolvedSourceBatch _revalidate(
  AppScope scope,
  PlaybackMedia item, {
  StreamSource? preferredSource,
  Set<String> excludeSourceKeys = const {},
}) {
  final controller = StreamController<ResolvedSource>();
  final done = Completer<List<ResolvedSource>>();

  unawaited(() async {
    final progress = _ResolveProgress();
    try {
      var sources = await _loadSources(scope, item);
      if (sources.isEmpty && item.isLive) {
        await Future<void>.delayed(_sourceRetryDelay);
        sources = await _loadSources(scope, item);
      }
      if (sources.isEmpty) {
        done.complete(const []);
        return;
      }

      scope.sourceCache.recordSourceList(item.ref, sources);
      // The initial playback fan-out may already be resolving these same
      // descriptors. Revalidating them here creates duplicate WebViews and
      // Cloudflare challenges, which is especially expensive on iOS/macOS.
      final sourcesToResolve = [
        for (final source in sources)
          if (!excludeSourceKeys.contains(sourceDescriptorKey(source))) source,
      ];
      final batch = _resolveKnownSourcesAsTheySettle(
        scope,
        item,
        sourcesToResolve,
        progress,
        preferredSource: preferredSource,
      );
      final resolved = <ResolvedSource>[];
      await for (final source in batch.stream) {
        resolved.add(source);
        controller.add(source);
      }
      done.complete(List<ResolvedSource>.unmodifiable(resolved));
    } catch (_) {
      // Revalidation is background work. A failed refresh must not turn the
      // source picker stream into an unhandled future error.
      if (!done.isCompleted) done.complete(const []);
    } finally {
      progress.dispose();
      await controller.close();
    }
  }());
  return _ResolvedSourceBatch(
    stream: controller.stream,
    done: done.future,
    first: done.future.then((sources) => sources.firstOrNull),
  );
}

const _sourceRetryDelay = Duration(milliseconds: 250);
const _preferredSourceGrace = Duration(milliseconds: 750);
// Browser-backed providers can spend longer than the normal handoff grace on
// a challenge. Keep the selected episode source consistent when it is listed,
// then fall back if it cannot produce a fresh URL in this budget.
const _preferredEpisodeSourceTimeout = Duration(seconds: 30);
const _subtitleSourceGrace = Duration(milliseconds: 300);
const _externalSubtitleGrace = Duration(seconds: 1);
// Cloudflare-backed providers may need to finish a visible macOS challenge
// before the extension can retry its API request. Keep this budget longer than
// CloudflareKiller's 25-second solver window so a valid source is not discarded
// while that browser context is still being established.
const _sourceDiscoveryTimeout = Duration(seconds: 30);
// Browser-backed providers can need more than one nested iframe/request before
// the JS resolver reaches the final media URL. Resolution runs in parallel and
// the first fast source still opens the player immediately, so this only keeps
// slow fallback sources alive long enough to contribute to the source picker.
const _sourceResolveTimeout = Duration(seconds: 60);

/// A live event can be visible before a provider's event feed or stream
/// endpoint has settled. Give that transient window one automatic retry so a
/// first tap does not incorrectly report that the event has no sources.
Future<void> _openPlayer(
  NavigatorState navigator,
  AppScope scope,
  PlaybackMedia item,
  List<ResolvedSource> sources,
  bool replaceCurrent, {
  Route<void>? loadingRoute,
  Route<dynamic>? routeToReplace,
  required ContentRating contentRating,
  EpisodeGuide? episodeGuide,
  Stream<ResolvedSource>? pendingSources,
  Future<void>? externalSubtitles,
  Future<List<PlaybackSegment>>? playbackSegments,
  bool returnToDetail = false,
}) async {
  final stopwatch = Stopwatch()..start();
  // Started alongside source resolution, so by now it has almost always
  // landed. The short grace keeps the preferred track available without
  // making a slow subtitle provider block playback indefinitely.
  if (externalSubtitles != null) {
    _debugSourceLog('player_open_subtitle_wait_start');
    await _waitForExternalSubtitles(externalSubtitles);
    _debugSourceLog(
      'player_open_subtitle_wait_done '
      'elapsed=${stopwatch.elapsedMilliseconds}ms',
    );
  }
  if (loadingRoute != null && !loadingRoute.isActive) return;
  final resolved = _preferredFirst(
    sources,
    scope.sourcePriorityController,
    scope.subtitlePreferenceController,
  );
  _debugSourceLog(
    'player_source_candidates '
    'priority=${scope.sourcePriorityController.state.orderedProviderIds.join(',')} '
    'candidates=${sources.map((source) => _sourceLogName(source.source)).join(',')} '
    'selected=${_sourceLogName(resolved.first.source)}',
  );
  scope.sourceCache.promote(item.ref, resolved.first.source.id);
  if (canUseCachedPlaybackSources(item)) {
    scope.sourceCache.saveLastResolved(item.ref, resolved.first);
  }
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
  final player = PlayerPage(
    key: GlobalKey(),
    item: item.item,
    resolvedSources: resolved,
    persistedSourceId: canUseCachedPlaybackSources(item)
        ? resolved.first.source.id
        : null,
    pendingSources: pendingSources,
    pendingSegments: playbackSegments,
    episodeGuide: episodeGuide,
    returnToDetail: returnToDetail,
  );
  _debugSourceLog(
    'player_host_ready '
    'source=${_sourceLogName(resolved.first.source)} '
    'elapsed=${stopwatch.elapsedMilliseconds}ms',
  );
  scope.pictureInPictureSession.attach(player);
  if (loadingRoute?.isActive == true) navigator.removeRoute(loadingRoute!);
  if (replaceCurrent && routeToReplace?.isActive == true) {
    navigator.removeRoute(routeToReplace!);
  }
}

Future<void> _waitForExternalSubtitles(Future<void> pending) {
  final completer = Completer<void>();
  Timer? graceTimer;

  void finish() {
    if (completer.isCompleted) return;
    graceTimer?.cancel();
    completer.complete();
  }

  graceTimer = Timer(_externalSubtitleGrace, finish);
  unawaited(
    pending.then<void>(
      (_) => finish(),
      onError: (Object _, StackTrace _) => finish(),
    ),
  );
  return completer.future;
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

Future<
  ({
    ResolvedSource? first,
    Stream<ResolvedSource> second,
    _ResolvedSourceBatch? refresh,
  })
>
_resolveFirstPlayableWithRetry(
  AppScope scope,
  PlaybackMedia item,
  _ResolveProgress progress, {
  StreamSource? preferredSource,
}) async {
  final firstAttempt = await _resolveFirstPlayable(
    scope,
    item,
    progress,
    preferredSource: preferredSource,
  );
  if (firstAttempt.first != null || !item.isLive) return firstAttempt;
  await Future<void>.delayed(_sourceRetryDelay);
  return _resolveFirstPlayable(
    scope,
    item,
    progress,
    preferredSource: preferredSource,
  );
}

Future<
  ({
    ResolvedSource? first,
    Stream<ResolvedSource> second,
    _ResolvedSourceBatch? refresh,
  })
>
_resolveFirstPlayable(
  AppScope scope,
  PlaybackMedia item,
  _ResolveProgress progress, {
  StreamSource? preferredSource,
}) async {
  // A fast discovery may return only the first provider with sources. That is
  // fine when there is no source preference, but it can hide the user's
  // preferred locale/provider entirely. Fetch the complete list first whenever
  // the preference can affect the initial handoff; resolution remains parallel.
  final sourcePriority = scope.sourcePriorityController.state;
  final fastInitialDiscovery =
      !item.isLive &&
      preferredSource == null &&
      sourcePriority.orderedProviderIds.isEmpty &&
      sourcePriority.sourceLocale.isAuto;
  final sources = await _loadSources(scope, item, fast: fastInitialDiscovery);
  if (sources.isEmpty) {
    final retry = canUseCachedPlaybackSources(item)
        ? _revalidate(scope, item, preferredSource: preferredSource)
        : null;
    final complete = retry == null ? null : await retry.done;
    if (complete != null && complete.isNotEmpty) {
      return (
        first: complete.first,
        second: const Stream<ResolvedSource>.empty(),
        refresh: null,
      );
    }
    return (
      first: null,
      second: const Stream<ResolvedSource>.empty(),
      refresh: null,
    );
  }

  final ordered = _orderSourcesForPlayback(
    sources,
    scope.sourcePriorityController,
    preferredSource,
  );
  progress.begin([for (final source in ordered) source.label]);
  final target = PlaybackTarget.detect();
  final futures = [
    for (final source in ordered)
      _resolveOne(scope, item, source, target, progress),
  ];
  final all = _resolvedAsTheySettle(futures);
  // Resolution remains parallel, but the initial handoff must still honor
  // the ordered source list. That list includes manual provider order and
  // preferred source locale; using _firstMatching here would let the fastest
  // provider bypass both whenever no manual order was configured.
  final first = item.isLive
      ? await _firstMatching(futures, (_) => true)
      : preferredSource == null
      ? await _firstByPriority(futures)
      : await _firstPreferredEpisodeSource(futures, ordered, preferredSource);
  _ResolvedSourceBatch? startRefresh() => canUseCachedPlaybackSources(item)
      ? _revalidate(
          scope,
          item,
          preferredSource: preferredSource,
          excludeSourceKeys: {
            for (final source in sources) sourceDescriptorKey(source),
          },
        )
      : null;
  final preferred = scope.subtitlePreferenceController;
  if (first == null ||
      preferred.languageCode == null ||
      preferred.isSatisfiedBy(first.stream.subtitles)) {
    if (first != null) {
      return (first: first, second: all, refresh: startRefresh());
    }
    final retry = canUseCachedPlaybackSources(item)
        ? _revalidate(scope, item, preferredSource: preferredSource)
        : null;
    final complete = retry == null ? null : await retry.done;
    if (complete != null && complete.isNotEmpty) {
      return (first: complete.first, second: all, refresh: null);
    }
    return (first: null, second: all, refresh: null);
  }
  final subtitleMatch = await Future.any<ResolvedSource?>([
    _firstMatching(
      futures,
      (source) => preferred.isSatisfiedBy(source.stream.subtitles),
    ),
    Future<ResolvedSource?>.delayed(_subtitleSourceGrace, () => null),
  ]);
  if (subtitleMatch != null) {
    return (first: subtitleMatch, second: all, refresh: startRefresh());
  }
  return (first: first, second: all, refresh: startRefresh());
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
  PlaybackMedia item, {
  bool fast = false,
}) async {
  final stopwatch = Stopwatch()..start();
  try {
    final sources = await scope.sourceCache.loadSourceList(
      item.ref,
      () => scope.registry
          .sources(item.item, fast: fast)
          .timeout(_sourceDiscoveryTimeout),
      fast: fast,
    );
    final orderedSources = scope.sourcePriorityController.order(sources);
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
      'discovery_ok count=${orderedSources.length} '
      'mode=${fast ? 'fast' : 'full'} '
      'providers=${providers.isEmpty ? 'none' : providers} '
      'elapsed=${stopwatch.elapsedMilliseconds}ms',
    );
    return orderedSources;
  } on TimeoutException {
    _debugSourceLog(
      'discovery_timeout mode=${fast ? 'fast' : 'full'} '
      'after=${stopwatch.elapsedMilliseconds}ms',
    );
    return _staleSourceList(scope, item, fast: fast);
  } catch (error) {
    _debugSourceLog(
      'discovery_error mode=${fast ? 'fast' : 'full'} '
      'error=${redactPlaybackLogText(error)} '
      'elapsed=${stopwatch.elapsedMilliseconds}ms',
    );
    return _staleSourceList(scope, item, fast: fast);
  }
}

List<StreamSource> _staleSourceList(
  AppScope scope,
  PlaybackMedia item, {
  required bool fast,
}) {
  final cached = scope.sourceCache.peekSourceList(item.ref);
  if (cached == null || cached.isEmpty) return const [];
  final sources = scope.sourcePriorityController.order(cached);
  _debugSourceLog(
    'discovery_stale_ok count=${sources.length} '
    'mode=${fast ? 'fast' : 'full'}',
  );
  return sources;
}

/// Chooses the highest-priority source that resolves successfully, while
/// keeping a short deadline so a broken preferred provider cannot hold up
/// playback. All resolves are started in parallel; the grace window only
/// controls which completed result wins the initial handoff.
Future<ResolvedSource?> _firstByPriority(
  List<Future<ResolvedSource?>> futures,
) {
  final completer = Completer<ResolvedSource?>();
  final results = List<ResolvedSource?>.filled(futures.length, null);
  final settled = List<bool>.filled(futures.length, false);
  var graceElapsed = false;

  void choose() {
    if (completer.isCompleted) return;
    if (graceElapsed) {
      for (final result in results) {
        if (result != null) {
          completer.complete(result);
          return;
        }
      }
    } else {
      for (var index = 0; index < results.length; index++) {
        if (!settled[index]) return;
        final result = results[index];
        if (result != null) {
          completer.complete(result);
          return;
        }
      }
    }
    if (settled.every((value) => value)) completer.complete(null);
  }

  final timer = Timer(_preferredSourceGrace, () {
    graceElapsed = true;
    choose();
  });
  for (var index = 0; index < futures.length; index++) {
    unawaited(
      futures[index].then<void>(
        (value) {
          settled[index] = true;
          results[index] = value;
          choose();
        },
        onError: (Object _, StackTrace _) {
          settled[index] = true;
          choose();
        },
      ),
    );
  }
  unawaited(completer.future.whenComplete(timer.cancel));
  return completer.future;
}

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

List<StreamSource> _orderSourcesForPlayback(
  List<StreamSource> sources,
  SourcePriorityController sourcePriority,
  StreamSource? preferredSource,
) {
  final ordered = sourcePriority.order(sources);
  if (preferredSource == null) return ordered;

  final preferredProvider = sourceProviderKey(preferredSource);
  if (preferredProvider.isEmpty) return ordered;
  final preferredLabel = preferredSource.label.trim().toLowerCase();
  var preferredIndex = ordered.indexWhere(
    (source) =>
        sourceProviderKey(source) == preferredProvider &&
        source.label.trim().toLowerCase() == preferredLabel,
  );
  if (preferredIndex < 0) {
    preferredIndex = ordered.indexWhere(
      (source) => sourceProviderKey(source) == preferredProvider,
    );
  }
  if (preferredIndex <= 0) return ordered;
  return [
    ordered[preferredIndex],
    ...ordered.take(preferredIndex),
    ...ordered.skip(preferredIndex + 1),
  ];
}

_ResolvedSourceBatch _resolveKnownSourcesAsTheySettle(
  AppScope scope,
  PlaybackMedia item,
  List<StreamSource> sources,
  _ResolveProgress progress, {
  StreamSource? preferredSource,
}) {
  final filtered = [
    for (final source in sources)
      if (scope.registry.isSourceEnabled(source)) source,
  ];
  if (filtered.isEmpty) {
    return _ResolvedSourceBatch(
      stream: const Stream<ResolvedSource>.empty(),
      done: Future<List<ResolvedSource>>.value(const []),
      first: Future<ResolvedSource?>.value(null),
    );
  }

  final ordered = _orderSourcesForPlayback(
    filtered,
    scope.sourcePriorityController,
    preferredSource,
  );
  progress.begin([for (final source in ordered) source.label]);
  final target = PlaybackTarget.detect();
  final futures = [
    for (final source in ordered)
      _resolveOne(scope, item, source, target, progress),
  ];
  final controller = StreamController<ResolvedSource>();
  final resolved = <ResolvedSource>[];
  final done = Completer<List<ResolvedSource>>();
  var remaining = futures.length;

  void settle() {
    remaining--;
    if (remaining != 0) return;
    if (!done.isCompleted) {
      done.complete(List<ResolvedSource>.unmodifiable(resolved));
    }
    unawaited(controller.close());
  }

  for (final future in futures) {
    unawaited(
      future
          .then<void>((source) {
            if (source == null) return;
            resolved.add(source);
            controller.add(source);
          }, onError: (Object _, StackTrace _) {})
          .whenComplete(settle),
    );
  }
  return _ResolvedSourceBatch(
    stream: controller.stream,
    done: done.future,
    first: preferredSource == null
        ? _firstByPriority(futures)
        : _firstPreferredEpisodeSource(futures, ordered, preferredSource),
  );
}

Future<ResolvedSource?> _firstPreferredEpisodeSource(
  List<Future<ResolvedSource?>> futures,
  List<StreamSource> ordered,
  StreamSource preferredSource,
) async {
  final preferredIndex = ordered.indexWhere(
    (source) => _sameSourceVariant(source, preferredSource),
  );
  if (preferredIndex < 0) return _firstByPriority(futures);

  _debugSourceLog(
    'preferred_source_wait source=${_sourceLogName(ordered[preferredIndex])} '
    'timeout_s=${_preferredEpisodeSourceTimeout.inSeconds}',
  );
  ResolvedSource? preferred;
  try {
    preferred = await futures[preferredIndex].timeout(
      _preferredEpisodeSourceTimeout,
    );
  } on TimeoutException {
    preferred = null;
  }
  if (preferred != null) {
    _debugSourceLog(
      'preferred_source_ready source=${_sourceLogName(preferred.source)}',
    );
    return preferred;
  }

  _debugSourceLog(
    'preferred_source_fallback source=${_sourceLogName(preferredSource)}',
  );

  final fallback = [
    for (var index = 0; index < futures.length; index++)
      if (index != preferredIndex) futures[index],
  ];
  return _firstByPriority(fallback);
}

bool _sameSourceVariant(StreamSource source, StreamSource preferred) {
  final provider = sourceProviderKey(preferred);
  if (provider.isEmpty || sourceProviderKey(source) != provider) return false;
  final preferredLabel = preferred.label.trim().toLowerCase();
  return preferredLabel.isEmpty ||
      source.label.trim().toLowerCase() == preferredLabel;
}

/// Merges the fast result and background refresh so each source is forwarded
/// as soon as its own resolver settles. Both streams are already running when
/// this is called; waiting for one stream before listening to the other would
/// make parallel discovery look sequential in the picker.
Stream<ResolvedSource> _appendResolvedSources(
  Stream<ResolvedSource> initial,
  _ResolvedSourceBatch? refresh,
) {
  if (refresh == null) return initial;

  final controller = StreamController<ResolvedSource>();
  final subscriptions = <StreamSubscription<ResolvedSource>>[];
  var openStreams = 2;

  void closeWhenDone() {
    openStreams--;
    if (openStreams == 0) unawaited(controller.close());
  }

  void listenTo(Stream<ResolvedSource> stream) {
    subscriptions.add(
      stream.listen(
        controller.add,
        onError: (Object _, StackTrace _) {},
        onDone: closeWhenDone,
      ),
    );
  }

  controller.onCancel = () async {
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
  };

  listenTo(initial);
  listenTo(refresh.stream);
  return controller.stream;
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

class _PlayerLaunchPage extends StatefulWidget {
  const _PlayerLaunchPage({
    super.key,
    required this.progress,
    required this.onBack,
    required this.onMounted,
  });

  final _ResolveProgress progress;
  final VoidCallback onBack;
  final VoidCallback onMounted;

  @override
  State<_PlayerLaunchPage> createState() => _PlayerLaunchPageState();
}

class _PlayerLaunchPageState extends State<_PlayerLaunchPage> {
  Timer? _ticker;
  int _cursor = 0;
  Widget? _player;

  void showPlayer(Widget player) {
    if (!mounted) return;
    setState(() => _player = player);
  }

  @override
  void initState() {
    super.initState();
    widget.onMounted();
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
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    body: _player ?? _sourceFindingView(),
  );

  Widget _sourceFindingView() => ColoredBox(
    color: AppColors.surfaceDark,
    child: SafeArea(
      child: Stack(
        children: [
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minWidth: constraints.maxWidth,
                    minHeight: constraints.maxHeight,
                  ),
                  child: Center(
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
                ),
              ),
            ),
          ),
          Positioned(
            top: AppSpacing.xxs,
            left: AppSpacing.xs,
            child: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded),
              color: AppColors.onDark,
              iconSize: 22,
              tooltip: 'Back',
              onPressed: widget.onBack,
            ),
          ),
        ],
      ),
    ),
  );
}
