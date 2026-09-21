import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';

import '../app_scope.dart';
import '../detail/episode_target_v2.dart';
import 'diagnostics/player_diagnostics.dart';
import '../library/library_controller.dart';
import '../platform/playback_capability.dart';
import '../theme/tokens.dart';
import 'controls/player_playback_controls.dart';
import 'controls/player_controls_overlay.dart';
import 'models/app_player_controller.dart';
import 'models/playback_media.dart';
import 'models/playback_start_position.dart';
import 'models/resolved_source.dart';
import 'multi_view_page.dart';
import 'sheets/player_selection_sheets.dart';
import 'state/playback_stall_detector.dart';
import 'state/persisted_resolved_source_recovery.dart';
import 'state/picture_in_picture_session.dart';
import 'state/player_orientation_coordinator.dart';
import 'state/source_fallback_policy.dart';
import 'state/stream_expiry.dart';
import 'widgets/player_overlays.dart';
import 'widgets/video_player_view.dart';
import 'workflow/play_item.dart';
import 'workflow/primary_episode_target.dart';

export 'models/resolved_source.dart' show ResolvedSource, mergeResolvedSources;

const Duration _progressInterval = Duration(seconds: 10);

/// How often playback is sampled for a stall.
///
/// Frequent enough that [PlaybackStallDetector.threshold] is the thing that
/// decides when to act, rather than the sampling rate.
const Duration _stallSampleInterval = Duration(seconds: 2);

/// A live player may leave its buffering flag set while its forward window is
/// still healthy. A sustained empty window, frozen position, or backward jump
/// is strong enough to discard the native player and resolve a fresh stream.
const Duration _liveBufferingRecoveryThreshold = Duration(seconds: 8);
const Duration _liveForwardBufferThreshold = Duration(seconds: 1);
const Duration _livePositionProgressTolerance = Duration(milliseconds: 250);
const Duration _renewalStabilityThreshold = Duration(seconds: 20);
const Duration _orientationReleaseDelay = Duration(milliseconds: 260);
const Duration _fallbackWaitTimeout = Duration(seconds: 10);
const Duration _livePlaybackWaitTimeout = Duration(seconds: 20);

/// How many failures in a row are answered by re-resolving the same source
/// before playback gives up on it and moves to another.
const int _maxConsecutiveRenewals = 2;

/// How close together renewals must be to count as consecutive.
const Duration _renewalPatienceWindow = Duration(minutes: 2);

Duration? sourceSwitchSeekPosition({
  required bool isLive,
  required Duration? previousPosition,
  required Duration? duration,
}) {
  if (isLive ||
      previousPosition == null ||
      duration == null ||
      duration <= Duration.zero) {
    return null;
  }
  return previousPosition > duration ? duration : previousPosition;
}

/// Progressive VOD origins can keep a replacement controller buffering after
/// a stall. Re-resolving the same MP4 source then drops the working controller
/// into a renewal loop, so a different already-resolved source is safer.
@visibleForTesting
bool shouldFallbackAfterVODStall({
  required bool isLive,
  required StreamFormat format,
}) => !isLive && format == StreamFormat.mp4;

/// Returns the media buffered ahead of the current live playback position.
@visibleForTesting
Duration liveForwardBuffer({
  required Duration position,
  required Duration bufferedPosition,
}) {
  if (bufferedPosition <= position) return Duration.zero;
  return bufferedPosition - position;
}

/// Returns only the buffer that is contiguous with the current live position.
@visibleForTesting
Duration liveContiguousForwardBuffer({
  required Duration position,
  required Duration bufferedPosition,
  List<AppPlayerTimeRange>? bufferedRanges,
}) {
  final ranges = bufferedRanges;
  if (ranges == null || ranges.isEmpty) {
    return liveForwardBuffer(
      position: position,
      bufferedPosition: bufferedPosition,
    );
  }
  return liveForwardBuffer(
    position: position,
    bufferedPosition: bufferedEndAtPosition(position: position, ranges: ranges),
  );
}

/// Reports whether a live player is buffering with no usable forward cushion.
@visibleForTesting
bool liveBufferingNeedsRecovery({
  required Duration position,
  required Duration bufferedPosition,
  List<AppPlayerTimeRange>? bufferedRanges,
  Duration? previousPosition,
  required bool isPlaying,
  required bool isBuffering,
}) {
  if (!isPlaying || !isBuffering) return false;
  final forwardBuffer = liveContiguousForwardBuffer(
    position: position,
    bufferedPosition: bufferedPosition,
    bufferedRanges: bufferedRanges,
  );
  if (forwardBuffer <= _liveForwardBufferThreshold) return true;
  if (previousPosition == null) return false;
  return position <= previousPosition + _livePositionProgressTolerance;
}

@visibleForTesting
bool playbackIsStableForRenewalReset({
  required bool isLive,
  required Duration position,
  required bool isPlaying,
  required bool isBuffering,
}) => isPlaying && !isBuffering && (!isLive || position > Duration.zero);

class PlayerPage extends StatefulWidget {
  PlayerPage({
    super.key,
    required MediaItemV2 item,
    required this.resolvedSources,
    this.persistedSourceId,
    this.episodeGuide,
    this.pendingSources,
    this.pendingSegments,
    this.returnToDetail = false,
  }) : media = PlaybackMedia(item),
       assert(resolvedSources.isNotEmpty, 'Must provide at least one source');

  final PlaybackMedia media;
  final List<ResolvedSource> resolvedSources;
  final String? persistedSourceId;
  final EpisodeGuide? episodeGuide;
  final Stream<ResolvedSource>? pendingSources;
  final Future<List<PlaybackSegment>>? pendingSegments;
  final bool returnToDetail;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  late int _currentIndex;
  late List<ResolvedSource> _resolvedSources;
  late final ValueNotifier<List<ResolvedSource>> _resolvedSourcesListenable;
  Future<List<ResolvedSource>>? _refetch;
  late final NextEpisodeV2? _nextEpisode;
  bool _showUpNext = false;

