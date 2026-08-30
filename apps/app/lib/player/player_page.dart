import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';

import '../app_scope.dart';
import '../detail/episode_target_v2.dart';
import '../library/library_controller.dart';
import '../platform/playback_capability.dart';
import '../theme/tokens.dart';
import 'controls/player_playback_controls.dart';
import 'models/playback_media.dart';
import 'models/app_player_controller.dart';
import 'models/resolved_source.dart';
import 'sheets/player_selection_sheets.dart';
import 'state/playback_stall_detector.dart';
import 'state/source_fallback_policy.dart';
import 'state/stream_expiry.dart';
import 'widgets/player_overlays.dart';
import 'workflow/play_item.dart';

export 'models/resolved_source.dart' show ResolvedSource, mergeResolvedSources;

const Duration _minResumeProgress = Duration(seconds: 5);
const Duration _resumeEndGuard = Duration(seconds: 30);
const Duration _progressInterval = Duration(seconds: 10);

/// How often playback is sampled for a stall.
///
/// Frequent enough that [PlaybackStallDetector.threshold] is the thing that
/// decides when to act, rather than the sampling rate.
const Duration _stallSampleInterval = Duration(seconds: 2);

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

class PlayerPage extends StatefulWidget {
  PlayerPage({
    super.key,
    required MediaItemV2 item,
    required this.resolvedSources,
    this.episodeGuide,
    this.pendingSources,
    this.returnToDetail = false,
  }) : media = PlaybackMedia(item),
       assert(resolvedSources.isNotEmpty, 'Must provide at least one source');

  final PlaybackMedia media;
  final List<ResolvedSource> resolvedSources;
  final EpisodeGuide? episodeGuide;
  final Stream<ResolvedSource>? pendingSources;
  final bool returnToDetail;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  late int _currentIndex;
  late List<ResolvedSource> _resolvedSources;
  Future<List<ResolvedSource>>? _refetch;
  late final NextEpisodeV2? _nextEpisode;
  bool _showUpNext = false;
  bool _upNextPaused = false;
  bool _advancing = false;
  LibraryController? _library;
  Timer? _progressTimer;
  Timer? _stallTimer;
  Timer? _renewalTimer;
  final PlaybackStallDetector _stallDetector = PlaybackStallDetector();
  bool _renewing = false;
  DateTime? _lastRenewalAt;
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
  int _sourceRevision = 0;
  int _playbackAttempt = 0;
  final Set<String> _failedSourceIds = <String>{};
  bool _sourceStarted = false;
  PlayerFitMode _fitMode = PlayerFitMode.contain;
  AppPlayerController? _aspectRatioController;
  double? _appliedViewportAspectRatio;
  bool? _systemUiImmersive;
  bool? _landscape;
  AppPlayerController? _controller;
  StreamSubscription<AppPlayerEvent>? _eventSubscription;
  void Function(bool visibility)? _onVisibilityChanged;

  bool get _isLive => widget.media.isLive;
  bool get _supportsFullScreen => defaultTargetPlatform == TargetPlatform.macOS;
  ResolvedSource get _current => _resolvedSources[_currentIndex];

