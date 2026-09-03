import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import '../../app_scope.dart';
import '../../detail/episode_target_v2.dart';
import '../../theme/tokens.dart';
import 'live_timeline.dart';
import '../models/playback_media.dart';
import 'player_controls_overlay.dart';
import '../mappers/stream_player_mapping.dart' show subtitleIndicatorLabel;
import '../models/app_player_controller.dart';
import '../models/resolved_source.dart';
import '../state/playback_stall_detector.dart';
import '../sheets/player_selection_sheets.dart';
import '../sheets/subtitle_picker_sheet.dart';
import '../widgets/player_overlays.dart';

const Duration _upNextFallbackTriggerRemaining = Duration(minutes: 1);
const Duration _upNextCountdown = Duration(seconds: 10);
const Duration _bufferingIndicatorDelay = Duration(milliseconds: 700);
const Duration _bufferingProgressTolerance = Duration(milliseconds: 250);

/// How long the stall watchdog is held off after the viewer swaps a track on
/// demand.
///
/// A swap throws libmpv's cushion away and refills from the current point,
/// which on a slow upstream outlasts [PlaybackStallDetector.threshold] — and
/// a watchdog that fires there re-resolves the source, restarting playback
/// and undoing the switch that was asked for.
const Duration _trackSwitchSettleGrace = Duration(seconds: 20);

/// The same, for a seek — deliberately much shorter.
///
/// A seek out of the buffered range is the one interruption that can hang
/// outright rather than merely take a while, and re-resolving is what gets
/// the viewer out of it: the demuxer is rebuilt and starts at the position
/// asked for. Room for a slow refill, not room for a hang to sit in.
const Duration _seekSettleGrace = Duration(seconds: 8);

/// The same grace on a live stream, where it has to stay small.
///
/// A live URL is signed, short-lived and per-edge, so the re-resolve this
/// defers is the recovery that live depends on most — and a live refill
/// cannot take twenty seconds anyway: the playlist window holds only a few
/// segments, and libmpv resumes after `cache-pause-wait`. Enough room for
/// that refill, and no more.
const Duration _liveSettleGrace = Duration(seconds: 6);

/// The grace a deliberate interruption earns on this kind of stream.
@visibleForTesting
Duration playerSettleGrace({required bool isLive, required bool trackSwitch}) =>
    isLive
    ? _liveSettleGrace
    : trackSwitch
    ? _trackSwitchSettleGrace
    : _seekSettleGrace;

void _noFitToggle() {}