  /// Whether the viewer has closed the up-next card for this episode.
  ///
  /// Closing it is an answer, not a pause: the card is offered from a
  /// position sample, so without remembering the answer the next sample —
  /// a moment later — asks again, and the card returns for the rest of the
  /// episode. Playing the next episode replaces this route, so a fresh one
  /// starts willing to ask again.
  bool _upNextDismissed = false;
  List<PlaybackSegment> _playbackSegments = const [];
  bool _upNextPaused = false;
  bool _advancing = false;
  bool _episodeTransitioning = false;
  LibraryController? _library;
  Timer? _progressTimer;
  Timer? _stallTimer;
  Timer? _renewalTimer;
  Timer? _fallbackWaitTimer;
  final PlaybackStallDetector _stallDetector = PlaybackStallDetector();
  DateTime? _liveBufferingSince;
  Duration? _lastLivePosition;
  bool _renewing = false;
  DateTime? _lastRenewalAt;
  DateTime? _renewalStableSince;
  int _consecutiveRenewals = 0;
  ValueListenable<AppPlayerValue>? _videoValue;
  AppPlayerController? _trackedPositionController;
  bool _hasResumed = false;
  Duration? _lastPosition;
  Duration? _lastDuration;
  Duration? _pendingSwitchPosition;
  Duration? _pendingFitPosition;
  AppPlayerController? _pendingFitController;
  String? _playbackError;
  bool _retrying = false;
  bool _waitingForFallback = false;
  int _sourceRevision = 0;
  int _playbackAttempt = 0;
  final Set<String> _failedSourceIds = <String>{};
  final PersistedResolvedSourceRecovery _persistedResolvedSourceRecovery =
      PersistedResolvedSourceRecovery();
  String? _persistedSourceId;
  bool _pendingSourcesSettled = true;
  final ValueNotifier<bool> _backgroundSourceLoading = ValueNotifier<bool>(
    false,
  );
  String? _pendingFallbackSourceId;
  String? _pendingFallbackError;
  bool _sourceStarted = false;
  PlayerFitMode _fitMode = PlayerFitMode.contain;
  AppPlayerController? _aspectRatioController;
  double? _appliedViewportAspectRatio;
  bool? _systemUiImmersive;
  bool? _landscape;
  final PlayerOrientationCoordinator _orientationCoordinator =
      PlayerOrientationCoordinator();
  bool _allowPop = false;
  bool _backInFlight = false;
  bool _pipBackground = false;
  bool _resumeAfterPictureInPicture = false;
  bool _restorePlayPending = false;
  MiniPlayerMode? _presentationBeforePictureInPicture;
  PictureInPictureSession? _pictureInPictureSession;
  AppPlayerController? _controller;
  StreamSubscription<AppPlayerEvent>? _eventSubscription;
  void Function(bool visibility)? _onVisibilityChanged;

  bool get _isLive => widget.media.isLive;
  Duration get _fallbackWaitDuration =>
      _isLive ? _livePlaybackWaitTimeout : _fallbackWaitTimeout;
  bool get _supportsFullScreen => defaultTargetPlatform == TargetPlatform.macOS;
  ResolvedSource get _current => _resolvedSources[_currentIndex];

  @override
  void initState() {
    super.initState();
    _persistedSourceId = widget.persistedSourceId;
    _currentIndex = 0;
    _resolvedSources = widget.resolvedSources;
    _resolvedSourcesListenable = ValueNotifier<List<ResolvedSource>>(
      _resolvedSources,
    );
    final item = widget.media.item;
    _nextEpisode = item is EpisodeItemV2 && widget.episodeGuide != null
        ? nextEpisodeOfV2(item, widget.episodeGuide!)
        : null;
    final pending = widget.pendingSources;
    if (pending != null) {
      _pendingSourcesSettled = false;
      _backgroundSourceLoading.value = true;
      unawaited(_addPendingSources(pending));
    }
    final pendingSegments = widget.pendingSegments;
    if (pendingSegments != null) {
      unawaited(_loadPlaybackSegments(pendingSegments));
    }
  }

  Future<void> _loadPlaybackSegments(
    Future<List<PlaybackSegment>> pending,
  ) async {
    final segments = await pending;
    if (!mounted) return;
    setState(() => _playbackSegments = segments);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _library = AppScope.of(context).libraryController;
    final session = AppScope.of(context).pictureInPictureSession;
    if (!identical(_pictureInPictureSession, session)) {
      _pictureInPictureSession?.removeListener(
        _onPictureInPicturePresentationChanged,
      );
      _pictureInPictureSession = session;
      session.addListener(_onPictureInPicturePresentationChanged);
    }
    _syncSystemUi();
    _progressTimer ??= Timer.periodic(
      _progressInterval,
      (_) => _reportProgress(),
    );
    _stallTimer ??= Timer.periodic(
      _stallSampleInterval,
      (_) => _sampleForStall(),
    );
  }

  Future<void> _addPendingSources(Stream<ResolvedSource> pending) async {
    try {
      await for (final source in pending) {
        if (!mounted) return;
        final playingId = _current.source.id;
        final merged = mergeResolvedSources(_resolvedSources, [
          source,
        ], preserveSourceId: playingId);
        final cache = AppScope.of(context).sourceCache;
        cache.promote(widget.media.ref, playingId);
        // Late discovery only appends alternatives. Keep the player subtree
        // out of this update: rebuilding the controls while a source sheet is
        // animating makes its timeline visibly blink. The sheet listens to
        // this notifier directly, and callbacks read the page-owned list.
        _resolvedSources = merged;
        _currentIndex = merged.indexWhere(
          (source) => source.source.id == playingId,
        );
        if (_currentIndex < 0) _currentIndex = 0;
        _resolvedSourcesListenable.value = merged;
        _continuePendingFallback();
      }
    } catch (_) {
      // Background discovery is failure-tolerant. A source that is already
      // playing remains usable even when the remaining fan-out fails.
    } finally {
      if (mounted) {
        final cache = AppScope.of(context).sourceCache;
        final refreshedDescriptors = cache.peekSourceList(widget.media.ref);
        if (refreshedDescriptors != null) {
          final playingId = _current.source.id;
          final reconciled = mergeResolvedSources(
            _resolvedSources,
            const [],
            preserveSourceId: playingId,
            refreshedDescriptors: refreshedDescriptors,
          );
          _resolvedSources = reconciled;
          _currentIndex = reconciled.indexWhere(
            (source) => source.source.id == playingId,
          );
          if (_currentIndex < 0) _currentIndex = 0;
          _resolvedSourcesListenable.value = reconciled;
        }
        _pendingSourcesSettled = true;
        _backgroundSourceLoading.value = false;
        _continuePendingFallback();
      }
    }
  }

  /// Discovery again, on request, merged into what is already playing.
  ///
  /// One in-flight refetch at a time, and the guard lives here rather than in
  /// the sheet because closing and reopening the picker builds a fresh sheet:
  /// a sheet-local flag would let every reopen start another fan-out. That
  /// matters more than it looks — the extension runs on a single QuickJS
  /// event loop, so concurrent fan-outs compete with the resolves feeding
  /// playback instead of finishing any sooner.
  Future<List<ResolvedSource>> _refetchSources() =>
      _refetch ??= _runRefetch().whenComplete(() => _refetch = null);

  Future<List<ResolvedSource>> _runRefetch() async {
    final scope = AppScope.of(context);
    final found = await refetchPlayableSources(scope, widget.media);
    if (!mounted || found.isEmpty) return _resolvedSources;

    // Replace stale descriptors only for providers represented in this full
    // refresh. Providers that failed discovery remain available as fallbacks,
    // and the source being watched keeps playing.
    final playingId = _current.source.id;
    final merged = mergeResolvedSources(
      _resolvedSources,
      found,
      preserveSourceId: playingId,
      refreshedDescriptors: scope.sourceCache.peekSourceList(widget.media.ref),
    );
    scope.sourceCache.promote(widget.media.ref, playingId);
    // The open source remains unchanged by a refresh. Publish the new list
    // to the sheet without rebuilding the native player or its controls.
    _resolvedSources = merged;
    _currentIndex = merged.indexWhere(
      (source) => source.source.id == playingId,
    );
    if (_currentIndex < 0) _currentIndex = 0;
    _resolvedSourcesListenable.value = merged;
    return merged;
  }

