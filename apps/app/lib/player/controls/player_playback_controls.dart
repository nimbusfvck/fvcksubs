import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import '../../app_scope.dart';
import '../../detail/episode_target_v2.dart';
import '../../library/library_controller.dart';
import '../../theme/tokens.dart';
import 'live_timeline.dart';
import '../models/playback_media.dart';
import 'player_controls_overlay.dart';
import '../mappers/stream_player_mapping.dart' show subtitleIndicatorLabel;
import '../models/app_player_controller.dart';
import '../models/resolved_source.dart';
import '../sheets/player_selection_sheets.dart';
import '../sheets/subtitle_picker_sheet.dart';
import '../widgets/player_overlays.dart';

const Duration _upNextTriggerRemaining = Duration(minutes: 2);
const Duration _upNextCountdown = Duration(seconds: 8);
const Duration _bufferingIndicatorDelay = Duration(milliseconds: 700);
const Duration _bufferingProgressTolerance = Duration(milliseconds: 250);

void _noFitToggle() {}

class PlayerPlaybackControls extends StatefulWidget {
  const PlayerPlaybackControls({
    super.key,
    required this.controller,
    required this.onVisibilityChanged,
    required this.media,
    required this.resolvedSources,
    required this.currentIndex,
    required this.onChangeSource,
    required this.onBack,
    this.onToggleFullScreen,
    this.fitMode = PlayerFitMode.contain,
    this.onToggleFit = _noFitToggle,
    required this.isLive,
    this.episodeGuide,
    this.upNextV2,
    this.upNextPaused = false,
    required this.onNearEnd,
    this.onManualNext,
    required this.onPlayNext,
    required this.onPauseUpNext,
    required this.onCancelUpNext,
  });

  final AppPlayerController? controller;
  final void Function(bool visibility) onVisibilityChanged;
  final PlaybackMedia media;
  final List<ResolvedSource> resolvedSources;
  final int currentIndex;
  final VoidCallback onChangeSource;
  final VoidCallback onBack;
  final VoidCallback? onToggleFullScreen;
  final PlayerFitMode fitMode;
  final VoidCallback onToggleFit;
  final bool isLive;
  final EpisodeGuide? episodeGuide;
  final NextEpisodeV2? upNextV2;
  final bool upNextPaused;
  final VoidCallback onNearEnd;
  final VoidCallback? onManualNext;
  final VoidCallback onPlayNext;
  final VoidCallback onPauseUpNext;
  final VoidCallback onCancelUpNext;

  @override
  State<PlayerPlaybackControls> createState() => _PlayerPlaybackControlsState();
}

class _PlayerPlaybackControlsState extends State<PlayerPlaybackControls> {
  ValueListenable<AppPlayerValue>? _videoValue;
  bool _controlsVisible = true;
  bool _wasPlaying = false;
  bool _wasBuffering = true; // Video starts in a loading state.
  bool _playbackIntent = true;
  bool _resumeAfterBuffering = false;
  Timer? _hideTimer;
  double? _dragValueMs;
  String? _activeSubtitleLabel;
  String? _activeQualityLabel;
  Timer? _bufferingIndicatorTimer;
  Timer? _liveEdgeRefreshTimer;
  Timer? _pausedLiveEdgeTimer;
  DateTime? _livePausedAt;
  Duration _livePauseStartEdge = Duration.zero;
  bool _showBufferingIndicator = false;
  Duration? _bufferingWatchPosition;
  bool _valueUpdateScheduled = false;
  Duration _liveEdge = Duration.zero;

  bool _isReady(AppPlayerValue? value) =>
      value?.initialized == true ||
      (widget.isLive &&
          value != null &&
          (value.isPlaying || liveSeekEdge(value) > Duration.zero));

  bool get _isBuffering =>
      !_isReady(_videoValue?.value) || _showBufferingIndicator;

  ResolvedSource get _current => widget.resolvedSources[widget.currentIndex];

  String get _overlayTitle {
    final item = widget.media.item;
    return item is EpisodeItemV2
        ? episodeSeriesTitle(item)
        : widget.media.title;
  }

  String? get _overlaySubtitle {
    final item = widget.media.item;
    return item is EpisodeItemV2
        ? currentEpisodeContextLabel(item, widget.episodeGuide)
        : null;
  }

  @override
  void initState() {
    super.initState();
    _syncVideoValue();
  }

  @override
  void didUpdateWidget(covariant PlayerPlaybackControls oldWidget) {
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
    final ValueListenable<AppPlayerValue>? next = widget.controller?.value;
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
    final isPlaying = value?.isPlaying ?? false;
    final isBuffering = value?.isBuffering ?? true;
    final isInitialized = _isReady(value);

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
      if (_playbackIntent) _resumeAfterBuffering = true;
    }

    if (widget.isLive) {
      final edge = liveSeekEdge(value);
      if (edge > _liveEdge) _liveEdge = edge;
    } else {
      _syncActiveSubtitleLabel();
    }