void _noSettling(Duration grace) {}

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
    this.fitMode = PlayerFitMode.contain,
    this.onToggleFit = _noFitToggle,
    required this.isLive,
    this.episodeGuide,
    this.playbackSegments = const [],
    this.upNextV2,
    this.upNextPaused = false,
    required this.onNearEnd,
    this.onManualNext,
    required this.onPlayNext,
    required this.onPauseUpNext,
    required this.onCancelUpNext,
    this.onSettling = _noSettling,
  });

  final AppPlayerController? controller;
  final void Function(bool visibility) onVisibilityChanged;
  final PlaybackMedia media;
  final List<ResolvedSource> resolvedSources;
  final int currentIndex;
  final VoidCallback onChangeSource;
  final VoidCallback onBack;
  final PlayerFitMode fitMode;
  final VoidCallback onToggleFit;
  final bool isLive;
  final EpisodeGuide? episodeGuide;
  final List<PlaybackSegment> playbackSegments;
  final NextEpisodeV2? upNextV2;
  final bool upNextPaused;
  final VoidCallback onNearEnd;
  final VoidCallback? onManualNext;
  final VoidCallback onPlayNext;
  final VoidCallback onPauseUpNext;
  final VoidCallback onCancelUpNext;

  /// Announces a deliberate interruption — a seek, or a track swap — so the
  /// page can stop its stall watchdog from reading the refill that follows as
  /// a dead source.
  final void Function(Duration grace) onSettling;

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

  /// Whether a rendition was chosen, here or in Settings, rather than left to
  /// the player. Only a viewer's own pick puts the tick on a height; Auto
  /// keeps it, and names what is playing beside it.
  bool? _qualityPinned;
  Timer? _bufferingIndicatorTimer;
  Timer? _liveEdgeRefreshTimer;
  Timer? _pausedLiveEdgeTimer;
  DateTime? _livePausedAt;
  Duration _livePauseStartEdge = Duration.zero;
  bool _showBufferingIndicator = false;
  Duration? _bufferingWatchPosition;
  bool _valueUpdateScheduled = false;
  Duration _liveEdge = Duration.zero;

  /// Segments the viewer has already skipped.
  ///
  /// A seek does not always land where it was aimed: a jump out of the
  /// buffered range takes the demuxer's own landing point, and a cut playlist
  /// begins at the segment boundary before it. Either can leave playback
  /// still inside the intro that was just skipped, and the button would offer
  /// itself again — the one thing the viewer has already answered.
  final Set<String> _skippedSegments = {};

  bool _isReady(AppPlayerValue? value) =>
      value?.initialized == true ||
      (widget.isLive &&
          value != null &&
          (value.isPlaying || liveSeekEdge(value) > Duration.zero));

  Duration _settlingGrace({required bool trackSwitch}) =>
      playerSettleGrace(isLive: widget.isLive, trackSwitch: trackSwitch);

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

    final position = value?.position ?? Duration.zero;
    final duration = value?.duration ?? Duration.zero;
    if (_shouldShowUpNext(position, duration)) {
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

  String _segmentKey(PlaybackSegment segment) =>
      '${segment.type.name}:${segment.startMs}:${segment.endMs}';

  PlaybackSegment? get _activeIntroSegment {
    if (!widget.media.isEpisode || widget.isLive) return null;
    final value = _videoValue?.value;
    // Segment metadata can arrive before the native player has initialized.
    // AVPlayer can also report initialized for a moment before play() starts;
    // do not offer a seek action against that placeholder position (zero).
    if (value?.initialized != true) return null;
    final position = value!.position;
    if (!value.isPlaying && position <= Duration.zero) return null;
    const lead = Duration(seconds: 5);
    for (final segment in widget.playbackSegments) {
      if (segment.type != PlaybackSegmentType.intro) continue;
      final start = Duration(milliseconds: segment.startMs);
      final end = Duration(milliseconds: segment.endMs);
      final key = _segmentKey(segment);
      // Rewinding to before the intro is a change of mind, and the offer
      // comes back with it.
      if (position < start - lead) {
        _skippedSegments.remove(key);
        continue;
      }
      if (position >= end || _skippedSegments.contains(key)) continue;
      return segment;
    }
    return null;
  }

  bool _hasReachedOutro(Duration position) {
    if (!widget.media.isEpisode || widget.isLive) return false;
    return widget.playbackSegments.any(
      (segment) =>
          segment.type == PlaybackSegmentType.outro &&
          position >= Duration(milliseconds: segment.startMs),
    );
  }

  bool get _hasOutroMarker =>
      widget.media.isEpisode &&
      !widget.isLive &&
      widget.playbackSegments.any(
        (segment) => segment.type == PlaybackSegmentType.outro,
      );

  bool _shouldShowUpNext(Duration position, Duration duration) {
    if (_hasReachedOutro(position)) return true;
    if (_hasOutroMarker || duration <= _upNextFallbackTriggerRemaining) {
      return false;
    }
    return duration - position <= _upNextFallbackTriggerRemaining;
  }

  void _skipIntro() {
    final segment = _activeIntroSegment;
    if (segment == null) return;
    _skippedSegments.add(_segmentKey(segment));
    _seekTo(Duration(milliseconds: segment.endMs));
    _revealControls();
  }

  void _seekTo(Duration target) {
    widget.onSettling(_settlingGrace(trackSwitch: false));
    unawaited(widget.controller?.seekTo(target));
  }

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
    final active = widget.controller?.activeQuality;
    final pinned =
        _qualityPinned ??
        (AppScope.of(context).qualityPreferenceController.maxHeight != null);
    final picked = await showModalBottomSheet<AppQualityTrack>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => PlayerQualityPickerSheet(
        tracks: tracks,
        current: pinned ? active : null,
        playing: active,
      ),
    );
    if (!mounted) return;
    if (picked != null) {
      widget.onSettling(_settlingGrace(trackSwitch: true));
      unawaited(widget.controller?.setQuality(picked));
      final height = picked.height;
      setState(() {
        _qualityPinned = height > 0;
        _activeQualityLabel = height > 0
            ? qualityRungLabel(width: picked.width, height: height)
            : null;
      });
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
      widget.onSettling(_settlingGrace(trackSwitch: true));
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
            bottom: kPlayerOverlayCardInset,
            child: SafeArea(
              child: Align(
                alignment: Alignment.bottomRight,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 250),
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
      fitMode: widget.fitMode,
      onToggleFit: widget.onToggleFit,
      onSkip: _skip,
      skipIntroLabel: _activeIntroSegment == null ? null : 'Skip intro',
      onSkipIntro: _activeIntroSegment == null ? null : _skipIntro,
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
      playbackSegments: widget.playbackSegments,
      upNextCard: upNextCard,
    );
  }
}