  @override
  void dispose() {
    _pictureInPictureSession
      ?..removeListener(_onPictureInPicturePresentationChanged)
      ..detach(widget);
    _progressTimer?.cancel();
    _stallTimer?.cancel();
    _renewalTimer?.cancel();
    _fallbackWaitTimer?.cancel();
    _detachPositionListener();
    unawaited(_eventSubscription?.cancel());
    _backgroundSourceLoading.dispose();
    _resolvedSourcesListenable.dispose();
    _reportProgress();
    final landscape = _landscape == true;
    unawaited(
      SystemChrome.setEnabledSystemUIMode(
        landscape ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
      ),
    );
    _orientationCoordinator.reset();
    super.dispose();
  }

  void _trackPosition(AppPlayerController controller) {
    final next = controller.value;
    if (identical(next, _videoValue) &&
        identical(controller, _trackedPositionController)) {
      return;
    }
    _detachPositionListener();
    _trackedPositionController = controller;
    _videoValue = next..addListener(_onVideoValueChanged);
    _onVideoValueChanged();
  }

  void _detachPositionListener() {
    _videoValue?.removeListener(_onVideoValueChanged);
    _videoValue = null;
    _trackedPositionController = null;
  }

  void _onVideoValueChanged() {
    final controller = _trackedPositionController;
    if (controller == null || !identical(controller, _controller)) return;
    final value = _videoValue?.value;
    if (value == null || !value.initialized) return;
    _pictureInPictureSession?.setPlaybackState(
      isPlaying: value.isPlaying,
      isBuffering: value.isBuffering,
    );
    if (!_sourceStarted && value.initialized && value.isPlaying) {
      _sourceStarted = true;
      _saveLastResolvedSource(_current);
      _fallbackWaitTimer?.cancel();
      _fallbackWaitTimer = null;
      _pendingFallbackSourceId = null;
      _pendingFallbackError = null;
      if (_waitingForFallback || _retrying) {
        setState(() {
          _waitingForFallback = false;
          _retrying = false;
        });
      }
      // Only once the stream is actually running: arming on the resolved URL
      // alone would schedule renewals for a source that never played.
      _armRenewalTimer();
    }
    if (_pipBackground) _resumeAfterPictureInPicture = value.isPlaying;
    _updateRenewalStability(value);
    _lastPosition = value.position;
    _lastDuration = value.duration;
  }

  void _updateRenewalStability(AppPlayerValue value) {
    if (_consecutiveRenewals == 0) return;
    final stable = playbackIsStableForRenewalReset(
      isLive: _isLive,
      position: value.position,
      isPlaying: value.isPlaying,
      isBuffering: value.isBuffering,
    );
    if (!stable) {
      _renewalStableSince = null;
      return;
    }
    final since = _renewalStableSince ??= DateTime.now();
    if (DateTime.now().difference(since) < _renewalStabilityThreshold) return;
    _consecutiveRenewals = 0;
    _lastRenewalAt = null;
    _renewalStableSince = null;
    if (kDebugMode) {
      debugPrint('[PlaybackSources] renewal_counter_reset stable_playback');
    }
  }

  void _attachEventListener(AppPlayerController controller) {
    if (identical(controller, _controller) && _eventSubscription != null) {
      return;
    }
    unawaited(_eventSubscription?.cancel());
    final attempt = _playbackAttempt;
    _eventSubscription = controller.events.listen(
      (event) => _handlePlayerEvent(controller, attempt, event),
    );
    _playbackError = null;
  }

