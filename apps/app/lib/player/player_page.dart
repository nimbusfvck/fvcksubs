import 'dart:async';

import 'package:better_player_plus/better_player_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';

import '../app_scope.dart';
import '../detail/episode_target_v2.dart';
import '../library/library_controller.dart';
import '../platform/playback_capability.dart';
import '../theme/tokens.dart';
import 'play_item.dart';
import 'playback_media.dart';
import 'stream_player_mapping.dart'
    show
        subtitleIndicatorLabel,
        subtitleLanguageLabel,
        subtitleSourceFor,
        subtitlesForPicker;

const Duration _upNextTriggerRemaining = Duration(minutes: 2);

const Duration _upNextCountdown = Duration(seconds: 8);

const Duration _kMinResumeProgress = Duration(seconds: 5);

const Duration _kResumeEndGuard = Duration(seconds: 30);

const Duration _kProgressReportInterval = Duration(seconds: 10);
const Duration _kLiveEdgeSnapThreshold = Duration(seconds: 2);
const Duration _kLiveEdgeSeekBackoff = Duration(seconds: 2);
const Duration _kLiveEdgeSyncTolerance = Duration(seconds: 5);
const Duration _kBufferingIndicatorDelay = Duration(milliseconds: 700);
const Duration _kBufferingProgressTolerance = Duration(milliseconds: 250);

List<BetterPlayerAsmsTrack> dedupedQualityTracks(
  List<BetterPlayerAsmsTrack> tracks,
) {
  final byHeight = <int, BetterPlayerAsmsTrack>{};
  for (final track in tracks) {
    final height = track.height ?? 0;
    if (height <= 0) continue;
    final existing = byHeight[height];
    if (existing == null || (track.bitrate ?? 0) > (existing.bitrate ?? 0)) {
      byHeight[height] = track;
    }
  }
  return byHeight.values.toList()
    ..sort((a, b) => (b.height ?? 0).compareTo(a.height ?? 0));
}

Duration liveSeekEdge(VideoPlayerValue? value) {
  if (value == null) return Duration.zero;
  var edge = value.duration ?? Duration.zero;
  if (value.position > edge) edge = value.position;
  for (final range in value.buffered) {
    if (range.end > edge) edge = range.end;
  }
  return edge;
}

/// The furthest buffered point used for the seekbar's secondary track.
Duration bufferedSeekEdge(VideoPlayerValue? value) {
  if (value == null) return Duration.zero;
  var edge = value.position;
  for (final range in value.buffered) {
    if (range.end > edge) edge = range.end;
  }
  return edge;
}

/// Refreshes resolved sources without dropping the source already playing.
///
/// A background refresh can fail to resolve one of the sources that opened the
/// player. Keep that entry until the current session ends, while replacing
/// refreshed entries and appending newly discovered ones.
List<ResolvedSource> mergeResolvedSources(
  List<ResolvedSource> current,
  List<ResolvedSource> refreshed,
) {
  final refreshedById = {
    for (final source in refreshed) source.source.id: source,
  };
  final merged = <ResolvedSource>[
    for (final source in current)
      refreshedById.remove(source.source.id) ?? source,
    ...refreshedById.values,
  ];
  return merged;
}

/// Converts a rightmost live scrub into a safe seek near the live edge.
///
/// Seeking to the exact end of a dynamic DASH window can flush the decoder at
/// a position whose segment is not available yet. If playback is already live,
/// avoid that redundant flush entirely. Otherwise stay one small segment
/// behind the edge while remaining inside the LIVE indicator tolerance.
Duration? liveSeekTarget(
  Duration target,
  Duration edge, {
  required Duration currentPosition,
}) {
  if (edge <= Duration.zero) return target;
  final snapStart = edge - _kLiveEdgeSnapThreshold;
  if (target < snapStart) return target;
  if (isAtLiveEdge(currentPosition, edge)) return null;

  final safeEdge = edge - _kLiveEdgeSeekBackoff;
  return safeEdge > Duration.zero ? safeEdge : Duration.zero;
}

/// Whether playback is close enough to the current live edge to be in sync.
bool isAtLiveEdge(Duration position, Duration edge) {
  if (edge <= Duration.zero) return true;
  return position >= edge - _kLiveEdgeSyncTolerance;
}

/// Advances a live timeline while playback is intentionally paused.
Duration liveEdgeAfterPause(Duration edge, Duration pausedFor) =>
    pausedFor > Duration.zero ? edge + pausedFor : edge;

class ResolvedSource {
  const ResolvedSource({required this.source, required this.stream});

  final StreamSource source;
  final PlayableStream stream;
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
       assert(
         resolvedSources.isNotEmpty,
         'Must provide at least one resolved source',
       );

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
  late final NextEpisodeV2? _nextEpisodeV2;
  bool _showUpNext = false;
  bool _upNextPaused = false;
  bool _advancing = false;

  LibraryController? _libraryController;

  Timer? _progressTimer;

  ValueListenable<VideoPlayerValue>? _trackedVideoValue;

  bool _hasResumed = false;

  Duration? _lastKnownPosition;
  Duration? _lastKnownDuration;

  String? _playbackError;

  bool _retrying = false;

  int _sourceRevision = 0;

  BetterPlayerController? _errorListenerController;

  bool get _isLive => widget.media.isLive;