  @override
  void initState() {
    super.initState();
    _currentIndex = 0;
    _resolvedSources = widget.resolvedSources;
    final item = widget.media.item;
    _nextEpisode = item is EpisodeItemV2 && widget.episodeGuide != null
        ? nextEpisodeOfV2(item, widget.episodeGuide!)
        : null;
    final pending = widget.pendingSources;
    if (pending != null) unawaited(_addPendingSources(pending));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _library = AppScope.of(context).libraryController;
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
    await for (final source in pending) {
      if (!mounted) return;
      final playingId = _current.source.id;
      final merged = mergeResolvedSources(_resolvedSources, [source]);
      final cache = AppScope.of(context).sourceCache;
      cache.store(widget.media.ref, merged);
      cache.promote(widget.media.ref, playingId);
      setState(() {
        _resolvedSources = merged;
        _currentIndex = merged.indexWhere(
          (source) => source.source.id == playingId,
        );
        if (_currentIndex < 0) _currentIndex = 0;
      });
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

    // Merge, never replace: the source being watched keeps playing and keeps
    // its place, exactly as it does for sources that settle late.
    final playingId = _current.source.id;
    final merged = mergeResolvedSources(_resolvedSources, found);
    scope.sourceCache.store(widget.media.ref, merged);
    scope.sourceCache.promote(widget.media.ref, playingId);
    setState(() {
      _resolvedSources = merged;
      _currentIndex = merged.indexWhere(
        (source) => source.source.id == playingId,
      );
      if (_currentIndex < 0) _currentIndex = 0;
    });
    return merged;
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _stallTimer?.cancel();
    _renewalTimer?.cancel();
    _detachPositionListener();
    unawaited(_eventSubscription?.cancel());
    _reportProgress();
    final landscape = _landscape == true;
    unawaited(
      SystemChrome.setEnabledSystemUIMode(
        landscape ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
      ),
    );
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
    if (!_sourceStarted) {
      _sourceStarted = true;
      // Only once the stream is actually running: arming on the resolved URL
      // alone would schedule renewals for a source that never played.
      _armRenewalTimer();
    }
    _lastPosition = value.position;
    _lastDuration = value.duration;
    final position = sourceSwitchSeekPosition(
      isLive: _isLive,
      previousPosition: _pendingSwitchPosition,
      duration: value.duration,
    );
    if (position != null) {
      _pendingSwitchPosition = null;
      _lastPosition = position;
      unawaited(controller.seekTo(position));
    }
    if (!_hasResumed) {
      _hasResumed = true;
      _resumeSavedPosition(value.duration);
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
    if (event.type == AppPlayerEventType.completed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            attempt == _playbackAttempt &&
            identical(controller, _controller)) {
          _showNextEpisode();
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
        _recoverCurrentSource();
        return;
      }
      _failedSourceIds.add(_current.source.id);
      final nextIndex = nextUnfailedSourceIndex(
        sources: _resolvedSources,
        currentIndex: _currentIndex,
        failedSourceIds: _failedSourceIds,
      );
      if (nextIndex != null) {
        _switchToResolvedSource(nextIndex);
        return;
      }
      setState(() {
        _playbackError = (message == null || message.isEmpty)
            ? 'Playback failed.'
            : message;
        _retrying = false;
      });
    });
  }