  void _handlePlayerEvent(
    AppPlayerController controller,
    int attempt,
    AppPlayerEvent event,
  ) {
    if (attempt != _playbackAttempt) return;
    if (event.type == AppPlayerEventType.pictureInPictureStarted) {
      final session = _pictureInPictureSession;
      _presentationBeforePictureInPicture = session?.isMinimized == true
          ? MiniPlayerMode.minimized
          : MiniPlayerMode.fullScreen;
      _resumeAfterPictureInPicture = controller.value.value.isPlaying;
      session?.setInteractionEnabled(false);
      if (mounted && !_pipBackground) {
        setState(() => _pipBackground = true);
        _syncRequestedLandscapeOrientation();
      }
      return;
    }
    if (event.type == AppPlayerEventType.pictureInPictureClosed) {
      _resumeAfterPictureInPicture = false;
      _restorePlayPending = false;
      _presentationBeforePictureInPicture = null;
      if (!mounted) return;
      final session = _pictureInPictureSession;
      if (session != null && identical(session.player, widget)) {
        session.detach(widget);
      } else {
        _popRoute();
      }
      return;
    }
    if (event.type == AppPlayerEventType.pictureInPictureRestore) {
      _restorePictureInPicturePlayer();
      return;
    }
    if (event.type == AppPlayerEventType.completed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            attempt == _playbackAttempt &&
            identical(controller, _controller)) {
          if (!_upNextDismissed && !_upNextPaused && _nextEpisode != null) {
            _playNextEpisode();
          } else {
            _showNextEpisode();
          }
        }
      });
      return;
    }
    if (event.type != AppPlayerEventType.error) return;
    final message = event.error?.toString();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          attempt != _playbackAttempt ||
          !identical(controller, _controller)) {
        return;
      }
      // A source that played and then failed is a working source with a URL
      // that stopped working — ExoPlayer reports a segment that rolled out of
      // a live window as a fatal source error, and the stream it was cut from
      // is still there. Recover it the way a stall is recovered; only a
      // source that never started is failed outright.
      if (_sourceStarted) {
        if (_isLive) {
          // Keep the native live player alive while it reports a transient
          // buffering/error event. Recreating the player here discards its
          // forward buffer and can turn a recoverable hiccup into a visible
          // loading loop. Manual retry/source switching remains available.
          if (kDebugMode) {
            debugPrint(
              '[PlaybackSources] live_playback_error_recovery_disabled '
              'error=${redactPlaybackLogText(message)}',
            );
          }
          return;
        }
        _recoverCurrentSource();
        return;
      }
      if (_pendingFallbackSourceId == _current.source.id) return;
      if (kDebugMode) {
        debugPrint(
          '[PlaybackSources] playback_failed '
          'source=${_current.source.providerId}/${_current.source.label} '
          'error=${redactPlaybackLogText(message)}',
        );
      }
      final sourceId = _current.source.id;
      final sourceCache = AppScope.of(context).sourceCache;
      if (_persistedResolvedSourceRecovery.shouldRefreshAfterStartupFailure(
        isPersistedSource: _persistedSourceId == sourceId,
        cache: sourceCache,
        ref: widget.media.ref,
        sourceId: sourceId,
      )) {
        // A saved URL may have expired while the app was closed. Resolve this
        // same descriptor once before falling back to another source.
        unawaited(_retryPlayback());
        return;
      }
      _failedSourceIds.add(_current.source.id);
      _fallBackBeforePlaybackStarts(message);
    });
  }

  /// Uses an already-resolved alternative immediately. When the player was
  /// opened on the first fast source, keep its background fan-out alive long
  /// enough for a later source to become the fallback instead of presenting a
  /// terminal error while it is still being resolved.
  void _fallBackBeforePlaybackStarts(String? message) {
    final nextIndex = nextUnfailedSourceIndex(
      sources: _resolvedSources,
      currentIndex: _currentIndex,
      failedSourceIds: _failedSourceIds,
    );
    if (nextIndex != null) {
      _logAndSwitchToFallback(nextIndex);
      return;
    }
    if (!_pendingSourcesSettled) {
      _pendingFallbackSourceId = _current.source.id;
      _pendingFallbackError = message;
      _fallbackWaitTimer?.cancel();
      _fallbackWaitTimer = Timer(_fallbackWaitDuration, _finishFallbackWait);
      setState(() {
        _waitingForFallback = true;
        _playbackError = null;
        _retrying = false;
      });
      return;
    }
    _showInitialPlaybackError(message);
  }

  void _continuePendingFallback() {
    final failedSourceId = _pendingFallbackSourceId;
    if (failedSourceId == null ||
        _sourceStarted ||
        _current.source.id != failedSourceId) {
      return;
    }
    final nextIndex = nextUnfailedSourceIndex(
      sources: _resolvedSources,
      currentIndex: _currentIndex,
      failedSourceIds: _failedSourceIds,
    );
    if (nextIndex != null) {
      _fallbackWaitTimer?.cancel();
      _fallbackWaitTimer = null;
      _pendingFallbackSourceId = null;
      _pendingFallbackError = null;
      _logAndSwitchToFallback(nextIndex);
      return;
    }
    if (_pendingSourcesSettled) {
      _fallbackWaitTimer?.cancel();
      _fallbackWaitTimer = null;
      final message = _pendingFallbackError;
      _pendingFallbackSourceId = null;
      _pendingFallbackError = null;
      _showInitialPlaybackError(message);
    }
  }

  void _logAndSwitchToFallback(int nextIndex) {
    if (kDebugMode) {
      debugPrint(
        '[PlaybackSources] playback_fallback '
        'from=${_current.source.providerId}/${_current.source.label} '
        'to=${_resolvedSources[nextIndex].source.providerId}/'
        '${_resolvedSources[nextIndex].source.label}',
      );
    }
    _switchToResolvedSource(nextIndex);
  }

  void _showInitialPlaybackError(String? message) {
    _fallbackWaitTimer?.cancel();
    _fallbackWaitTimer = null;
    setState(() {
      _waitingForFallback = false;
      _playbackError = (message == null || message.isEmpty)
          ? 'Playback failed.'
          : message;
      _retrying = false;
    });
  }

  Future<void> _retryPlayback() async {
    if (_controller == null || _retrying) return;
    final attempt = ++_playbackAttempt;
    final sourceId = _current.source.id;
    final scope = AppScope.of(context);
    _fallbackWaitTimer?.cancel();
    _fallbackWaitTimer = null;
    _pendingFallbackSourceId = null;
    _pendingFallbackError = null;
    _failedSourceIds.remove(_current.source.id);
    _renewalTimer?.cancel();
    _renewalTimer = null;
    _stallDetector.reset();
    _consecutiveRenewals = 0;
    _renewalStableSince = null;
    _sourceStarted = false;
    _lastLivePosition = null;
    setState(() {
      _waitingForFallback = false;
      _retrying = true;
      _playbackError = null;
    });
    _fallbackWaitTimer?.cancel();
    _fallbackWaitTimer = Timer(_fallbackWaitDuration, _finishRetryWait);
    try {
      final stream = await scope.registry.resolveSource(
        widget.media.ref,
        sourceId,
      );
      if (!PlaybackTarget.detect().canPlay(stream)) {
        throw StateError(
          'The refreshed source is not playable on this device.',
        );
      }
      if (!mounted || attempt != _playbackAttempt) return;
      final position = _isLive ? null : _positionForSourceSwitch();
      _detachPositionListener();
      setState(() {
        _pendingSwitchPosition = position;
        _resolvedSources[_currentIndex] = ResolvedSource(
          source: _current.source,
          stream: stream,
        );
        _sourceRevision++;
        _controller = null;
      });
      _saveLastResolvedSource(_resolvedSources[_currentIndex]);
      scope.sourceCache.promote(widget.media.ref, sourceId);
    } catch (_) {
      if (!mounted || attempt != _playbackAttempt) return;
      scope.sourceCache.removeLastResolved(widget.media.ref, sourceId);
      _fallbackWaitTimer?.cancel();
      _fallbackWaitTimer = null;
      setState(() {
        _retrying = false;
        _playbackError =
            'Source is unavailable. Try another source or retry later.';
      });
    }
  }

  /// Arms a swap to a freshly signed URL before the current one expires.
  ///
  /// Providers that sign a playback URL bake an absolute deadline into it;
  /// past that instant every request answers 403 and the player freezes
  /// without reporting anything. Renewing ahead of the deadline keeps
  /// playback continuous instead of recovering after the viewer has already
  /// seen a spinner.
  void _armRenewalTimer() {
    _renewalTimer?.cancel();
    _renewalTimer = null;
    final remaining = streamTimeToExpiry(_current.stream.url);
    if (remaining == null) return;
    _renewalTimer = Timer(
      renewalDelayFor(remaining),
      () => unawaited(_renewCurrentSource(reason: 'scheduled')),
    );
  }

  void _sampleForStall() {
    final controller = _controller;
    if (controller == null || !_sourceStarted || _renewing) return;
    final value = controller.value.value;
    if (!value.initialized) return;
    if (_isLive) {
      _sampleLiveBuffering(value);
      return;
    }
    _lastLivePosition = null;
    final stalled = _stallDetector.sample(
      position: value.position,
      bufferedPosition: value.bufferedPosition,
      isBuffering: value.isBuffering,
      isPlaying: value.isPlaying,
      now: DateTime.now(),
    );
    if (!stalled) return;
    _recoverCurrentSource();
  }

  void _sampleLiveBuffering(AppPlayerValue value) {
    final stalled = liveBufferingNeedsRecovery(
      position: value.position,
      bufferedPosition: value.bufferedPosition,
      bufferedRanges: value.bufferedRanges,
      previousPosition: _lastLivePosition,
      isPlaying: value.isPlaying,
      isBuffering: value.isBuffering,
    );
    _lastLivePosition = value.position;
    if (!stalled) {
      _liveBufferingSince = null;
      return;
    }
    final since = _liveBufferingSince ??= DateTime.now();
    final elapsed = DateTime.now().difference(since);
    if (elapsed < _liveBufferingRecoveryThreshold) return;
    _liveBufferingSince = null;
    if (kDebugMode) {
      debugPrint(
        '[PlaybackSources] live_buffering_recovery '
        'buffered_ms=${value.bufferedPosition.inMilliseconds} '
        'contiguous_buffered_ms=${liveContiguousForwardBuffer(position: value.position, bufferedPosition: value.bufferedPosition, bufferedRanges: value.bufferedRanges).inMilliseconds} '
        'is_buffering=${value.isBuffering} '
        'elapsed_ms=${elapsed.inMilliseconds}',
      );
    }
    _recoverCurrentSource();
  }

  /// Answers a source that has stopped delivering — a confirmed stall, or a
  /// failure reported after playback had started — by re-resolving it.
  ///
  /// Both arrive at the same place: the URL in hand no longer works. Live
  /// URLs are signed, per-edge and short-lived, and a re-resolve mints a new
  /// one on a different edge, so the remedy is a round trip to the extension
  /// rather than a message telling the viewer to pick another source.
  ///
  /// Renewing only helps when the URL was the problem. A source that fails
  /// again right after a fresh one was minted is broken at the far end, and
  /// repeating the round trip would keep the viewer on a dead stream
  /// indefinitely, so the source is abandoned after
  /// [_maxConsecutiveRenewals] tries inside [_renewalPatienceWindow].
  void _recoverCurrentSource() {
    // A failing player reports the same error many times a second. One
    // recovery is in flight at a time; the rest are the same news twice.
    if (_renewing) return;
    if (shouldFallbackAfterVODStall(
      isLive: _isLive,
      format: _current.stream.format,
    )) {
      _consecutiveRenewals = 0;
      _stallDetector.reset();
      if (kDebugMode) {
        debugPrint(
          '[PlaybackSources] vod_mp4_stall_fallback '
          'source=${_current.source.providerId}/${_current.source.label}',
        );
      }
      _fallBackAfterFailedRenewal(_current.source.id);
      return;
    }
    final since = _lastRenewalAt;
    final now = DateTime.now();
    _consecutiveRenewals =
        since != null && now.difference(since) < _renewalPatienceWindow
        ? _consecutiveRenewals + 1
        : 1;
    _lastRenewalAt = now;
    if (_consecutiveRenewals > _maxConsecutiveRenewals) {
      _consecutiveRenewals = 0;
      _stallDetector.reset();
      _fallBackAfterFailedRenewal(_current.source.id);
      return;
    }
    unawaited(_renewCurrentSource(reason: 'buffering'));
  }

  /// Re-resolves the source being watched and swaps the result in silently.
  ///
  /// Used both for a scheduled renewal and for a confirmed stall, because the
  /// remedy is the same: the URL in hand no longer works and only the
  /// extension can mint another. A source that cannot be re-resolved is
  /// handed to [_fallBackAfterFailedRenewal] rather than left frozen.
  Future<void> _renewCurrentSource({required String reason}) async {
    if (_renewing || _controller == null || !mounted) return;
    final stopwatch = Stopwatch()..start();
    _renewing = true;
    _liveBufferingSince = null;
    _renewalTimer?.cancel();
    _renewalTimer = null;
    final attempt = ++_playbackAttempt;
    final scope = AppScope.of(context);
    final sourceId = _current.source.id;
    _logRecovery(
      'renew_start reason=$reason '
      'source=${_current.source.providerId}/${_current.source.label}',
    );
    try {
      final stream = await scope.registry.resolveSource(
        widget.media.ref,
        sourceId,
      );
      _logRecovery(
        'renew_resolve_done elapsed=${stopwatch.elapsedMilliseconds}ms '
        'url=${safePlaybackUrlForLog(stream.url)}',
      );
      if (!PlaybackTarget.detect().canPlay(stream)) {
        throw StateError('The renewed source is not playable on this device.');
      }
      if (!mounted || attempt != _playbackAttempt) return;
      final position = _isLive ? null : _positionForSourceSwitch();
      _detachPositionListener();
      _logRecovery(
        'renew_detach_controller elapsed=${stopwatch.elapsedMilliseconds}ms',
      );
      _stallDetector.reset();
      _sourceStarted = false;
      _renewalStableSince = null;
      _lastLivePosition = null;
      setState(() {
        _pendingSwitchPosition = position;
        _resolvedSources[_currentIndex] = ResolvedSource(
          source: _current.source,
          stream: stream,
        );
        _sourceRevision++;
        _playbackError = null;
        _controller = null;
      });
      _logRecovery(
        'renew_state_committed elapsed=${stopwatch.elapsedMilliseconds}ms '
        'revision=$_sourceRevision',
      );
      _saveLastResolvedSource(_resolvedSources[_currentIndex]);
      scope.sourceCache.promote(widget.media.ref, sourceId);
    } catch (_) {
      if (!mounted || attempt != _playbackAttempt) return;
      scope.sourceCache.removeLastResolved(widget.media.ref, sourceId);
      _fallBackAfterFailedRenewal(sourceId);
    } finally {
      _logRecovery('renew_done elapsed=${stopwatch.elapsedMilliseconds}ms');
      _renewing = false;
    }
  }

  void _logRecovery(String message) {
    if (!kDebugMode) return;
    debugPrint('[PlaybackSources] $message');
  }

  /// Moves to the next source that has not failed, or surfaces the error.
  ///
  /// Unlike the pre-start fallback this runs mid-playback, so the source that
  /// just died is recorded as failed first — walking back onto it would stall
  /// again within seconds.
  void _fallBackAfterFailedRenewal(String sourceId) {
    _failedSourceIds.add(sourceId);
    final nextIndex = nextUnfailedSourceIndex(
      sources: _resolvedSources,
      currentIndex: _currentIndex,
      failedSourceIds: _failedSourceIds,
    );
    if (nextIndex != null) {
      _stallDetector.reset();
      _switchToResolvedSource(nextIndex);
      return;
    }
    setState(() {
      _playbackError = 'This source stopped responding. Try another source.';
      _retrying = false;
    });
  }

  PlaybackStartPosition? get _startPosition {
    if (_isLive) return null;
    final pending = _pendingSwitchPosition;
    if (pending != null) return PlaybackStartPosition.exact(pending);
    final progress = _library?.recordFor(widget.media.ref)?.progress;
    return !_hasResumed && progress != null
        ? PlaybackStartPosition.resume(progress)
        : null;
  }

  void _reportProgress() {
    if (_isLive || _lastPosition == null) return;
    _library?.recordWatched(
      widget.media.item,
      progress: _lastPosition,
      duration: _lastDuration,
    );
  }

  void _showNextEpisode() {
    if (_nextEpisode == null || _showUpNext || _upNextDismissed) return;
    setState(() {
      _showUpNext = true;
      _upNextPaused = false;
    });
  }

  void _playNextEpisode() {
    final next = _nextEpisode;
    if (_advancing || next == null) return;
    _beginEpisodeTransition(next.item);
  }

  void _playEpisode(PlayerEpisodeEntry entry) {
    if (_advancing) return;
    final current = widget.media.item;
    if (current is! EpisodeItemV2) return;
    _beginEpisodeTransition(episodeItemFrom(current, entry.group, entry.index));
  }

  void _beginEpisodeTransition(MediaItemV2 item) {
    _advancing = true;
    final preferredSource = _current.source;
    if (mounted) {
      setState(() => _episodeTransitioning = true);
    }
    unawaited(() async {
      // The loading route is deliberately pushed while source discovery is in
      // flight. Pause the old native controller first so the previous episode
      // cannot keep playing underneath that route or through the handoff.
      final controller = _controller;
      if (controller?.value.value.isPlaying == true) {
        try {
          await controller!.pause();
        } catch (_) {
          // A controller can be disposed by PiP/route teardown during the
          // handoff; source playback should still proceed.
        }
      }
      if (!mounted) return;
      try {
        await playItemV2(
          context,
          item,
          episodeGuide: widget.episodeGuide,
          replaceCurrent: true,
          preferredSource: preferredSource,
        );
      } finally {
        // On success this page is removed. On failure, make the old page
        // usable again without leaving the rail permanently locked.
        if (mounted) {
          setState(() {
            _advancing = false;
            _episodeTransitioning = false;
          });
        }
      }
    }());
  }

  void _popRoute() {
    if (!mounted) return;
    final session = _pictureInPictureSession;
    if (session != null && identical(session.player, widget)) {
      session.detach(widget);
      return;
    }
    if (_allowPop) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  Future<void> _handleBack() async {
    if (_backInFlight) return;
    _backInFlight = true;
    final controller = _controller;
    final started = _sourceStarted;
    if (kDebugMode) {
      debugPrint(
        '[PlayerPiP] back_request started=$started '
        'mode=${_pictureInPictureSession?.mode.name}',
      );
    }
    if (controller?.isFullScreen == true) {
      unawaited(controller!.exitFullScreen());
    }
    if (!mounted) {
      _backInFlight = false;
      return;
    }
    if (!started) {
      _backInFlight = false;
      _popRoute();
      return;
    }

    _resumeAfterPictureInPicture = false;
    _restorePlayPending = false;
    _pictureInPictureSession?.minimize();
    _syncRequestedLandscapeOrientation();
    // Back is an in-app presentation change, not a native PiP request. Keep
    // automatic PiP eligible so backgrounding from the mini-player can still
    // promote the active full-video session into a floating native window.
    await _syncNativePictureInPictureAllowed();
    _backInFlight = false;
  }

  void _minimizePlayer() {
    if (!mounted) return;
    if (!_sourceStarted) {
      unawaited(_handleBack());
      return;
    }
    _pictureInPictureSession?.minimize();
    _syncRequestedLandscapeOrientation();
    unawaited(_syncNativePictureInPictureAllowed());
  }

  void _toggleLandscapeOrientation() {
    _orientationCoordinator.toggle(
      activeFullPlayer: _isActiveFullPlayer,
      pipBackground: _pipBackground,
    );
    if (mounted) setState(() {});
  }

  bool get _isActiveFullPlayer =>
      _pictureInPictureSession?.isFullScreen ?? true;

  void _syncRequestedLandscapeOrientation() {
    final activeFullPlayer = _isActiveFullPlayer;
    _orientationCoordinator.sync(
      activeFullPlayer: activeFullPlayer,
      pipBackground: _pipBackground,
      releaseDelay: activeFullPlayer ? Duration.zero : _orientationReleaseDelay,
    );
  }

  void _onPictureInPicturePresentationChanged() {
    _syncRequestedLandscapeOrientation();
    unawaited(_syncNativePictureInPictureAllowed());
  }

  Future<void> _syncNativePictureInPictureAllowed() async {
    if (!mounted) return;
    final controller = _controller;
    final policy = controller is AppPlayerPictureInPicturePolicy
        ? controller as AppPlayerPictureInPicturePolicy
        : null;
    if (policy == null) return;
    final preference = AppScope.of(
      context,
    ).pictureInPicturePreferenceController;
    try {
      await policy.setPictureInPictureAllowed(preference.enabled);
    } catch (error) {
      if (kDebugMode) {
        debugPrint('[PlayerPiP] eligibility_update_error=$error');
      }
    }
  }

  void _restorePictureInPicturePlayer() {
    if (!mounted) return;
    final previousPresentation = _presentationBeforePictureInPicture;
    _presentationBeforePictureInPicture = null;
    final shouldResume =
        _resumeAfterPictureInPicture ||
        _controller?.value.value.isPlaying == true;
    _resumeAfterPictureInPicture = false;
    _restorePlayPending = shouldResume;
    final session = _pictureInPictureSession;
    if (previousPresentation == MiniPlayerMode.minimized) {
      session?.minimize();
    } else if (previousPresentation == MiniPlayerMode.fullScreen) {
      session?.restore();
    }
    session?.setInteractionEnabled(true);
    setState(() => _pipBackground = false);
    // Keep the player in its original route for the whole PiP lifecycle.
    // Reparenting a UiKitView can preserve AVPlayer audio while losing the
    // native video surface on iOS.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || _pipBackground) return;
      _syncRequestedLandscapeOrientation();
      final controller = _controller;
      final restorer = controller is AppPlayerPictureInPictureRestorer
          ? controller as AppPlayerPictureInPictureRestorer
          : null;
      if (restorer != null) await restorer.completePictureInPictureRestore();
      if (mounted && !_pipBackground) {
        await _syncNativePictureInPictureAllowed();
      }
      if (mounted && _restorePlayPending && !_pipBackground) {
        _restorePlayPending = false;
        unawaited(controller?.play());
      }
    });
  }

  void _togglePlayback() {
    final controller = _controller;
    if (controller == null) return;
    if (controller.value.value.isPlaying) {
      unawaited(controller.pause());
    } else {
      unawaited(controller.play());
    }
  }

  void _seekBy(Duration offset) {
    final controller = _controller;
    if (controller == null || _isLive) return;
    final target = controller.value.value.position + offset;
    unawaited(
      controller.seekTo(target < Duration.zero ? Duration.zero : target),
    );
  }

  void _toggleFullScreen() {
    if (!_supportsFullScreen) return;
    final controller = _controller;
    if (controller != null) unawaited(controller.toggleFullScreen());
  }

  void _openMultiView() {
    final event = widget.media.item;
    if (event is! EventItemV2 || !_isLive) return;
    final navigator = Navigator.of(context);
    final scope = AppScope.of(context);
    void restoreSinglePlayer(
      EventItemV2 selectedEvent,
      ResolvedSource selectedSource, {
      required bool minimize,
    }) {
      final player = PlayerPage(
        key: GlobalKey(),
        item: selectedEvent,
        resolvedSources: [selectedSource],
        persistedSourceId: selectedSource.source.id,
      );
      scope.pictureInPictureSession.attach(player);
      if (minimize) scope.pictureInPictureSession.minimize();
      if (navigator.canPop()) navigator.pop();
    }

    // PlayerPage is hosted by the persistent mini-player overlay rather than
    // being a normal route. Release that surface before pushing the actual
    // multi-view route, otherwise the old native player remains above it.
    _pictureInPictureSession?.detach(widget);
    navigator.push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'multi-view'),
        builder: (_) => MultiViewPage(
          initialEvent: event,
          initialSource: _current,
          onOpenSinglePlayer: (selectedEvent, selectedSource) {
            restoreSinglePlayer(selectedEvent, selectedSource, minimize: false);
          },
          onExitToMiniPlayer: (selectedEvent, selectedSource) =>
              restoreSinglePlayer(
                selectedEvent,
                selectedSource,
                minimize: true,
              ),
        ),
      ),
    );
  }

  void _toggleFit() {
    final controller = _controller;
    final position = !_isLive ? controller?.value.value.position : null;
    _pendingFitPosition = position;
    _pendingFitController = controller;
    final next = _fitMode.toggled;
    setState(() => _fitMode = next);
    _syncSystemUi();
    if (controller != null) unawaited(controller.setFit(next));
    if (position != null && controller != null) {
      unawaited(_restoreFitPosition(controller, position));
    }
  }

  Future<void> _restoreFitPosition(
    AppPlayerController controller,
    Duration position,
  ) async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (!mounted ||
        _pendingFitPosition != position ||
        !identical(_pendingFitController, controller) ||
        !identical(_controller, controller)) {
      return;
    }
    _pendingFitPosition = null;
    _pendingFitController = null;
    final current = controller.value.value.position;
    final delta = current >= position ? current - position : position - current;
    if (delta > const Duration(seconds: 1)) {
      unawaited(controller.seekTo(position));
    }
  }

  void _syncSystemUi() {
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    _landscape = landscape;
    final immersive = _fitMode == PlayerFitMode.cover || landscape;
    if (_systemUiImmersive == immersive) return;
    _systemUiImmersive = immersive;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _systemUiImmersive != immersive) return;
      unawaited(
        SystemChrome.setEnabledSystemUIMode(
          immersive ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
        ),
      );
    });
  }

  void _switchToResolvedSource(int index) {
    if (index < 0 ||
        index >= _resolvedSources.length ||
        index == _currentIndex) {
      return;
    }
    final picked = _resolvedSources[index];
    final position = _isLive ? null : _positionForSourceSwitch();
    _detachPositionListener();
    _renewalTimer?.cancel();
    _renewalTimer = null;
    _stallDetector.reset();
    _liveBufferingSince = null;
    _lastLivePosition = null;
    _fallbackWaitTimer?.cancel();
    _fallbackWaitTimer = null;
    _consecutiveRenewals = 0;
    _renewalStableSince = null;
    _failedSourceIds.remove(picked.source.id);
    _pendingFallbackSourceId = null;
    _pendingFallbackError = null;
    unawaited(_eventSubscription?.cancel());
    _eventSubscription = null;
    setState(() {
      _waitingForFallback = false;
      _pendingSwitchPosition = position;
      _currentIndex = index;
      _playbackAttempt++;
      _playbackError = null;
      _retrying = false;
      _sourceRevision++;
      _sourceStarted = false;
      _pendingFitPosition = null;
      _pendingFitController = null;
      _controller = null;
      _onVisibilityChanged = null;
    });
    _pictureInPictureSession?.setPlaybackState(
      isPlaying: false,
      isBuffering: true,
    );
    final sourceCache = AppScope.of(context).sourceCache;
    sourceCache.promote(widget.media.ref, picked.source.id);
    // Do not persist a manually selected URL until the replacement controller
    // has actually started. If startup fails, treating this unplayed URL as a
    // Continue Watching cache hit would route the error into "Refreshing
    // stream…" instead of the normal source fallback/error path.
  }

  void _saveLastResolvedSource(ResolvedSource resolved) {
    if (_isLive) return;
    AppScope.of(
      context,
    ).sourceCache.saveLastResolved(widget.media.ref, resolved);
    _persistedSourceId = resolved.source.id;
  }

  void _finishFallbackWait() {
    _fallbackWaitTimer = null;
    if (!mounted || !_waitingForFallback || _sourceStarted) return;
    if (kDebugMode) {
      debugPrint(
        '[PlaybackSources] fallback_wait_timeout '
        'timeout_s=${_fallbackWaitDuration.inSeconds}',
      );
    }
    final message = _pendingFallbackError;
    _pendingFallbackSourceId = null;
    _pendingFallbackError = null;
    _showInitialPlaybackError(message);
  }

  void _finishRetryWait() {
    _fallbackWaitTimer = null;
    if (!mounted || !_retrying || _sourceStarted) return;
    _playbackAttempt++;
    if (kDebugMode) {
      debugPrint(
        '[PlaybackSources] retry_timeout '
        'timeout_s=${_fallbackWaitDuration.inSeconds}',
      );
    }
    setState(() {
      _retrying = false;
      _playbackError =
          'Source is unavailable. Try another source or retry later.';
    });
  }

  Duration? _positionForSourceSwitch() {
    final value = _controller?.value.value;
    if (value != null && value.initialized) return value.position;
    return _lastPosition;
  }

  Future<void> _changeSource() async {
    final modalContext =
        AppScope.of(
          context,
        ).pictureInPictureSession.modalNavigatorKey.currentContext ??
        context;
    final picked = await showModalBottomSheet<ResolvedSource>(
      context: modalContext,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        // The sheet can rebuild after the player route has been dismissed.
        // Resolve inherited dependencies from the sheet itself, not from the
        // PlayerPage State whose context may already be defunct.
        final registry = AppScope.of(sheetContext).registry;
        final providerNames = {
          for (final manifest in registry.installed)
            for (final provider in manifest.providers)
              if (provider.name != null) provider.id: provider.name!,
        };
        return PlayerSourcePickerSheet(
          resolvedSources: _resolvedSources,
          current: _current,
          providerNames: providerNames,
          onRefresh: _refetchSources,
          backgroundSourceLoading: _backgroundSourceLoading,
          resolvedSourcesListenable: _resolvedSourcesListenable,
        );
      },
    );
    if (!mounted || picked == null) return;
    final index = _resolvedSources.indexOf(picked);
    if (index < 0 || index == _currentIndex) return;
    _switchToResolvedSource(index);
  }

  Widget _controlsFor(AppPlayerController? controller) =>
      PlayerPlaybackControls(
        controller: controller,
        onVisibilityChanged: _onVisibilityChanged ?? (_) {},
        media: widget.media,
        resolvedSources: _resolvedSources,
        currentIndex: _currentIndex,
        onChangeSource: _changeSource,
        onMinimize: _minimizePlayer,
        fitMode: _fitMode,
        onToggleFit: _toggleFit,
        landscapeLocked: _orientationCoordinator.landscapeRequested,
        onToggleLandscape: _toggleLandscapeOrientation,
        isLive: _isLive,
        playbackSegments: _playbackSegments,
        episodeGuide: widget.episodeGuide,
        upNextV2: _showUpNext ? _nextEpisode : null,
        upNextPaused: _upNextPaused,
        onNearEnd: _showNextEpisode,
        onPlayEpisode: _playEpisode,
        onPlayNext: _playNextEpisode,
        onOpenMultiView: _isLive && widget.media.item is EventItemV2
            ? _openMultiView
            : null,
        onSettling: (grace) => _stallDetector.defer(grace, now: DateTime.now()),
        onPauseUpNext: () => setState(() => _upNextPaused = true),
        onCancelUpNext: () => setState(() {
          _showUpNext = false;
          _upNextPaused = false;
          _upNextDismissed = true;
        }),
      );

  Widget _fullScreenControls() {
    final session = _pictureInPictureSession;
    final controls = _controlsFor(_controller);
    if (session == null) return controls;
    return ValueListenableBuilder<MiniPlayerPresentationState>(
      valueListenable: session.presentation,
      builder: (context, state, child) =>
          state.showControls ? child! : const SizedBox.shrink(),
      child: controls,
    );
  }

  /// The external track to hand the player for the current source.
  ///
  /// An explicit pick for this item always wins — the viewer chose it. Failing
  /// that, an external track only stands in when the source itself carries
  /// nothing in the preferred language: a source's own subtitles are timed
  /// against its own encode, so they are the better match wherever they exist.
  /// Recomputed per source, because switching source changes the answer.
  SubtitleTrack? _externalSubtitle(BuildContext context) {
    final preference = AppScope.of(context).subtitlePreferenceController;
    final explicit = preference.rememberedExternalSubtitle(widget.media.ref);
    if (explicit != null) return explicit;
    if (_isLive || preference.isSatisfiedBy(_current.stream.subtitles)) {
      return null;
    }
    return preference.preferredExternalMatch(widget.media.ref);
  }

  Widget _buildPlayer(BuildContext context) =>
      AppScope.of(context).playerBuilder(
        context,
        _current.stream,
        isLive: _isLive,
        key: ValueKey('${_current.source.id}:$_sourceRevision'),
        preferredSubtitleLanguage: AppScope.of(
          context,
        ).subtitlePreferenceController.languageCode,
        startPosition: _startPosition,
        preferredQualityMaxHeight: AppScope.of(
          context,
        ).qualityPreferenceController.maxHeight,
        subtitleAppearance: AppScope.of(
          context,
        ).subtitlePreferenceController.appearance,
        preferredExternalSubtitle: _externalSubtitle(context),
        onControllerCreated: (value) {
          final controller = value as AppPlayerController?;
          _controller = controller;
          _pictureInPictureSession?.setPlaybackToggleRequested(
            controller == null ? null : _togglePlayback,
          );
          if (controller != null) {
            _pictureInPictureSession?.setPlaybackState(
              isPlaying: controller.value.value.isPlaying,
              isBuffering: controller.value.value.isBuffering,
            );
            _attachEventListener(controller);
            unawaited(controller.setFit(_fitMode));
            unawaited(_syncNativePictureInPictureAllowed());
          }
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() {});
          });
        },
        onPlaybackReady: (value) {
          final controller = value as AppPlayerController?;
          if (controller != null) {
            _hasResumed = true;
            _pendingSwitchPosition = null;
            _trackPosition(controller);
          }
        },
        customControlsBuilder: (context, value, onVisibilityChanged) {
          final controller = value as AppPlayerController?;
          _controller ??= controller;
          _onVisibilityChanged = onVisibilityChanged;
          return controller?.isFullScreen == true
              ? _controlsFor(controller)
              : const SizedBox.shrink();
        },
      );

  Widget _playerViewport(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final maxHeight = constraints.maxHeight;
        final cover = _fitMode == PlayerFitMode.cover;
        final viewportRatio = maxHeight > 0 ? maxWidth / maxHeight : 16 / 9;
        final ratio = cover ? viewportRatio : 16 / 9;
        final controller = _controller;
        if (controller != null &&
            (!identical(controller, _aspectRatioController) ||
                _appliedViewportAspectRatio != ratio)) {
          _aspectRatioController = controller;
          _appliedViewportAspectRatio = ratio;
          unawaited(controller.setViewportAspectRatio(ratio));
        }
        final player = _buildPlayer(context);
        final playerWithSubtitleVisibility =
            ValueListenableBuilder<MiniPlayerPresentationState>(
              valueListenable: _pictureInPictureSession!.presentation,
              builder: (context, state, _) => PlayerSubtitleVisibility(
                showSubtitles: state.mode == MiniPlayerMode.fullScreen,
                child: player,
              ),
            );
        return SizedBox(
          width: maxWidth,
          height: maxHeight,
          child: playerWithSubtitleVisibility,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Keep this wrapper in the tree even when PiP is inactive. Adding it only
    // when PiP starts changes the native surface's element ancestry, which can
    // recreate the player: AVPlayer audio survives, but the video surface is
    // then lost when PiP expands.
    return ClipRect(
      clipper: _PictureInPictureClipper(hidden: _pipBackground),
      child: IgnorePointer(
        ignoring: _pipBackground,
        child: _buildInteractivePlayer(context),
      ),
    );
  }

  Widget _buildInteractivePlayer(BuildContext context) {
    final showSourceLoading =
        _episodeTransitioning ||
        _waitingForFallback ||
        (_retrying && !_sourceStarted);
    final showPlaybackError =
        _playbackError != null &&
        !(_pictureInPictureSession?.isMinimized ?? false);
    return PopScope<void>(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_handleBack());
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.space): _togglePlayback,
          const SingleActivator(LogicalKeyboardKey.keyJ): () =>
              _seekBy(const Duration(seconds: -10)),
          const SingleActivator(LogicalKeyboardKey.keyL): () =>
              _seekBy(const Duration(seconds: 10)),
          const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
              _seekBy(const Duration(seconds: -5)),
          const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
              _seekBy(const Duration(seconds: 5)),
          if (_supportsFullScreen)
            const SingleActivator(LogicalKeyboardKey.keyF): _toggleFullScreen,
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              unawaited(_controller?.exitFullScreen()),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: Stack(
              children: [
                Positioned.fill(child: _playerBackground()),
                _playerViewport(context),
                if (!showSourceLoading)
                  Positioned.fill(child: _fullScreenControls()),
                if (showSourceLoading)
                  Positioned.fill(
                    child: PlayerFallbackLoadingOverlay(
                      onBack: _handleBack,
                      message: _retrying
                          ? 'Refreshing stream…'
                          : _episodeTransitioning
                          ? 'Opening episode…'
                          : 'Finding another source…',
                    ),
                  ),
                if (showPlaybackError)
                  Positioned.fill(
                    child: PlayerPlaybackErrorOverlay(
                      message: _playbackError!,
                      retrying: _retrying,
                      onRetry: _retryPlayback,
                      // Continue Watching can start with one cached resolved
                      // source. If that URL expires, the picker still needs
                      // to be reachable so its refresh action can discover
                      // other providers.
                      onChangeSource: _changeSource,
                      onBack: _handleBack,
                      onHide: () => setState(() => _playbackError = null),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _playerBackground() {
    final session = _pictureInPictureSession;
    if (session == null) return const ColoredBox(color: Colors.black);
    return ValueListenableBuilder<MiniPlayerPresentationState>(
      valueListenable: session.presentation,
      builder: (context, state, _) => ColoredBox(
        color: state.showBackground ? Colors.black : Colors.transparent,
      ),
    );
  }
}

class _PictureInPictureClipper extends CustomClipper<Rect> {
  const _PictureInPictureClipper({required this.hidden});

  final bool hidden;

  @override
  Rect getClip(Size size) => hidden ? Rect.zero : Offset.zero & size;

  @override
  bool shouldReclip(_PictureInPictureClipper oldClipper) =>
      hidden != oldClipper.hidden;
}
