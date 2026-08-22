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
import 'live_timeline.dart';
import 'play_item.dart';
import 'playback_media.dart';
import 'player_controls_overlay.dart';
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
const Duration _kBufferingIndicatorDelay = Duration(milliseconds: 700);
const Duration _kBufferingProgressTolerance = Duration(milliseconds: 250);

/// Returns the matching VOD position after a source change.
///
/// Live streams use a moving DVR window, so their position cannot safely be
/// carried over to another source. A shorter VOD fallback resumes at its end
/// rather than seeking beyond its available duration.
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
  int _playbackAttempt = 0;
  Duration? _pendingSourceSwitchPosition;

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
    final switchPosition = sourceSwitchSeekPosition(
      isLive: _isLive,
      previousPosition: _pendingSourceSwitchPosition,
      duration: value.duration,
    );
    if (switchPosition != null) {
      _pendingSourceSwitchPosition = null;
      _lastKnownPosition = switchPosition;
      final controller = _betterController;
      if (controller != null) unawaited(controller.seekTo(switchPosition));
    }
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
    final attempt = _playbackAttempt;
    void listener(BetterPlayerEvent event) =>
        _onPlayerEvent(controller, attempt, event);
    _errorListener = listener;
    controller.addEventsListener(listener);
    _playbackError = null;
  }

  void _onPlayerEvent(
    BetterPlayerController controller,
    int attempt,
    BetterPlayerEvent event,
  ) {
    if (attempt != _playbackAttempt) return;
    if (event.betterPlayerEventType == BetterPlayerEventType.finished) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            attempt != _playbackAttempt ||
            !identical(controller, _errorListenerController)) {
          return;
        }
        _handleNearEnd();
      });
      return;
    }
    if (event.betterPlayerEventType != BetterPlayerEventType.exception) return;
    final message = event.parameters?['exception']?.toString();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || attempt != _playbackAttempt) return;
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
    final attempt = ++_playbackAttempt;
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
      if (!mounted || attempt != _playbackAttempt) return;
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
      if (!mounted || attempt != _playbackAttempt) return;
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
        setState(() {
          _pendingSourceSwitchPosition = _isLive ? null : _lastKnownPosition;
          _currentIndex = index;
          _playbackAttempt++;
          _playbackError = null;
          _retrying = false;
          _sourceRevision++;
          _betterController = null;
          _onVisibilityChanged = null;
        });
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
  // The native controller can report `isPlaying == false` while it is
  // rebuffering. Keep the user's playback intent separate so that a transient
  // decoder pause does not become a permanent pause.
  bool _playbackIntent = true;
  bool _resumeAfterBuffering = false;
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
      if (_resumeAfterBuffering) {
        _resumeAfterBuffering = false;
        if (_playbackIntent && isInitialized && !isPlaying) {
          final controller = widget.controller;
          if (controller != null) unawaited(controller.play());
        }
      }
    } else if (!_showBufferingIndicator && _bufferingIndicatorTimer == null) {
      _scheduleBufferingIndicator(value?.position ?? Duration.zero);
      if (_wasPlaying && _playbackIntent) _resumeAfterBuffering = true;
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
      _playbackIntent = false;
      _resumeAfterBuffering = false;
      _startPausedLiveEdgeTracking();
      unawaited(widget.controller?.pause());
    } else {
      _playbackIntent = true;
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

  @override
  Widget build(BuildContext context) {
    final value = _videoValue?.value;
    final position = value?.position ?? Duration.zero;
    final duration = value?.duration ?? Duration.zero;
    final timelineExtent = widget.isLive
        ? (_liveEdge > liveSeekEdge(value) ? _liveEdge : liveSeekEdge(value))
        : duration;
    final upNextCard = widget.upNextV2 == null
        ? null
        : Positioned(
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
          );

    return PlayerControlsOverlayView(
      title: widget.media.title,
      favoriteAction: _PlaybackFavoriteButton(media: widget.media),
      controlsVisible: _controlsVisible,
      isLive: widget.isLive,
      isPlaying: value?.isPlaying ?? false,
      isBuffering:
          widget.controller != null &&
          (_showBufferingIndicator || !_isReady(value)),
      sourceLabel: widget.resolvedSources.isEmpty
          ? null
          : _current.source.label,
      activeSubtitleLabel: _activeSubtitleLabel,
      activeQualityLabel: _activeQualityLabel,
      position: position,
      duration: duration,
      timelineExtent: timelineExtent,
      bufferedExtent: bufferedSeekEdge(value),
      atLiveEdge: isAtLiveEdge(position, timelineExtent),
      dragValueMs: _dragValueMs,
      onBackgroundTap: _handleBackgroundTap,
      onBack: widget.onBack,
      onSkip: _skip,
      onTogglePlayPause: _togglePlayPause,
      onChangeSource: () {
        _hideTimer?.cancel();
        widget.onChangeSource();
      },
      onPlayNext: widget.upNextV2 == null ? null : widget.onPlayNext,
      onOpenSubtitlePicker: _openSubtitlePicker,
      onOpenQualityPicker: _openQualityPicker,
      onTimelineChangeStart: (value) {
        _hideTimer?.cancel();
        setState(() => _dragValueMs = value);
      },
      onTimelineChanged: (value) {
        setState(() => _dragValueMs = value);
      },
      onTimelineChangeEnd: (value) {
        final target = Duration(milliseconds: value.round());
        final seekTarget = widget.isLive
            ? liveSeekTarget(target, timelineExtent, currentPosition: position)
            : target;
        if (seekTarget != null) _seekTo(seekTarget);
        setState(() => _dragValueMs = null);
        _revealControls();
      },
      upNextCard: upNextCard,
    );
  }
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