  Future<void> _retryPlayback() async {
    if (_controller == null || _retrying) return;
    final attempt = ++_playbackAttempt;
    _failedSourceIds.remove(_current.source.id);
    _renewalTimer?.cancel();
    _renewalTimer = null;
    _stallDetector.reset();
    _consecutiveRenewals = 0;
    _sourceStarted = false;
    setState(() {
      _retrying = true;
      _playbackError = null;
    });
    try {
      final scope = AppScope.of(context);
      final stream = await scope.registry.resolveSource(
        widget.media.ref,
        _current.source.id,
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
        _retrying = false;
      });
      scope.sourceCache.store(widget.media.ref, _resolvedSources);
    } catch (_) {
      if (!mounted || attempt != _playbackAttempt) return;
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
      () => unawaited(_renewCurrentSource()),
    );
  }

  void _sampleForStall() {
    final controller = _controller;
    if (controller == null || !_sourceStarted || _renewing) return;
    final value = controller.value.value;
    if (!value.initialized) return;
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
    unawaited(_renewCurrentSource());
  }

  /// Re-resolves the source being watched and swaps the result in silently.
  ///
  /// Used both for a scheduled renewal and for a confirmed stall, because the
  /// remedy is the same: the URL in hand no longer works and only the
  /// extension can mint another. A source that cannot be re-resolved is
  /// handed to [_fallBackAfterFailedRenewal] rather than left frozen.
  Future<void> _renewCurrentSource() async {
    if (_renewing || _controller == null || !mounted) return;
    _renewing = true;
    _renewalTimer?.cancel();
    _renewalTimer = null;
    final attempt = ++_playbackAttempt;
    final scope = AppScope.of(context);
    final sourceId = _current.source.id;
    try {
      final stream = await scope.registry.resolveSource(
        widget.media.ref,
        sourceId,
      );
      if (!PlaybackTarget.detect().canPlay(stream)) {
        throw StateError('The renewed source is not playable on this device.');
      }
      if (!mounted || attempt != _playbackAttempt) return;
      final position = _isLive ? null : _positionForSourceSwitch();
      _detachPositionListener();
      _stallDetector.reset();
      _sourceStarted = false;
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
      scope.sourceCache.store(widget.media.ref, _resolvedSources);
    } catch (_) {
      if (!mounted || attempt != _playbackAttempt) return;
      _fallBackAfterFailedRenewal(sourceId);
    } finally {
      _renewing = false;
    }
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

  void _resumeSavedPosition(Duration? duration) {
    if (_isLive || _controller == null) return;
    final progress = _library?.recordFor(widget.media.ref)?.progress;
    if (progress == null || progress < _minResumeProgress) return;
    if (duration != null && duration - progress < _resumeEndGuard) return;
    unawaited(_controller!.seekTo(progress));
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
    if (_nextEpisode == null || _showUpNext) return;
    setState(() {
      _showUpNext = true;
      _upNextPaused = false;
    });
  }

  void _playNextEpisode() {
    final next = _nextEpisode;
    if (_advancing || next == null) return;
    _advancing = true;
    unawaited(
      playItemV2(
        context,
        next.item,
        episodeGuide: widget.episodeGuide,
        replaceCurrent: true,
      ),
    );
  }

  void _dismiss(AppPlayerController? controller) {
    if (controller?.isFullScreen == true) {
      unawaited(controller!.exitFullScreen());
    }
    Navigator.of(context).pop();
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
    _consecutiveRenewals = 0;
    _failedSourceIds.remove(picked.source.id);
    unawaited(_eventSubscription?.cancel());
    _eventSubscription = null;
    setState(() {
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
    AppScope.of(
      context,
    ).sourceCache.promote(widget.media.ref, picked.source.id);
  }

  Duration? _positionForSourceSwitch() {
    final value = _controller?.value.value;
    if (value != null && value.initialized) return value.position;
    return _lastPosition;
  }

  Future<void> _changeSource() async {
    final picked = await showModalBottomSheet<ResolvedSource>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) {
        final registry = AppScope.of(context).registry;
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
        onBack: () => _dismiss(controller),
        onToggleFullScreen: _supportsFullScreen ? _toggleFullScreen : null,
        fitMode: _fitMode,
        onToggleFit: _toggleFit,
        isLive: _isLive,
        episodeGuide: widget.episodeGuide,
        upNextV2: _showUpNext ? _nextEpisode : null,
        upNextPaused: _upNextPaused,
        onNearEnd: _showNextEpisode,
        onManualNext: _nextEpisode == null ? null : _playNextEpisode,
        onPlayNext: _playNextEpisode,
        onPauseUpNext: () => setState(() => _upNextPaused = true),
        onCancelUpNext: () => setState(() {
          _showUpNext = false;
          _upNextPaused = false;
        }),
      );

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
        subtitleAppearance: AppScope.of(
          context,
        ).subtitlePreferenceController.appearance,
        preferredExternalSubtitle: _externalSubtitle(context),
        onControllerCreated: (value) {
          _controller = value as AppPlayerController?;
          if (_controller != null) {
            _attachEventListener(_controller!);
            unawaited(_controller!.setFit(_fitMode));
          }
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() {});
          });
        },
        onPlaybackReady: (value) {
          final controller = value as AppPlayerController?;
          if (controller != null) _trackPosition(controller);
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
        final containWidth = maxHeight > 0 && viewportRatio > 16 / 9
            ? maxHeight * (16 / 9)
            : maxWidth;
        final containHeight = containWidth / (16 / 9);
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
        return Align(
          alignment: Alignment.center,
          child: SizedBox(
            width: cover ? maxWidth : containWidth,
            height: cover ? maxHeight : containHeight,
            child: player,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
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
      child: PlayerDragToClose(
        onDismiss: () => _dismiss(_controller),
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              _playerViewport(context),
              Positioned.fill(child: _controlsFor(_controller)),
              if (_playbackError != null)
                Positioned.fill(
                  child: PlayerPlaybackErrorOverlay(
                    message: _playbackError!,
                    retrying: _retrying,
                    onRetry: _retryPlayback,
                    onChangeSource: _resolvedSources.length > 1
                        ? _changeSource
                        : null,
                    onBack: () => _dismiss(_controller),
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
