import 'package:flutter/material.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';

import '../../theme/tokens.dart';
import '../models/app_player_controller.dart';
import '../widgets/player_fit_button.dart';
import '../widgets/player_overlays.dart';

void _noFitToggle() {}

class PlayerControlsOverlayView extends StatelessWidget {
  const PlayerControlsOverlayView({
    super.key,
    required this.title,
    this.subtitle,
    required this.controlsVisible,
    required this.isLive,
    required this.isPlaying,
    required this.isBuffering,
    required this.sourceLabel,
    required this.activeSubtitleLabel,
    required this.activeQualityLabel,
    required this.position,
    required this.duration,
    required this.timelineExtent,
    required this.bufferedExtent,
    required this.atLiveEdge,
    required this.dragValueMs,
    required this.onBackgroundTap,
    required this.onBack,
    this.fitMode = PlayerFitMode.contain,
    this.onToggleFit = _noFitToggle,
    required this.onSkip,
    this.skipIntroLabel,
    this.onSkipIntro,
    required this.onTogglePlayPause,
    required this.onChangeSource,
    required this.onPlayNext,
    required this.onOpenSubtitlePicker,
    this.onOpenAudioPicker,
    required this.onOpenQualityPicker,
    required this.onTimelineChangeStart,
    required this.onTimelineChanged,
    required this.onTimelineChangeEnd,
    this.upNextCard,
    this.playbackSegments = const [],
  });

  /// Media title shown in the top bar.
  final String title;

  /// Optional secondary line shown below the media title.
  final String? subtitle;

  /// Whether the transport and top/bottom controls are visible.
  final bool controlsVisible;

  /// Whether playback is live, which changes timeline and live-edge behavior.
  final bool isLive;

  /// Current playback state used by the play/pause control.
  final bool isPlaying;

  /// Whether the player is buffering and should show a loading indicator.
  final bool isBuffering;

  /// Current source label used as the source selector tooltip; null hides it.
  final String? sourceLabel;

  /// Active subtitle label shown in the subtitle control.
  final String? activeSubtitleLabel;

  /// Active quality label shown in the quality control.
  final String? activeQualityLabel;

  /// Current playback position.
  final Duration position;

  /// Media duration used for the displayed timeline values.
  final Duration duration;

  /// Maximum seekable timeline extent, including the live edge when relevant.
  final Duration timelineExtent;

  /// End of the currently buffered range shown behind the seek progress.
  final Duration bufferedExtent;

  /// Whether the current live position is at the live edge.
  final bool atLiveEdge;

  /// Temporary timeline position while the user is dragging the seekbar.
  final double? dragValueMs;

  /// Handles taps on the player background, usually to toggle controls.
  final VoidCallback onBackgroundTap;

  /// Handles leaving the player screen.
  final VoidCallback onBack;

  /// Current video viewport mode.
  final PlayerFitMode fitMode;

  /// Toggles between preserving the source ratio and filling the viewport.
  final VoidCallback onToggleFit;

  /// Skips forward or backward by the requested number of seconds.
  final ValueChanged<int> onSkip;

  /// Label for the optional episode intro action.
  final String? skipIntroLabel;

  /// Seeks to the end of the active intro segment.
  final VoidCallback? onSkipIntro;

  /// Toggles playback between playing and paused.
  final VoidCallback onTogglePlayPause;

  /// Opens the source-selection UI.
  final VoidCallback onChangeSource;

  /// Starts the next episode manually; null hides the manual next icon.
  final VoidCallback? onPlayNext;

  /// Opens the subtitle-selection UI.
  final VoidCallback onOpenSubtitlePicker;

  /// Opens audio-track selection; null hides the audio action.
  final VoidCallback? onOpenAudioPicker;

  /// Opens quality-selection UI.
  final VoidCallback onOpenQualityPicker;

  /// Receives the timeline value when dragging starts.
  final ValueChanged<double> onTimelineChangeStart;

  /// Receives timeline values continuously while dragging.
  final ValueChanged<double> onTimelineChanged;

  /// Receives the final timeline value when dragging ends.
  final ValueChanged<double> onTimelineChangeEnd;

  /// Optional auto-next episode card displayed over the player.
  final Widget? upNextCard;