    if (_wasBuffering && !isBuffering && isPlaying) _restartHideTimer();
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
    final label = widget.controller?.activeSubtitle?.label;
    _activeSubtitleLabel = label == null ? null : subtitleIndicatorLabel(label);
  }

  void _restartHideTimer() {
    if (widget.controller == null) return;
    if (_isBuffering || !_isReady(_videoValue?.value)) return;
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () => _setVisible(false));
  }

  void _scheduleBufferingIndicator(Duration startPosition) {
    _bufferingWatchPosition = startPosition;
    _bufferingIndicatorTimer = Timer(_bufferingIndicatorDelay, () {
      _bufferingIndicatorTimer = null;
      final value = _videoValue?.value;
      if (!mounted || value == null || !value.isBuffering) return;
      final watchedPosition = _bufferingWatchPosition ?? value.position;
      final playbackProgressed =
          value.isPlaying &&
          value.position - watchedPosition > _bufferingProgressTolerance;
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
    if (_wasPlaying) _restartHideTimer();
  }

  void _handleBackgroundTap() {
    if (widget.upNextV2 != null && !widget.upNextPaused) {
      widget.onPauseUpNext();
      return;
    }
    if (_controlsVisible) {
      if (_isBuffering || !_isReady(_videoValue?.value)) return;
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

  void _seekTo(Duration target) => unawaited(widget.controller?.seekTo(target));

  Future<void> _openSubtitlePicker() async {
    if (widget.isLive) return;
    _hideTimer?.cancel();
    final currentSub = widget.controller?.activeSubtitle;
    final subtitlePreference = AppScope.of(
      context,
    ).subtitlePreferenceController;
    final tracks = subtitlePreference.tracksForPicker(
      _current.stream.subtitles,
    );
    final picked = await showModalBottomSheet<PlayerSubtitleSelection>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => PlayerSubtitlePickerSheet(
        media: widget.media,
        tracks: tracks,
        current: currentSub,
        filterTracks: subtitlePreference.tracksForPicker,
        initialExternalTracks: subtitlePreference.rememberedExternalSubtitles(
          widget.media.ref,
        ),
        onExternalTracksFetched: (tracks) => subtitlePreference
            .rememberExternalSubtitles(widget.media.ref, tracks),
      ),
    );
    if (!mounted) return;
    if (picked != null) {
      unawaited(widget.controller?.setSubtitle(picked.track));
      AppScope.of(context).subtitlePreferenceController.rememberSubtitle(
        widget.media.ref,
        track: picked.track,
        external: picked.isExternal,
      );
      final isOff = picked.track == null;
      setState(() {
        _activeSubtitleLabel = isOff
            ? null
            : subtitleIndicatorLabel(picked.track!.label);
      });
    }
    _revealControls();
  }

  Future<void> _openQualityPicker() async {
    _hideTimer?.cancel();
    final tracks = widget.controller?.qualityTracks ?? const [];
    final current = widget.controller?.activeQuality;
    final picked = await showModalBottomSheet<AppQualityTrack>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) =>
          PlayerQualityPickerSheet(tracks: tracks, current: current),
    );
    if (!mounted) return;
    if (picked != null) {
      unawaited(widget.controller?.setQuality(picked));
      final height = picked.height;
      setState(() => _activeQualityLabel = height > 0 ? '${height}p' : null);
    }
    _revealControls();
  }

  Future<void> _openAudioPicker() async {
    _hideTimer?.cancel();
    final tracks = widget.controller?.audioTracks ?? const [];
    final picked = await showModalBottomSheet<AppAudioTrack>(
      context: context,
      backgroundColor: AppColors.surfaceDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => PlayerAudioPickerSheet(
        tracks: tracks,
        current: widget.controller?.activeAudio,
      ),
    );
    if (!mounted) return;
    if (picked != null) {
      await widget.controller?.setAudioTrack(picked);
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
              child: Align(
                alignment: Alignment.bottomRight,
                child: SizedBox(
                  width: 280,
                  child: PlayerUpNextCard(
                    seriesTitle: widget.upNextV2!.seriesTitle,
                    subtitle: nextEpisodeContextLabel(widget.upNextV2!),
                    countdown: _upNextCountdown,
                    paused: widget.upNextPaused,
                    onPlayNext: widget.onPlayNext,
                    onCancel: widget.onCancelUpNext,
                  ),
                ),
              ),
            ),
          );
    final audioTracks = widget.controller?.audioTracks ?? const [];
    return PlayerControlsOverlayView(
      title: _overlayTitle,
      subtitle: _overlaySubtitle,
      favoriteAction: PlayerFavoriteButton(media: widget.media),
      controlsVisible: _controlsVisible,
      isLive: widget.isLive,
      isPlaying: value?.isPlaying ?? false,
      isBuffering: widget.controller != null && _isBuffering,
      sourceLabel: widget.resolvedSources.isEmpty
          ? null
          : _current.source.label,
      activeSubtitleLabel: _activeSubtitleLabel,
      activeQualityLabel: _activeQualityLabel,
      position: position,
      duration: duration,
      timelineExtent: timelineExtent,
      bufferedExtent: value?.bufferedPosition ?? Duration.zero,
      atLiveEdge: isAtLiveEdge(position, timelineExtent),
      dragValueMs: _dragValueMs,
      onBackgroundTap: _handleBackgroundTap,
      onBack: widget.onBack,
      onToggleFullScreen: widget.onToggleFullScreen,
      fitMode: widget.fitMode,
      onToggleFit: widget.onToggleFit,
      onSkip: _skip,
      onTogglePlayPause: _togglePlayPause,
      onChangeSource: () {
        _hideTimer?.cancel();
        widget.onChangeSource();
      },
      onPlayNext: widget.onManualNext,
      onOpenSubtitlePicker: _openSubtitlePicker,
      onOpenAudioPicker: audioTracks.length > 1 ? _openAudioPicker : null,
      onOpenQualityPicker: _openQualityPicker,
      onTimelineChangeStart: (value) {
        _hideTimer?.cancel();
        setState(() => _dragValueMs = value);
      },
      onTimelineChanged: (value) => setState(() => _dragValueMs = value),
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

class PlayerFavoriteButton extends StatelessWidget {
  const PlayerFavoriteButton({super.key, required this.media});

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