  @override
  void initState() {
    super.initState();
    _currentIndex = 0;
    _resolvedSources = widget.resolvedSources;
    final item = widget.media.item;
    _nextEpisodeV2 = item is EpisodeItemV2 && widget.episodeGuide != null
        ? nextEpisodeOfV2(item, widget.episodeGuide!)
        : null;
    final pending = widget.pendingSources;
    if (pending != null) {
      unawaited(_awaitPendingSources(pending));
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = AppScope.of(context);
    _libraryController = scope.libraryController;
    _progressTimer ??= Timer.periodic(
      _kProgressReportInterval,
      (_) => _reportProgress(),
    );
  }

  Future<void> _awaitPendingSources(Stream<ResolvedSource> pending) async {
    await for (final source in pending) {
      if (!mounted) return;
      final playingId = _current.source.id;
      final merged = mergeResolvedSources(_resolvedSources, [source]);
      AppScope.of(context).sourceCache.store(widget.media.ref, merged);
      AppScope.of(context).sourceCache.promote(widget.media.ref, playingId);
      setState(() {
        _resolvedSources = merged;
        final index = merged.indexWhere((s) => s.source.id == playingId);
        _currentIndex = index == -1 ? 0 : index;
      });
    }
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _trackedVideoValue?.removeListener(_onVideoValueChanged);
    final errorListener = _errorListener;
    if (errorListener != null) {
      _errorListenerController?.removeEventsListener(errorListener);
    }
    _reportProgress();
    super.dispose();
  }

  void _trackPosition(BetterPlayerController controller) {
    final videoValue = controller.videoPlayerController;
    if (identical(videoValue, _trackedVideoValue)) return;
    _trackedVideoValue?.removeListener(_onVideoValueChanged);
    _trackedVideoValue = videoValue?..addListener(_onVideoValueChanged);
    _onVideoValueChanged();
  }

  void _onVideoValueChanged() {
    final value = _trackedVideoValue?.value;
    if (value == null || !value.initialized) return;
    _lastKnownPosition = value.position;
    _lastKnownDuration = value.duration;
    if (!_hasResumed) {
      _hasResumed = true;
      _maybeResumePosition(value.duration);
    }
  }

  void Function(BetterPlayerEvent)? _errorListener;

  void _attachErrorListener(BetterPlayerController controller) {
    if (identical(controller, _errorListenerController)) return;
    final oldListener = _errorListener;
    if (oldListener != null) {
      _errorListenerController?.removeEventsListener(oldListener);
    }
    _errorListenerController = controller;
    void listener(BetterPlayerEvent event) => _onPlayerEvent(controller, event);
    _errorListener = listener;
    controller.addEventsListener(listener);
    _playbackError = null;
  }

  void _onPlayerEvent(
    BetterPlayerController controller,
    BetterPlayerEvent event,
  ) {
    if (event.betterPlayerEventType == BetterPlayerEventType.finished) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !identical(controller, _errorListenerController)) {
          return;
        }
        _handleNearEnd();
      });
      return;
    }
    if (event.betterPlayerEventType != BetterPlayerEventType.exception) return;
    final message = event.parameters?['exception']?.toString();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!identical(controller, _errorListenerController)) return;
      setState(() {
        _playbackError = (message == null || message.isEmpty)
            ? 'Playback failed.'
            : message;
        _retrying = false;
      });
    });
  }

  Future<void> _retryPlayback() async {
    final controller = _betterController;
    if (controller == null || _retrying) return;
    setState(() {
      _retrying = true;
      _playbackError = null;
    });
    try {
      // Resolve again because signed URLs and tokens may have expired.
      final scope = AppScope.of(context);
      final refreshed = await scope.registry.resolveSource(
        widget.media.ref,
        _current.source.id,
      );
      if (!PlaybackTarget.detect().canPlay(refreshed)) {
        throw StateError(
          'The refreshed source is not playable on this device.',
        );
      }
      if (!mounted) return;
      setState(() {
        _resolvedSources[_currentIndex] = ResolvedSource(
          source: _current.source,
          stream: refreshed,
        );
        _sourceRevision++;
        _retrying = false;
      });
      scope.sourceCache.store(widget.media.ref, _resolvedSources);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _retrying = false;
        _playbackError =
            'Source is unavailable. Try another source or retry later.';
      });
    }
  }

  void _maybeResumePosition(Duration? duration) {
    if (_isLive) return;
    final controller = _betterController;
    if (controller == null) return;

    final progress = _libraryController?.recordFor(widget.media.ref)?.progress;

    if (progress == null || progress < _kMinResumeProgress) return;
    if (duration != null && duration - progress < _kResumeEndGuard) return;

    unawaited(controller.seekTo(progress));
  }

  void _reportProgress() {
    if (_isLive) return;
    final position = _lastKnownPosition;
    if (position == null) return;
    _libraryController?.recordWatched(
      widget.media.item,
      progress: position,
      duration: _lastKnownDuration,
    );
  }

  void _handleNearEnd() {
    if (_nextEpisodeV2 == null || _showUpNext) {
      return;
    }
    setState(() {
      _showUpNext = true;
      _upNextPaused = false;
    });
  }

  void _pauseUpNext() {
    if (_upNextPaused) return;
    setState(() => _upNextPaused = true);
  }

  void _cancelUpNext() {
    setState(() {
      _showUpNext = false;
      _upNextPaused = false;
    });
  }

  void _playNextEpisode() {
    if (_advancing) return;
    final nextV2 = _nextEpisodeV2;
    if (nextV2 == null) return;
    _advancing = true;
    unawaited(
      playItemV2(
        context,
        nextV2.item,
        episodeGuide: widget.episodeGuide,
        replaceCurrent: true,
      ),
    );
  }

  ResolvedSource get _current => _resolvedSources[_currentIndex];

  void _handleBack(BetterPlayerController? controller) {
    if (controller != null && controller.isFullScreen) {
      controller.exitFullScreen();
    }
    Navigator.of(context).pop();
  }

  Future<void> _changeSource() async {
    final picked = await showModalBottomSheet<ResolvedSource>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _SourcePickerSheet(
        resolvedSources: _resolvedSources,
        current: _current,
      ),
    );

    if (!mounted) return;
    if (picked != null) {
      final index = _resolvedSources.indexOf(picked);
      if (index != -1 && index != _currentIndex) {
        setState(() => _currentIndex = index);
        AppScope.of(
          context,
        ).sourceCache.promote(widget.media.ref, picked.source.id);
      }
    }
  }

  BetterPlayerController? _betterController;

  void Function(bool visibility)? _onVisibilityChanged;

  Widget _controlsFor(BetterPlayerController? controller) =>
      _NetflixControlsOverlay(
        controller: controller,
        onVisibilityChanged: _onVisibilityChanged ?? (_) {},
        media: widget.media,
        resolvedSources: _resolvedSources,
        currentIndex: _currentIndex,
        onChangeSource: _changeSource,
        onBack: () => _handleBack(controller),
        isLive: _isLive,
        upNextV2: _showUpNext ? _nextEpisodeV2 : null,
        upNextPaused: _upNextPaused,
        onNearEnd: _handleNearEnd,
        onPlayNext: _playNextEpisode,
        onPauseUpNext: _pauseUpNext,
        onCancelUpNext: _cancelUpNext,
      );

  @override
  Widget build(BuildContext context) {
    return _DragToCloseWrapper(
      onDismiss: () => _handleBack(_betterController),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            Center(
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: AppScope.of(context).playerBuilder(
                  context,
                  _current.stream,
                  isLive: _isLive,
                  key: ValueKey('${_current.source.id}:$_sourceRevision'),
                  preferredSubtitleLanguage: AppScope.of(
                    context,
                  ).subtitlePreferenceController.languageCode,
                  onControllerCreated: (c) {
                    _betterController = c as BetterPlayerController?;
                    if (_betterController != null) {
                      _attachErrorListener(_betterController!);
                    }
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) setState(() {});
                    });
                  },
                  onPlaybackReady: (c) {
                    final controller = c as BetterPlayerController?;
                    if (controller != null) _trackPosition(controller);
                  },
                  customControlsBuilder:
                      (context, controller, onVisibilityChanged) {
                        final betterController =
                            controller as BetterPlayerController?;
                        _betterController ??= betterController;
                        _onVisibilityChanged = onVisibilityChanged;
                        if (betterController?.isFullScreen != true) {
                          return const SizedBox.shrink();
                        }
                        return _controlsFor(betterController);
                      },
                ),
              ),
            ),
            Positioned.fill(child: _controlsFor(_betterController)),
            if (_playbackError != null)
              Positioned.fill(
                child: _PlaybackErrorOverlay(
                  message: _playbackError!,
                  retrying: _retrying,
                  onRetry: _retryPlayback,
                  onChangeSource: _resolvedSources.length > 1
                      ? _changeSource
                      : null,
                  onBack: () => _handleBack(_betterController),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PlaybackErrorOverlay extends StatelessWidget {
  const _PlaybackErrorOverlay({
    required this.message,
    required this.retrying,
    required this.onRetry,
    required this.onChangeSource,
    required this.onBack,
  });

  final String message;
  final bool retrying;
  final VoidCallback onRetry;
  final VoidCallback? onChangeSource;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Colors.black.withValues(alpha: 0.92),
    child: SafeArea(
      child: Stack(
        children: [
          Positioned(
            top: AppSpacing.xxs,
            left: AppSpacing.xs,
            child: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded),
              color: Colors.white,
              iconSize: 22,
              tooltip: 'Back',
              onPressed: onBack,
            ),
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.error_outline,
                    color: Colors.white70,
                    size: 48,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    "Couldn't play this source",
                    style: AppTypography.titleMd.copyWith(color: Colors.white),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    message,
                    style: AppTypography.bodySm.copyWith(
                      color: AppColors.onDarkSoft,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      OutlinedButton(
                        onPressed: retrying ? null : onRetry,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white54),
                          shape: const StadiumBorder(),
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.lg,
                            vertical: AppSpacing.sm,
                          ),
                        ),
                        child: retrying
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Try Again'),
                      ),
                      if (onChangeSource != null) ...[
                        const SizedBox(width: AppSpacing.sm),
                        ElevatedButton(
                          onPressed: onChangeSource,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.black,
                            shape: const StadiumBorder(),
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.lg,
                              vertical: AppSpacing.sm,
                            ),
                          ),
                          child: const Text('Change Source'),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _DragToCloseWrapper extends StatefulWidget {
  const _DragToCloseWrapper({required this.onDismiss, required this.child});

  final VoidCallback onDismiss;
  final Widget child;

  @override
  State<_DragToCloseWrapper> createState() => _DragToCloseWrapperState();
}

const double _kDismissThreshold = 200;
const double _kDismissVelocity = 800;

class _DragToCloseWrapperState extends State<_DragToCloseWrapper>
    with SingleTickerProviderStateMixin {
  double _dy = 0;
  late final AnimationController _snapCtrl;
  late Animation<double> _snapAnim;

  @override
  void initState() {
    super.initState();
    _snapCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
  }

  @override
  void dispose() {
    _snapCtrl.dispose();
    super.dispose();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (_snapCtrl.isAnimating) _snapCtrl.stop();
    setState(() => _dy = (_dy + details.delta.dy).clamp(0, double.infinity));
  }

  void _onDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (_dy > _kDismissThreshold || velocity > _kDismissVelocity) {
      widget.onDismiss();
    } else {
      _snapBack();
    }
  }

  void _snapBack() {
    final start = _dy;
    _snapAnim = Tween<double>(
      begin: start,
      end: 0,
    ).animate(CurvedAnimation(parent: _snapCtrl, curve: Curves.elasticOut));
    _snapCtrl.forward(from: 0);
    _snapAnim.addListener(() {
      if (mounted) setState(() => _dy = _snapAnim.value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final progress = (_dy / _kDismissThreshold).clamp(0.0, 1.0);
    return GestureDetector(
      onVerticalDragUpdate: _onDragUpdate,
      onVerticalDragEnd: _onDragEnd,
      onVerticalDragCancel: _snapBack,
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 1.0 - progress * 0.6),
        child: Transform.translate(offset: Offset(0, _dy), child: widget.child),
      ),
    );
  }
}

class _NetflixControlsOverlay extends StatefulWidget {
  const _NetflixControlsOverlay({
    required this.controller,
    required this.onVisibilityChanged,
    required this.media,
    required this.resolvedSources,
    required this.currentIndex,
    required this.onChangeSource,
    required this.onBack,
    required this.isLive,
    this.upNextV2,
    this.upNextPaused = false,
    required this.onNearEnd,
    required this.onPlayNext,
    required this.onPauseUpNext,
    required this.onCancelUpNext,
  });

  final BetterPlayerController? controller;
  final void Function(bool visibility) onVisibilityChanged;
  final PlaybackMedia media;
  final List<ResolvedSource> resolvedSources;
  final int currentIndex;
  final VoidCallback onChangeSource;
  final VoidCallback onBack;

  final bool isLive;

  final NextEpisodeV2? upNextV2;

  final bool upNextPaused;

  final VoidCallback onNearEnd;
  final VoidCallback onPlayNext;

  final VoidCallback onPauseUpNext;
  final VoidCallback onCancelUpNext;

  @override
  State<_NetflixControlsOverlay> createState() =>
      _NetflixControlsOverlayState();
}

class _NetflixControlsOverlayState extends State<_NetflixControlsOverlay> {
  ValueListenable<VideoPlayerValue>? _videoValue;
  bool _controlsVisible = true;
  bool _wasPlaying = false;
  bool _wasBuffering = true; // start as true: video is loading on first open
  Timer? _hideTimer;
  double? _dragValueMs;
  String? _activeSubtitleLabel; // null = no subtitle chosen yet
  String? _activeQualityLabel; // null = Auto

  Timer? _bufferingIndicatorTimer;
  Timer? _liveEdgeRefreshTimer;
  Timer? _pausedLiveEdgeTimer;
  DateTime? _livePausedAt;
  Duration _livePauseStartEdge = Duration.zero;
  bool _showBufferingIndicator = false;
  Duration? _bufferingWatchPosition;
  bool _valueUpdateScheduled = false;
  Duration _liveEdge = Duration.zero;

  bool _isReady(VideoPlayerValue? value) =>
      value?.initialized == true ||
      (widget.isLive &&
          value != null &&
          (value.isPlaying || liveSeekEdge(value) > Duration.zero));

  bool get _isBuffering =>
      !_isReady(_videoValue?.value) || _showBufferingIndicator;

  ResolvedSource get _current => widget.resolvedSources[widget.currentIndex];

  @override
  void initState() {
    super.initState();
    _syncVideoValue();
  }

  @override
  void didUpdateWidget(covariant _NetflixControlsOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncVideoValue();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _bufferingIndicatorTimer?.cancel();
    _liveEdgeRefreshTimer?.cancel();
    _pausedLiveEdgeTimer?.cancel();
    _videoValue?.removeListener(_onValueChanged);
    super.dispose();
  }

  void _syncVideoValue() {
    final ValueListenable<VideoPlayerValue>? next =
        widget.controller?.videoPlayerController;
    if (identical(next, _videoValue)) return;
    _videoValue?.removeListener(_onValueChanged);
    _stopPausedLiveEdgeTracking();
    _liveEdge = Duration.zero;
    _videoValue = next?..addListener(_onValueChanged);
  }

  void _onValueChanged() {
    if (!mounted || _valueUpdateScheduled) return;
    _valueUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _valueUpdateScheduled = false;
      if (!mounted) return;
      _applyVideoValue();
    });
  }

  void _applyVideoValue() {
    final value = _videoValue?.value;
    final bool isPlaying = value?.isPlaying ?? false;
    final bool isBuffering = value?.isBuffering ?? true;
    final bool isInitialized = _isReady(value);

    if (!isBuffering) {
      _bufferingIndicatorTimer?.cancel();
      _bufferingIndicatorTimer = null;
      _bufferingWatchPosition = null;
      _showBufferingIndicator = false;
    } else if (!_showBufferingIndicator && _bufferingIndicatorTimer == null) {
      _scheduleBufferingIndicator(value?.position ?? Duration.zero);
    }

    if (widget.isLive) {
      final edge = liveSeekEdge(value);
      if (edge > _liveEdge) _liveEdge = edge;
    } else {
      _syncActiveSubtitleLabel();
    }

    if (_wasBuffering && !isBuffering && isPlaying) {
      _restartHideTimer();
    }
    _wasBuffering = isBuffering || !isInitialized;

    if (isPlaying != _wasPlaying) {
      _wasPlaying = isPlaying;
      if (isPlaying) {
        _restartHideTimer();
      } else {
        _hideTimer?.cancel();
        _setVisible(true);
      }
    }

    final duration = value?.duration ?? Duration.zero;
    final position = value?.position ?? Duration.zero;
    if (duration > _upNextTriggerRemaining &&
        duration - position <= _upNextTriggerRemaining) {
      widget.onNearEnd();
    }

    setState(() {});
  }

  void _syncActiveSubtitleLabel() {
    final subtitle = widget.controller?.betterPlayerSubtitlesSource;
    final label = subtitle?.type == BetterPlayerSubtitlesSourceType.none
        ? null
        : subtitle?.name;
    _activeSubtitleLabel = label == null ? null : subtitleIndicatorLabel(label);
  }

  void _restartHideTimer() {
    if (widget.controller == null) return;
    final isInitialized = _isReady(_videoValue?.value);
    if (_isBuffering || !isInitialized) return;
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () => _setVisible(false));
  }

  void _scheduleBufferingIndicator(Duration startPosition) {
    _bufferingWatchPosition = startPosition;
    _bufferingIndicatorTimer = Timer(_kBufferingIndicatorDelay, () {
      _bufferingIndicatorTimer = null;
      final value = _videoValue?.value;
      if (!mounted || value == null || !value.isBuffering) return;

      final watchedPosition = _bufferingWatchPosition ?? value.position;
      final playbackProgressed =
          value.isPlaying &&
          value.position - watchedPosition > _kBufferingProgressTolerance;
      if (playbackProgressed) {
        _scheduleBufferingIndicator(value.position);
        return;
      }

      setState(() => _showBufferingIndicator = true);
    });
  }

  void _setVisible(bool visible) {
    if (_controlsVisible == visible) return;
    setState(() => _controlsVisible = visible);
    widget.onVisibilityChanged(visible);
  }

  void _revealControls() {
    _hideTimer?.cancel();
    _setVisible(true);
    if (_wasPlaying) {
      _restartHideTimer();
    }
  }

  void _handleBackgroundTap() {
    if (widget.upNextV2 != null && !widget.upNextPaused) {
      widget.onPauseUpNext();
      return;
    }

    if (_controlsVisible) {
      final isInitialized = _isReady(_videoValue?.value);
      if (_isBuffering || !isInitialized) return;
      _hideTimer?.cancel();
      _setVisible(false);
    } else {
      _revealControls();
    }
  }

  void _togglePlayPause() {
    if (_videoValue?.value.isPlaying ?? false) {
      _startPausedLiveEdgeTracking();
      unawaited(widget.controller?.pause());
    } else {
      _stopPausedLiveEdgeTracking();
      unawaited(widget.controller?.play());
      _refreshLiveEdgeAfterResume();
    }
    _revealControls();
  }

  void _startPausedLiveEdgeTracking() {
    if (!widget.isLive || _livePausedAt != null) return;
    final nativeEdge = liveSeekEdge(_videoValue?.value);
    if (nativeEdge > _liveEdge) _liveEdge = nativeEdge;
    _livePauseStartEdge = _liveEdge;
    _livePausedAt = DateTime.now();
    _pausedLiveEdgeTimer?.cancel();
    _pausedLiveEdgeTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _updatePausedLiveEdge(),
    );
  }

  void _updatePausedLiveEdge() {
    final pausedAt = _livePausedAt;
    if (!mounted || pausedAt == null) return;
    final estimated = liveEdgeAfterPause(
      _livePauseStartEdge,
      DateTime.now().difference(pausedAt),
    );
    if (estimated <= _liveEdge) return;
    setState(() => _liveEdge = estimated);
  }

  void _stopPausedLiveEdgeTracking() {
    _pausedLiveEdgeTimer?.cancel();
    _pausedLiveEdgeTimer = null;
    final pausedAt = _livePausedAt;
    if (pausedAt != null) {
      final estimated = liveEdgeAfterPause(
        _livePauseStartEdge,
        DateTime.now().difference(pausedAt),
      );
      if (estimated > _liveEdge) _liveEdge = estimated;
    }
    _livePausedAt = null;
  }

  void _refreshLiveEdgeAfterResume() {
    if (!widget.isLive) return;
    _liveEdgeRefreshTimer?.cancel();
    _liveEdgeRefreshTimer = Timer(const Duration(milliseconds: 750), () {
      if (mounted) _applyVideoValue();
    });
  }

  void _skip(int seconds) {
    final currentPos = _videoValue?.value.position ?? Duration.zero;
    _seekTo(currentPos + Duration(seconds: seconds));
    _revealControls();
  }

  void _seekTo(Duration target) {
    unawaited(widget.controller?.seekTo(target));
  }

  Future<void> _openSubtitlePicker() async {
    if (widget.isLive) return;
    _hideTimer?.cancel();
    final currentSub = widget.controller?.betterPlayerSubtitlesSource;
    final tracks = AppScope.of(
      context,
    ).subtitlePreferenceController.tracksForPicker(_current.stream.subtitles);

    final picked = await showModalBottomSheet<BetterPlayerSubtitlesSource>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _SubtitlePickerSheet(
        media: widget.media,
        tracks: tracks,
        current: currentSub,
        filterTracks: AppScope.of(
          context,
        ).subtitlePreferenceController.tracksForPicker,
      ),
    );

    if (!mounted) return;
    if (picked != null) {
      unawaited(widget.controller?.setupSubtitleSource(picked));
      final isOff = picked.type == BetterPlayerSubtitlesSourceType.none;
      setState(() {
        _activeSubtitleLabel = isOff
            ? null
            : subtitleIndicatorLabel(picked.name);
      });
    }
    _revealControls();
  }

  Future<void> _openQualityPicker() async {
    _hideTimer?.cancel();
    final tracks = dedupedQualityTracks(
      widget.controller?.betterPlayerAsmsTracks ?? const [],
    );
    final current = widget.controller?.betterPlayerAsmsTrack;

    final picked = await showModalBottomSheet<BetterPlayerAsmsTrack>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _QualityPickerSheet(tracks: tracks, current: current),
    );

    if (!mounted) return;
    if (picked != null) {
      unawaited(widget.controller?.setTrack(picked));
      final height = picked.height ?? 0;
      setState(() {
        _activeQualityLabel = height > 0 ? '${height}p' : null;
      });
    }
    _revealControls();
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (duration.inHours > 0) {
      final hours = duration.inHours.toString();
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final value = _videoValue?.value;
    final isPlaying = value?.isPlaying ?? false;
    final position = value?.position ?? Duration.zero;
    final duration = value?.duration ?? Duration.zero;
    final timelineExtent = widget.isLive
        ? (_liveEdge > liveSeekEdge(value) ? _liveEdge : liveSeekEdge(value))
        : duration;
    final bufferedExtent = bufferedSeekEdge(value);
    final atLiveEdge = isAtLiveEdge(position, timelineExtent);
    final isBuffering =
        widget.controller != null &&
        (_showBufferingIndicator || !_isReady(value));

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _handleBackgroundTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: AnimatedOpacity(
              opacity: _controlsVisible ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: IgnorePointer(
                ignoring: !_controlsVisible,
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xCC000000), Colors.transparent],
                      stops: [0.0, 1.0],
                    ),
                  ),
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: AppSpacing.xxs,
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_back_ios_new_rounded),
                            color: Colors.white,
                            iconSize: 22,
                            tooltip: 'Back',
                            onPressed: widget.onBack,
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Expanded(
                            child: Text(
                              widget.media.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.titleMd.copyWith(
                                color: Colors.white,
                                shadows: [
                                  const Shadow(
                                    color: Colors.black87,
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          _PlaybackFavoriteButton(media: widget.media),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          AnimatedOpacity(
            opacity: _controlsVisible ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: IgnorePointer(
              ignoring: !_controlsVisible,
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!widget.isLive) ...[
                      IconButton(
                        icon: const Icon(Icons.replay_10_rounded),
                        color: Colors.white,
                        iconSize: 38,
                        onPressed: () => _skip(-10),
                      ),
                      const SizedBox(width: AppSpacing.xl),
                    ],
                    if (isBuffering)
                      const SizedBox(
                        width: 64,
                        height: 64,
                        child: Padding(
                          padding: EdgeInsets.all(12),
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 3,
                          ),
                        ),
                      )
                    else
                      IconButton(
                        icon: Icon(
                          isPlaying
                              ? Icons.pause_circle_filled_rounded
                              : Icons.play_circle_fill_rounded,
                        ),
                        color: Colors.white,
                        iconSize: 64,
                        onPressed: _togglePlayPause,
                      ),
                    if (!widget.isLive) ...[
                      const SizedBox(width: AppSpacing.xl),
                      IconButton(
                        icon: const Icon(Icons.forward_10_rounded),
                        color: Colors.white,
                        iconSize: 38,
                        onPressed: () => _skip(10),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),

          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: AnimatedOpacity(
              opacity: _controlsVisible ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: IgnorePointer(
                ignoring: !_controlsVisible,
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [Color(0xCC000000), Colors.transparent],
                      stops: [0.0, 1.0],
                    ),
                  ),
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.xs,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (widget.resolvedSources.isNotEmpty)
                                    InkWell(
                                      onTap: () {
                                        _hideTimer?.cancel();
                                        widget.onChangeSource();
                                      },
                                      borderRadius: AppRadius.sm,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: AppSpacing.sm,
                                          vertical: AppSpacing.xxs + 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.white12,
                                          borderRadius: AppRadius.sm,
                                          border: Border.all(
                                            color: Colors.white24,
                                            width: 0.5,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(
                                              Icons.playlist_play_rounded,
                                              color: Colors.white,
                                              size: 20,
                                            ),
                                            const SizedBox(
                                              width: AppSpacing.xxs,
                                            ),
                                            Text(
                                              _current.source.label,
                                              style: AppTypography.bodySm
                                                  .copyWith(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  if (widget.upNextV2 != null)
                                    TextButton.icon(
                                      onPressed: widget.onPlayNext,
                                      icon: const Icon(
                                        Icons.skip_next_rounded,
                                        size: 22,
                                      ),
                                      label: const Text('Next Episode'),
                                      style: TextButton.styleFrom(
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: AppSpacing.xs,
                                        ),
                                      ),
                                    ),
                                ],
                              ),

                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (!widget.isLive)
                                    GestureDetector(
                                      onTap: _openSubtitlePicker,
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: AppSpacing.xs,
                                          vertical: AppSpacing.xxs,
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              _activeSubtitleLabel != null
                                                  ? Icons.closed_caption_rounded
                                                  : Icons
                                                        .closed_caption_off_rounded,
                                              color:
                                                  _activeSubtitleLabel != null
                                                  ? AppColors.brandAccent
                                                  : Colors.white,
                                              size: 26,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  GestureDetector(
                                    onTap: _openQualityPicker,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: AppSpacing.xs,
                                        vertical: AppSpacing.xxs,
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (_activeQualityLabel == null)
                                            Icon(
                                              Icons.high_quality_rounded,
                                              color: _activeQualityLabel != null
                                                  ? AppColors.brandAccent
                                                  : Colors.white,
                                              size: 26,
                                            ),
                                          if (_activeQualityLabel != null) ...[
                                            const SizedBox(width: 4),
                                            Text(
                                              _activeQualityLabel!,
                                              style: AppTypography.caption
                                                  .copyWith(
                                                    color:
                                                        AppColors.brandAccent,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),

                          if (widget.isLive || duration > Duration.zero) ...[
                            Row(
                              children: [
                                if (widget.isLive)
                                  _PlayerLiveIndicator(isAtLiveEdge: atLiveEdge)
                                else
                                  Text(
                                    _formatDuration(position),
                                    style: AppTypography.caption.copyWith(
                                      color: Colors.white70,
                                    ),
                                  ),
                                Expanded(
                                  child: SliderTheme(
                                    data: const SliderThemeData(
                                      trackHeight: 3,
                                      thumbShape: RoundSliderThumbShape(
                                        enabledThumbRadius: 6,
                                      ),
                                      activeTrackColor: AppColors.brandAccent,
                                      secondaryActiveTrackColor: Colors.white54,
                                      inactiveTrackColor: Colors.white24,
                                      thumbColor: AppColors.brandAccent,
                                    ),
                                    child: Slider(
                                      value:
                                          (_dragValueMs ??
                                                  position.inMilliseconds
                                                      .toDouble())
                                              .clamp(
                                                0.0,
                                                timelineExtent.inMilliseconds
                                                    .toDouble(),
                                              ),
                                      min: 0.0,
                                      max: timelineExtent > Duration.zero
                                          ? timelineExtent.inMilliseconds
                                                .toDouble()
                                          : 1.0,
                                      secondaryTrackValue:
                                          timelineExtent > Duration.zero
                                          ? bufferedExtent.inMilliseconds
                                                .clamp(
                                                  0,
                                                  timelineExtent.inMilliseconds,
                                                )
                                                .toDouble()
                                          : null,
                                      onChangeStart:
                                          timelineExtent > Duration.zero
                                          ? (val) {
                                              _hideTimer?.cancel();
                                              setState(
                                                () => _dragValueMs = val,
                                              );
                                            }
                                          : null,
                                      onChanged: timelineExtent > Duration.zero
                                          ? (val) {
                                              setState(
                                                () => _dragValueMs = val,
                                              );
                                            }
                                          : null,
                                      onChangeEnd:
                                          timelineExtent > Duration.zero
                                          ? (val) {
                                              final target = Duration(
                                                milliseconds: val.round(),
                                              );
                                              final seekTarget = widget.isLive
                                                  ? liveSeekTarget(
                                                      target,
                                                      timelineExtent,
                                                      currentPosition: position,
                                                    )
                                                  : target;
                                              if (seekTarget != null) {
                                                _seekTo(seekTarget);
                                              }
                                              setState(
                                                () => _dragValueMs = null,
                                              );
                                              _revealControls();
                                            }
                                          : null,
                                    ),
                                  ),
                                ),
                                if (!widget.isLive)
                                  Text(
                                    _formatDuration(duration),
                                    style: AppTypography.caption.copyWith(
                                      color: Colors.white70,
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          if (widget.upNextV2 != null)
            Positioned(
              left: AppSpacing.md,
              right: AppSpacing.md,
              bottom: AppSpacing.xl * 2,
              child: SafeArea(
                child: _UpNextCard(
                  seriesTitle: widget.upNextV2!.seriesTitle,
                  subtitle:
                      '${widget.upNextV2!.groupTitle} E${widget.upNextV2!.episode}',
                  countdown: _upNextCountdown,
                  paused: widget.upNextPaused,
                  onPlayNext: widget.onPlayNext,
                  onCancel: widget.onCancelUpNext,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PlayerLiveIndicator extends StatelessWidget {
  const _PlayerLiveIndicator({required this.isAtLiveEdge});

  final bool isAtLiveEdge;

  @override
  Widget build(BuildContext context) => Semantics(
    label: isAtLiveEdge
        ? 'Live broadcast, at live edge'
        : 'Live broadcast, behind live edge',
    child: Container(
      key: const Key('player-live-indicator'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: AppColors.liveAccent,
        borderRadius: AppRadius.sm,
      ),
      child: Text(
        'LIVE',
        style: AppTypography.liveBadge.copyWith(color: AppColors.primary),
      ),
    ),
  );
}

class _UpNextCard extends StatefulWidget {
  const _UpNextCard({
    required this.seriesTitle,
    required this.subtitle,
    required this.countdown,
    required this.paused,
    required this.onPlayNext,
    required this.onCancel,
  });

  final String seriesTitle;
  final String subtitle;
  final Duration countdown;
  final bool paused;
  final VoidCallback onPlayNext;
  final VoidCallback onCancel;

  @override
  State<_UpNextCard> createState() => _UpNextCardState();
}

class _UpNextCardState extends State<_UpNextCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.countdown)
      ..addStatusListener(_onStatusChanged)
      ..forward();
  }

  @override
  void didUpdateWidget(covariant _UpNextCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.paused == oldWidget.paused) return;
    if (widget.paused) {
      _controller.stop();
    } else {
      _controller.forward();
    }
  }

  void _onStatusChanged(AnimationStatus status) {
    if (status == AnimationStatus.completed) widget.onPlayNext();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: Container(
      width: MediaQuery.sizeOf(context).width,
      padding: EdgeInsets.fromLTRB(
        AppSpacing.sm,
        widget.paused ? AppSpacing.xxs : AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.surfaceDark.withValues(alpha: 0.95),
        borderRadius: AppRadius.sm,
        border: Border.all(color: Colors.white24, width: 0.5),
      ),
      child: Column(
        children: [
          if (widget.paused)
            Align(
              alignment: Alignment.topLeft,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: widget.onCancel,
                child: const Padding(
                  padding: EdgeInsets.all(2),
                  child: Icon(
                    Icons.close_rounded,
                    size: 16,
                    color: AppColors.onDarkSoft,
                  ),
                ),
              ),
            ),

          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.seriesTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodyMd.copyWith(
                        color: AppColors.onDark,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      widget.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodySm.copyWith(
                        color: AppColors.onDarkSoft,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: AppSpacing.sm),

              SizedBox(
                width: 46,
                height: 46,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    AnimatedBuilder(
                      animation: _controller,
                      builder: (context, _) {
                        return CircularProgressIndicator(
                          value: 1.0 - _controller.value,
                          strokeWidth: 2.5,
                          backgroundColor: Colors.white24,
                          valueColor: const AlwaysStoppedAnimation(
                            AppColors.brandAccent,
                          ),
                        );
                      },
                    ),

                    Padding(
                      padding: const EdgeInsets.all(1),
                      child: Material(
                        color: Colors.white,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: widget.onPlayNext,
                          child: const SizedBox(
                            width: 24,
                            height: 24,
                            child: Icon(
                              Icons.play_arrow_rounded,
                              color: Colors.black,
                              size: 18,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

Widget? _subtitleSummary(ResolvedSource source) {
  final languages = <String>{
    for (final track in source.stream.subtitles)
      if (track.language.isNotEmpty) track.language.split(RegExp('[-_]')).first,
  };
  if (languages.isEmpty) return null;
  final ordered = languages.toList()..sort();
  return Text(
    'Subtitles: ${ordered.join(', ')}',
    style: AppTypography.bodySm.copyWith(color: AppColors.onDarkSoft),
  );
}

class _SourcePickerSheet extends StatelessWidget {
  const _SourcePickerSheet({
    required this.resolvedSources,
    required this.current,
  });

  final List<ResolvedSource> resolvedSources;
  final ResolvedSource current;

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * 0.6;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: AppSpacing.sm),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.hairlineDark,
                borderRadius: AppRadius.pill,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Video Sources',
              style: AppTypography.titleMd.copyWith(color: AppColors.onDark),
            ),
            const SizedBox(height: AppSpacing.xs),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final item in resolvedSources)
                    ListTile(
                      title: Text(
                        item.source.label,
                        style: AppTypography.bodyMd.copyWith(
                          color: AppColors.onDark,
                        ),
                      ),
                      subtitle: _subtitleSummary(item),
                      trailing: item.source.id == current.source.id
                          ? const Icon(
                              Icons.check,
                              color: AppColors.brandAccent,
                            )
                          : null,
                      onTap: () => Navigator.of(context).pop(item),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
        ),
      ),
    );
  }
}

class _QualityPickerSheet extends StatelessWidget {
  const _QualityPickerSheet({required this.tracks, required this.current});

  final List<BetterPlayerAsmsTrack> tracks;

  final BetterPlayerAsmsTrack? current;

  bool get _autoSelected => (current?.height ?? 0) <= 0;

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * 0.6;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: AppSpacing.sm),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.hairlineDark,
                borderRadius: AppRadius.pill,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Quality',
              style: AppTypography.titleMd.copyWith(color: AppColors.onDark),
            ),
            const SizedBox(height: AppSpacing.xs),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  ListTile(
                    title: Text(
                      'Auto',
                      style: AppTypography.bodyMd.copyWith(
                        color: AppColors.onDark,
                      ),
                    ),
                    trailing: _autoSelected
                        ? const Icon(Icons.check, color: AppColors.brandAccent)
                        : null,
                    onTap: () => Navigator.of(
                      context,
                    ).pop(BetterPlayerAsmsTrack.defaultTrack()),
                  ),
                  for (final track in tracks)
                    ListTile(
                      title: Text(
                        '${track.height}p',
                        style: AppTypography.bodyMd.copyWith(
                          color: AppColors.onDark,
                        ),
                      ),
                      trailing: !_autoSelected && current == track
                          ? const Icon(
                              Icons.check,
                              color: AppColors.brandAccent,
                            )
                          : null,
                      onTap: () => Navigator.of(context).pop(track),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
        ),
      ),
    );
  }
}

class _PlaybackFavoriteButton extends StatelessWidget {
  const _PlaybackFavoriteButton({required this.media});

  final PlaybackMedia media;

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context).libraryController;
    return BlocBuilder<LibraryController, LibraryState>(
      bloc: controller,
      builder: (context, state) {
        final favorited = state.isFavorite(media.ref);
        return IconButton(
          icon: Icon(favorited ? Icons.favorite : Icons.favorite_border),
          color: favorited ? AppColors.liveAccent : null,
          tooltip: favorited ? 'Remove from favorites' : 'Add to favorites',
          onPressed: () => controller.toggleFavorite(media.item),
        );
      },
    );
  }
}

class _SubtitleGroup {
  _SubtitleGroup({required this.label, required this.tracks});

  final String label;
  final List<SubtitleTrack> tracks;
}

class _SubtitlePickerSheet extends StatefulWidget {
  const _SubtitlePickerSheet({
    required this.media,
    required this.tracks,
    required this.current,
    required this.filterTracks,
  });

  final PlaybackMedia media;

  final List<SubtitleTrack> tracks;
  final BetterPlayerSubtitlesSource? current;
  final List<SubtitleTrack> Function(List<SubtitleTrack> tracks) filterTracks;

  @override
  State<_SubtitlePickerSheet> createState() => _SubtitlePickerSheetState();
}

enum _ExternalFetchState { idle, loading, foundNone }

class _SubtitlePickerSheetState extends State<_SubtitlePickerSheet> {
  _SubtitleGroup? _expanded;

  List<SubtitleTrack> _externalTracks = const [];
  _ExternalFetchState _externalState = _ExternalFetchState.idle;

  List<_SubtitleGroup> get _groups {
    final merged = subtitlesForPicker([...widget.tracks, ..._externalTracks]);
    final byLabel = <String, List<SubtitleTrack>>{};
    for (final track in merged) {
      (byLabel[subtitleLanguageLabel(track.language)] ??= []).add(track);
    }
    return [
      for (final entry in byLabel.entries)
        _SubtitleGroup(label: entry.key, tracks: entry.value),
    ];
  }

  Future<void> _fetchExternal() async {
    setState(() => _externalState = _ExternalFetchState.loading);
    final registry = AppScope.of(context).registry;
    final fetched = await registry.externalSubtitles(widget.media.item);
    if (!mounted) return;
    final visibleTracks = widget.filterTracks(fetched);
    setState(() {
      _externalTracks = visibleTracks;
      _externalState = visibleTracks.isEmpty
          ? _ExternalFetchState.foundNone
          : _ExternalFetchState.idle;
    });
  }

  String? _urlOf(BetterPlayerSubtitlesSource source) =>
      (source.urls != null && source.urls!.isNotEmpty)
      ? source.urls!.first
      : null;

  BetterPlayerSubtitlesSource _sourceFor(SubtitleTrack track) =>
      subtitleSourceFor(track);

  BetterPlayerSubtitlesSource _offSource() => BetterPlayerSubtitlesSource(
    type: BetterPlayerSubtitlesSourceType.none,
    name: 'Off',
  );

  bool get _offSelected =>
      widget.current == null ||
      widget.current!.type == BetterPlayerSubtitlesSourceType.none;

  bool _isSelected(SubtitleTrack track) {
    final current = widget.current;
    if (current == null ||
        current.type == BetterPlayerSubtitlesSourceType.none) {
      return false;
    }
    return _urlOf(current) == track.url;
  }

  String _variantName(SubtitleTrack track, int index) =>
      track.label.isNotEmpty ? track.label : 'Option ${index + 1}';

  @override
  Widget build(BuildContext context) {
    final expanded = _expanded;
    final maxHeight = MediaQuery.of(context).size.height * 0.6;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: AppSpacing.sm),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.hairlineDark,
                borderRadius: AppRadius.pill,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                SizedBox(
                  width: 40,
                  child: expanded == null
                      ? null
                      : IconButton(
                          icon: const Icon(
                            Icons.arrow_back_ios_new_rounded,
                            size: 18,
                          ),
                          color: AppColors.onDark,
                          onPressed: () => setState(() => _expanded = null),
                        ),
                ),
                Expanded(
                  child: Text(
                    expanded?.label ?? 'Subtitles (CC)',
                    textAlign: TextAlign.center,
                    style: AppTypography.titleMd.copyWith(
                      color: AppColors.onDark,
                    ),
                  ),
                ),
                const SizedBox(width: 40),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: expanded == null
                    ? [
                        ListTile(
                          title: Text(
                            'Off',
                            style: AppTypography.bodyMd.copyWith(
                              color: AppColors.onDark,
                            ),
                          ),
                          trailing: _offSelected
                              ? const Icon(
                                  Icons.check,
                                  color: AppColors.brandAccent,
                                )
                              : null,
                          onTap: () => Navigator.of(context).pop(_offSource()),
                        ),
                        for (final group in _groups)
                          ListTile(
                            title: Text(
                              group.tracks.length > 1
                                  ? '${group.label} (${group.tracks.length})'
                                  : group.label,
                              style: AppTypography.bodyMd.copyWith(
                                color: AppColors.onDark,
                              ),
                            ),
                            trailing: group.tracks.any(_isSelected)
                                ? const Icon(
                                    Icons.check,
                                    color: AppColors.brandAccent,
                                  )
                                : group.tracks.length > 1
                                ? const Icon(
                                    Icons.chevron_right_rounded,
                                    color: AppColors.onDarkSoft,
                                  )
                                : null,
                            onTap: () {
                              if (group.tracks.length == 1) {
                                Navigator.of(
                                  context,
                                ).pop(_sourceFor(group.tracks.first));
                              } else {
                                setState(() => _expanded = group);
                              }
                            },
                          ),
                        const Divider(color: AppColors.hairlineDark, height: 1),
                        ListTile(
                          leading: _externalState == _ExternalFetchState.loading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.onDarkSoft,
                                  ),
                                )
                              : const Icon(
                                  Icons.cloud_download_rounded,
                                  color: AppColors.onDarkSoft,
                                ),
                          title: Text(
                            _externalState == _ExternalFetchState.foundNone
                                ? 'No supported external subtitles found'
                                : 'Fetch external subtitles',
                            style: AppTypography.bodyMd.copyWith(
                              color: AppColors.onDarkSoft,
                            ),
                          ),
                          subtitle: Text(
                            'A fallback if the ones above are missing, out of sync, or erroring',
                            style: AppTypography.caption.copyWith(
                              color: AppColors.onDarkSoft,
                            ),
                          ),
                          enabled:
                              _externalState != _ExternalFetchState.loading,
                          onTap: _fetchExternal,
                        ),
                      ]
                    : [
                        for (final (index, track) in expanded.tracks.indexed)
                          ListTile(
                            title: Text(
                              _variantName(track, index),
                              style: AppTypography.bodyMd.copyWith(
                                color: AppColors.onDark,
                              ),
                            ),
                            trailing: _isSelected(track)
                                ? const Icon(
                                    Icons.check,
                                    color: AppColors.brandAccent,
                                  )
                                : null,
                            onTap: () =>
                                Navigator.of(context).pop(_sourceFor(track)),
                          ),
                      ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
        ),
      ),
    );
  }
}