  /// Source-independent intro, recap, and outro intervals for the timeline.
  final List<PlaybackSegment> playbackSegments;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onBackgroundTap,
    child: Stack(
      fit: StackFit.expand,
      children: [
        _PlayerTopControls(
          title: title,
          subtitle: subtitle,
          visible: controlsVisible,
          onBack: onBack,
          fitMode: fitMode,
          onToggleFit: onToggleFit,
        ),
        _PlayerTransportControls(
          visible: controlsVisible,
          isLive: isLive,
          isPlaying: isPlaying,
          isBuffering: isBuffering,
          onSkip: onSkip,
          onTogglePlayPause: onTogglePlayPause,
        ),
        _PlayerBottomControls(
          visible: controlsVisible,
          isLive: isLive,
          sourceLabel: sourceLabel,
          activeSubtitleLabel: activeSubtitleLabel,
          activeQualityLabel: activeQualityLabel,
          position: position,
          duration: duration,
          timelineExtent: timelineExtent,
          bufferedExtent: bufferedExtent,
          atLiveEdge: atLiveEdge,
          dragValueMs: dragValueMs,
          onChangeSource: onChangeSource,
          onPlayNext: onPlayNext,
          onOpenSubtitlePicker: onOpenSubtitlePicker,
          onOpenAudioPicker: onOpenAudioPicker,
          onOpenQualityPicker: onOpenQualityPicker,
          onTimelineChangeStart: onTimelineChangeStart,
          onTimelineChanged: onTimelineChanged,
          onTimelineChangeEnd: onTimelineChangeEnd,
          playbackSegments: playbackSegments,
        ),
        if (upNextCard == null && skipIntroLabel != null && onSkipIntro != null)
          Positioned(
            left: AppSpacing.md,
            right: AppSpacing.md,
            bottom: kPlayerOverlayCardInset,
            child: SafeArea(
              child: Align(
                alignment: Alignment.bottomRight,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 250),
                  child: PlayerSkipIntroCard(
                    label: skipIntroLabel!,
                    onSkipIntro: onSkipIntro!,
                  ),
                ),
              ),
            ),
          ),
        if (upNextCard case final Widget card) card,
      ],
    ),
  );
}

class _PlayerTopControls extends StatelessWidget {
  const _PlayerTopControls({
    required this.title,
    required this.subtitle,
    required this.visible,
    required this.onBack,
    required this.fitMode,
    required this.onToggleFit,
  });

  final String title;
  final String? subtitle;
  final bool visible;
  final VoidCallback onBack;
  final PlayerFitMode fitMode;
  final VoidCallback onToggleFit;

  @override
  Widget build(BuildContext context) => Positioned(
    top: 0,
    left: 0,
    right: 0,
    child: AnimatedOpacity(
      opacity: visible ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 200),
      child: IgnorePointer(
        ignoring: !visible,
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
                  Transform.translate(
                    offset: const Offset(-AppSpacing.xs, 0),
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new_rounded),
                      color: Colors.white,
                      iconSize: 22,
                      tooltip: 'Back',
                      onPressed: onBack,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
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
                        if (subtitle case final value?) ...[
                          const SizedBox(height: AppSpacing.xxs),
                          Text(
                            value,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.bodySm.copyWith(
                              color: Colors.white70,
                              shadows: [
                                const Shadow(
                                  color: Colors.black87,
                                  blurRadius: 6,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  PlayerFitButton(mode: fitMode, onToggle: onToggleFit),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _PlayerTransportControls extends StatelessWidget {
  const _PlayerTransportControls({
    required this.visible,
    required this.isLive,
    required this.isPlaying,
    required this.isBuffering,
    required this.onSkip,
    required this.onTogglePlayPause,
  });

  final bool visible;
  final bool isLive;
  final bool isPlaying;
  final bool isBuffering;
  final ValueChanged<int> onSkip;
  final VoidCallback onTogglePlayPause;

  @override
  Widget build(BuildContext context) => AnimatedOpacity(
    opacity: visible ? 1.0 : 0.0,
    duration: const Duration(milliseconds: 200),
    child: IgnorePointer(
      ignoring: !visible,
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isLive) ...[
              IconButton(
                icon: const Icon(Icons.replay_10_rounded),
                color: Colors.white,
                iconSize: 38,
                onPressed: () => onSkip(-10),
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
                onPressed: onTogglePlayPause,
              ),
            if (!isLive) ...[
              const SizedBox(width: AppSpacing.xl),
              IconButton(
                icon: const Icon(Icons.forward_10_rounded),
                color: Colors.white,
                iconSize: 38,
                onPressed: () => onSkip(10),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

class _PlayerBottomControls extends StatelessWidget {
  const _PlayerBottomControls({
    required this.visible,
    required this.isLive,
    required this.sourceLabel,
    required this.activeSubtitleLabel,
    required this.activeQualityLabel,
    required this.position,
    required this.duration,
    required this.timelineExtent,
    required this.bufferedExtent,
    required this.atLiveEdge,
    required this.dragValueMs,
    required this.onChangeSource,
    required this.onPlayNext,
    required this.onOpenSubtitlePicker,
    required this.onOpenAudioPicker,
    required this.onOpenQualityPicker,
    required this.onTimelineChangeStart,
    required this.onTimelineChanged,
    required this.onTimelineChangeEnd,
    required this.playbackSegments,
  });

  final bool visible;
  final bool isLive;
  final String? sourceLabel;
  final String? activeSubtitleLabel;
  final String? activeQualityLabel;
  final Duration position;
  final Duration duration;
  final Duration timelineExtent;
  final Duration bufferedExtent;
  final bool atLiveEdge;
  final double? dragValueMs;
  final VoidCallback onChangeSource;
  final VoidCallback? onPlayNext;
  final VoidCallback onOpenSubtitlePicker;
  final VoidCallback? onOpenAudioPicker;
  final VoidCallback onOpenQualityPicker;
  final ValueChanged<double> onTimelineChangeStart;
  final ValueChanged<double> onTimelineChanged;
  final ValueChanged<double> onTimelineChangeEnd;
  final List<PlaybackSegment> playbackSegments;

  @override
  Widget build(BuildContext context) => Positioned(
    left: 0,
    right: 0,
    bottom: 0,
    child: AnimatedOpacity(
      opacity: visible ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 200),
      child: IgnorePointer(
        ignoring: !visible,
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
                  Align(
                    alignment: Alignment.centerRight,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (onPlayNext != null)
                          IconButton(
                            onPressed: onPlayNext,
                            icon: const Icon(Icons.skip_next_rounded),
                            color: Colors.white,
                            iconSize: 24,
                            tooltip: 'Next Episode',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 40,
                              minHeight: 40,
                            ),
                          ),
                        if (!isLive)
                          GestureDetector(
                            onTap: onOpenSubtitlePicker,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.xs,
                                vertical: AppSpacing.xxs,
                              ),
                              child: Icon(
                                activeSubtitleLabel != null
                                    ? Icons.closed_caption_rounded
                                    : Icons.closed_caption_off_rounded,
                                color: activeSubtitleLabel != null
                                    ? AppColors.brandAccent
                                    : Colors.white,
                                size: 26,
                              ),
                            ),
                          ),
                        if (onOpenAudioPicker != null)
                          GestureDetector(
                            onTap: onOpenAudioPicker,
                            child: const Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: AppSpacing.xs,
                                vertical: AppSpacing.xxs,
                              ),
                              child: Icon(
                                Icons.audiotrack_rounded,
                                color: Colors.white,
                                size: 26,
                              ),
                            ),
                          ),
                        GestureDetector(
                          onTap: onOpenQualityPicker,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.xs,
                              vertical: AppSpacing.xxs,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (activeQualityLabel == null)
                                  const Icon(
                                    Icons.high_quality_rounded,
                                    color: Colors.white,
                                    size: 26,
                                  ),
                                if (activeQualityLabel != null) ...[
                                  const SizedBox(width: 4),
                                  Text(
                                    activeQualityLabel!,
                                    style: AppTypography.caption.copyWith(
                                      color: AppColors.brandAccent,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        if (sourceLabel != null)
                          IconButton(
                            onPressed: onChangeSource,
                            icon: const Icon(Icons.playlist_play_rounded),
                            color: Colors.white,
                            iconSize: 26,
                            tooltip: sourceLabel!,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 40,
                              minHeight: 40,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (isLive || duration > Duration.zero)
                    _PlayerTimeline(
                      isLive: isLive,
                      position: position,
                      duration: duration,
                      timelineExtent: timelineExtent,
                      bufferedExtent: bufferedExtent,
                      atLiveEdge: atLiveEdge,
                      dragValueMs: dragValueMs,
                      onChangeStart: onTimelineChangeStart,
                      onChanged: onTimelineChanged,
                      onChangeEnd: onTimelineChangeEnd,
                      playbackSegments: playbackSegments,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _PlayerTimeline extends StatelessWidget {
  const _PlayerTimeline({
    required this.isLive,
    required this.position,
    required this.duration,
    required this.timelineExtent,
    required this.bufferedExtent,
    required this.atLiveEdge,
    required this.dragValueMs,
    required this.onChangeStart,
    required this.onChanged,
    required this.onChangeEnd,
    required this.playbackSegments,
  });

  final bool isLive;
  final Duration position;
  final Duration duration;
  final Duration timelineExtent;
  final Duration bufferedExtent;
  final bool atLiveEdge;
  final double? dragValueMs;
  final ValueChanged<double> onChangeStart;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;
  final List<PlaybackSegment> playbackSegments;

  @override
  Widget build(BuildContext context) {
    final durationStyle = AppTypography.caption.copyWith(
      color: Colors.white70,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final displayedPosition = dragValueMs == null
        ? position
        : Duration(milliseconds: dragValueMs!.round());
    final timeLabelWidth = _timeLabelWidth(context, durationStyle);

    return Row(
      children: [
        if (isLive)
          PlayerLiveIndicator(isAtLiveEdge: atLiveEdge)
        else
          SizedBox(
            width: timeLabelWidth,
            child: Text(
              _formatDuration(displayedPosition),
              key: const Key('player-position-label'),
              style: durationStyle,
            ),
          ),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              activeTrackColor: AppColors.brandAccent,
              secondaryActiveTrackColor: Colors.white54,
              inactiveTrackColor: Colors.white24,
              thumbColor: AppColors.brandAccent,
              trackShape: _PlaybackSegmentSliderTrackShape(
                segments: playbackSegments,
                timelineExtent: timelineExtent,
              ),
            ),
            child: Slider(
              value: (dragValueMs ?? position.inMilliseconds.toDouble()).clamp(
                0.0,
                timelineExtent.inMilliseconds.toDouble(),
              ),
              min: 0.0,
              max: timelineExtent > Duration.zero
                  ? timelineExtent.inMilliseconds.toDouble()
                  : 1.0,
              secondaryTrackValue: timelineExtent > Duration.zero
                  ? bufferedExtent.inMilliseconds
                        .clamp(0, timelineExtent.inMilliseconds)
                        .toDouble()
                  : null,
              onChangeStart: timelineExtent > Duration.zero
                  ? onChangeStart
                  : null,
              onChanged: timelineExtent > Duration.zero ? onChanged : null,
              onChangeEnd: timelineExtent > Duration.zero ? onChangeEnd : null,
            ),
          ),
        ),
        if (!isLive)
          SizedBox(
            width: timeLabelWidth,
            child: Text(
              _formatDuration(duration),
              key: const Key('player-duration-label'),
              style: durationStyle,
              textAlign: TextAlign.right,
            ),
          ),
      ],
    );
  }

  double _timeLabelWidth(BuildContext context, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: _formatDuration(duration), style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    return painter.width + AppSpacing.xs;
  }
}

/// Paints source-independent playback markers over the normal seek track.
///
/// The base slider still owns all interaction and progress semantics; this
/// shape only adds a yellow overlay for intervals such as intros or recaps.
class _PlaybackSegmentSliderTrackShape extends RoundedRectSliderTrackShape {
  const _PlaybackSegmentSliderTrackShape({
    required this.segments,
    required this.timelineExtent,
  });

  final List<PlaybackSegment> segments;
  final Duration timelineExtent;

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 2,
  }) {
    super.paint(
      context,
      offset,
      parentBox: parentBox,
      sliderTheme: sliderTheme,
      enableAnimation: enableAnimation,
      textDirection: textDirection,
      thumbCenter: thumbCenter,
      secondaryOffset: secondaryOffset,
      isDiscrete: isDiscrete,
      isEnabled: isEnabled,
      additionalActiveTrackHeight: additionalActiveTrackHeight,
    );

    final maxMs = timelineExtent.inMilliseconds;
    if (maxMs <= 0 || segments.isEmpty) return;

    final trackRect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
    final markerPaint = Paint()..color = AppColors.ratingAccent;
    final radius = Radius.circular(trackRect.height / 2);
    for (final segment in segments) {
      if (segment.type == PlaybackSegmentType.unknown) continue;
      final startMs = segment.startMs.clamp(0, maxMs).toDouble();
      final endMs = segment.endMs.clamp(0, maxMs).toDouble();
      if (endMs <= startMs) continue;

      final left = trackRect.left + trackRect.width * startMs / maxMs;
      final right = trackRect.left + trackRect.width * endMs / maxMs;
      context.canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(left, trackRect.top, right, trackRect.bottom),
          radius,
        ),
        markerPaint,
      );
    }
  }
}

class PlayerLiveIndicator extends StatelessWidget {
  const PlayerLiveIndicator({super.key, required this.isAtLiveEdge});

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

String _formatDuration(Duration duration) {
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (duration.inHours > 0) {
    final hours = duration.inHours.toString();
    return '$hours:$minutes:$seconds';
  }
  return '$minutes:$seconds';
}
