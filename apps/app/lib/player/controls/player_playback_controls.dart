import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
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
import '../state/player_controls_cubit.dart';
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
/// A swap can throw the native player's cushion away and refill from the
/// current point, which on a slow upstream outlasts
/// [PlaybackStallDetector.threshold]. A watchdog that fires there re-resolves
/// the source, restarting playback and undoing the requested switch.
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
/// defers is the recovery that live depends on most. A live refill cannot take
/// twenty seconds anyway: the playlist window holds only a few segments.
/// Enough room for that refill, and no more.
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
void _noLandscapeToggle() {}

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
    required this.onMinimize,
    this.fitMode = PlayerFitMode.contain,
    this.onToggleFit = _noFitToggle,
    this.landscapeLocked = false,
    this.onToggleLandscape = _noLandscapeToggle,
    required this.isLive,
    this.episodeGuide,
    this.playbackSegments = const [],
    this.upNextV2,
    this.upNextPaused = false,
    required this.onNearEnd,
    required this.onPlayEpisode,
    required this.onPlayNext,
    required this.onPauseUpNext,
    required this.onCancelUpNext,
    this.onOpenMultiView,
    this.onSettling = _noSettling,
  });

  final AppPlayerController? controller;
  final void Function(bool visibility) onVisibilityChanged;
  final PlaybackMedia media;
  final List<ResolvedSource> resolvedSources;
  final int currentIndex;
  final VoidCallback onChangeSource;
  final VoidCallback onMinimize;
  final PlayerFitMode fitMode;
  final VoidCallback onToggleFit;
  final bool landscapeLocked;
  final VoidCallback onToggleLandscape;
  final bool isLive;
  final EpisodeGuide? episodeGuide;
  final List<PlaybackSegment> playbackSegments;
  final NextEpisodeV2? upNextV2;
  final bool upNextPaused;
  final VoidCallback onNearEnd;
  final ValueChanged<PlayerEpisodeEntry> onPlayEpisode;
  final VoidCallback onPlayNext;
  final VoidCallback onPauseUpNext;
  final VoidCallback onCancelUpNext;
  final VoidCallback? onOpenMultiView;

  /// Announces a deliberate interruption — a seek, or a track swap — so the
  /// page can stop its stall watchdog from reading the refill that follows as
  /// a dead source.
  final void Function(Duration grace) onSettling;

  @override
  State<PlayerPlaybackControls> createState() => _PlayerPlaybackControlsState();
}

class _PlayerPlaybackControlsState extends State<PlayerPlaybackControls> {
  late final PlayerControlsCubit _controlsCubit;
  ValueListenable<AppPlayerValue>? _videoValue;
  bool _controlsVisible = true;
  bool _wasPlaying = false;
  bool _wasBuffering = true; // Video starts in a loading state.
  bool _playbackIntent = true;
  bool _resumeAfterBuffering = false;
  Timer? _hideTimer;
  double? _dragValueMs;
  double _playbackSpeed = 1.0;
  String? _activeSubtitleLabel;
  String? _activeQualityLabel;
  int _qualityRequestGeneration = 0;
  bool _qualitySwitching = false;
  AppPlayerController? _qualityController;

  /// Whether a rendition was chosen, here or in Settings, rather than left to
  /// the player. Only a viewer's own pick puts the tick on a height; Auto keeps
  /// the control label as Auto even while the native player reports a concrete
  /// rendition such as 720p.
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
  Duration _liveEdgeLead = Duration.zero;

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

  BuildContext get _modalContext =>
      AppScope.of(
        context,
      ).pictureInPictureSession.modalNavigatorKey.currentContext ??
      context;

  List<PlayerEpisodeEntry> get _episodeEntries {
    final guide = widget.episodeGuide;
    if (guide == null || !widget.media.isEpisode || widget.isLive) {
      return const [];
    }
    return [
      for (final group in guide.groups)
        for (final entry in group.episodes.indexed)
          (group: group, index: entry.$1, episode: entry.$2),
    ];
  }

  @override
  void initState() {
    super.initState();
    _controlsCubit = PlayerControlsCubit();
    _syncVideoValue();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_qualityPinned != null) return;
    _qualityPinned =
        AppScope.of(context).qualityPreferenceController.maxHeight != null;
    if (_qualityController != null) {
      _activeQualityLabel = _displayQualityLabel(widget.controller);
      _publishControlState();
    }
  }

  @override
  void didUpdateWidget(covariant PlayerPlaybackControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncVideoValue();
    if (!identical(oldWidget.controller, widget.controller)) {
      unawaited(widget.controller?.setPlaybackSpeed(_playbackSpeed));
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _bufferingIndicatorTimer?.cancel();
    _liveEdgeRefreshTimer?.cancel();
    _pausedLiveEdgeTimer?.cancel();
    _videoValue?.removeListener(_onValueChanged);
    unawaited(_controlsCubit.close());
    super.dispose();
  }

  void _syncVideoValue() {
    final ValueListenable<AppPlayerValue>? next = widget.controller?.value;
    if (identical(next, _videoValue) &&
        identical(_qualityController, widget.controller)) {
      return;
    }
    final controllerChanged = !identical(_qualityController, widget.controller);
    _qualityController = widget.controller;
    _controlsCubit.cancelSeek();
    _videoValue?.removeListener(_onValueChanged);
    _stopPausedLiveEdgeTracking();
    _liveEdge = Duration.zero;
    _liveEdgeLead = Duration.zero;
    _videoValue = next?..addListener(_onValueChanged);
    if (controllerChanged) {
      _qualityRequestGeneration++;
      _qualitySwitching = false;
      _activeQualityLabel = _displayQualityLabel(widget.controller);
    }
    _publishControlState();
  }

  void _onValueChanged() {
    if (!mounted) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      if (_valueUpdateScheduled) return;
      _valueUpdateScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _valueUpdateScheduled = false;
        if (mounted) _applyVideoValue();
      });
      return;
    }
    _applyVideoValue();
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
      final nativeEdge = value?.seekablePosition ?? Duration.zero;
      if (nativeEdge > Duration.zero) {
        final observedLead = nativeEdge - (value?.position ?? Duration.zero);
        if (observedLead > Duration.zero) _liveEdgeLead = observedLead;
        final estimatedEdge =
            (value?.position ?? Duration.zero) + _liveEdgeLead;
        if (estimatedEdge > _liveEdge) _liveEdge = estimatedEdge;
        if (nativeEdge > _liveEdge) _liveEdge = nativeEdge;
      } else {
        final edge = liveSeekEdge(value);
        if (edge > _liveEdge) _liveEdge = edge;
      }
    } else {
      _syncActiveSubtitleLabel();
      if (!_qualitySwitching) {
        _activeQualityLabel = _displayQualityLabel(widget.controller);
      }
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

    _publishControlState();
  }

  void _publishControlState() {
    final value = _videoValue?.value ?? const AppPlayerValue();
    final activeIntro = _activeIntroSegment;
    _controlsCubit.update(
      value: value,
      controlsVisible: _controlsVisible,
      isBuffering: widget.controller != null && _isBuffering,
      liveEdge: _liveEdge,
      dragValueMs: _dragValueMs,
      activeSubtitleLabel: _activeSubtitleLabel,
      activeQualityLabel: _activeQualityLabel,
      skipIntroLabel: activeIntro == null ? null : 'Skip intro',
    );
  }

  void _syncActiveSubtitleLabel() {
    final label = widget.controller?.activeSubtitle?.label;
    _activeSubtitleLabel = label == null ? null : subtitleIndicatorLabel(label);
  }

  String? _qualityLabel(AppQualityTrack? track) {
    if (track == null || track.height <= 0) return null;
    return qualityRungLabel(width: track.width, height: track.height) ??
        '${track.height}p';
  }

  String? _displayQualityLabel(AppPlayerController? controller) {
    final active = _qualityLabel(controller?.activeQuality);
    if (active == null) return null;
    if (!(_qualityPinned ?? false)) return 'Auto';
    return active;
  }

  String _requestedQualityLabel(AppQualityTrack track) {
    if (track.id == 'auto' || track.height <= 0) return 'Auto';
    return _qualityLabel(track) ?? '${track.height}p';
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
      _showBufferingIndicator = true;
      _publishControlState();
    });
  }

  void _setVisible(bool visible) {
    if (_controlsVisible == visible) return;
    _controlsVisible = visible;
    _controlsCubit.setControlsVisible(visible);
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
    _liveEdge = estimated;
    _controlsCubit.setLiveEdge(estimated);
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
    final controller = widget.controller;
    if (controller != null) unawaited(_controlsCubit.seek(controller, target));
  }

  void _setPlaybackSpeed(double speed) {
    _playbackSpeed = speed;
    unawaited(widget.controller?.setPlaybackSpeed(speed));
    _revealControls();
  }

  void _onEpisodeListVisibilityChanged(bool visible) {
    _hideTimer?.cancel();
    if (!visible) _revealControls();
  }

  Future<void> _openSettings() async {
    _hideTimer?.cancel();
    final picked = await showDialog<double>(
      context: _modalContext,
      builder: (_) =>
          PlayerPlaybackSettingsDialog(currentSpeed: _playbackSpeed),
    );
    if (!mounted) return;
    if (picked != null) _setPlaybackSpeed(picked);
    _revealControls();
  }

  Future<void> _openSubtitlePicker() async {
    if (widget.isLive) return;
    _hideTimer?.cancel();
    final currentSub = widget.controller?.activeSubtitle;
    final subtitlePreference = AppScope.of(
      context,
    ).subtitlePreferenceController;
    final language = subtitlePreference.languageCode;
    final tracks = subtitlePreference.tracksForPicker(
      _current.stream.subtitles,
    );
    final picked = await showModalBottomSheet<PlayerSubtitleSelection>(
      context: _modalContext,
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
        translationSourceTracks: _current.stream.subtitles,
        initialExternalTracks: subtitlePreference.rememberedExternalSubtitles(
          widget.media.ref,
        ),
        onExternalTracksFetched: (tracks) => subtitlePreference
            .rememberExternalSubtitles(widget.media.ref, tracks),
        initialOnlineResults: language == null
            ? const []
            : subtitlePreference.rememberedOnlineSearchResults(
                widget.media.ref,
                language,
              ),
        selectedOnlineResultKey: subtitlePreference
            .selectedOnlineSearchResultKey(widget.media.ref),
        onOnlineResultsFetched: (results) {
          if (language == null) return;
          subtitlePreference.rememberOnlineSearchResults(
            widget.media.ref,
            language,
            results,
          );
        },
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
      subtitlePreference.selectOnlineSearchResult(
        widget.media.ref,
        picked.onlineSearchResultKey,
      );
      final isOff = picked.track == null;
      _activeSubtitleLabel = isOff
          ? null
          : subtitleIndicatorLabel(picked.track!.label);
      _publishControlState();
    }
    _revealControls();
  }

  Future<void> _openQualityPicker() async {
    if (_qualitySwitching) {
      _revealControls();
      return;
    }
    _hideTimer?.cancel();
    final trackRefresher = widget.controller is AppPlayerTrackRefresher
        ? widget.controller! as AppPlayerTrackRefresher
        : null;
    if (trackRefresher != null) {
      await trackRefresher.refreshTracks();
      if (!mounted) return;
    }
    final tracks = widget.controller?.qualityTracks ?? const [];
    final active = widget.controller?.activeQuality;
    final pinned =
        _qualityPinned ??
        (AppScope.of(context).qualityPreferenceController.maxHeight != null);
    await showModalBottomSheet<void>(
      context: _modalContext,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => PlayerQualityPickerSheet(
        tracks: tracks,
        current: pinned ? active : null,
        playing: active,
        onSelect: _requestQuality,
      ),
    );
    if (!mounted) return;
    _revealControls();
  }

  Future<bool> _requestQuality(AppQualityTrack picked) async {
    if (!mounted) return false;
    widget.onSettling(_settlingGrace(trackSwitch: true));
    final controller = widget.controller;
    if (controller == null) return false;
    final requestGeneration = ++_qualityRequestGeneration;
    final previousLabel =
        _activeQualityLabel ?? _qualityLabel(controller.activeQuality);
    final previousPinned = _qualityPinned;
    _qualitySwitching = true;
    _activeQualityLabel = '${_requestedQualityLabel(picked)}…';
    _publishControlState();
    try {
      await controller.setQuality(picked);
      if (!mounted ||
          requestGeneration != _qualityRequestGeneration ||
          !identical(controller, widget.controller)) {
        return false;
      }
      _qualityPinned = picked.id == 'auto' ? false : picked.height > 0;
      _qualitySwitching = false;
      _activeQualityLabel = _displayQualityLabel(controller);
      _publishControlState();
      return true;
    } catch (error) {
      if (!mounted ||
          requestGeneration != _qualityRequestGeneration ||
          !identical(controller, widget.controller)) {
        return false;
      }
      _qualityPinned = previousPinned;
      _qualitySwitching = false;
      _activeQualityLabel = previousLabel;
      if (kDebugMode) {
        debugPrint('[Player] quality_switch_rejected ${error.runtimeType}');
      }
      _publishControlState();
      return false;
    }
  }

  Future<void> _openAudioPicker() async {
    _hideTimer?.cancel();
    final tracks = widget.controller?.audioTracks ?? const [];
    final picked = await showModalBottomSheet<AppAudioTrack>(
      context: _modalContext,
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
      onMinimize: widget.onMinimize,
      fitMode: widget.fitMode,
      onToggleFit: widget.onToggleFit,
      landscapeLocked: widget.landscapeLocked,
      onToggleLandscape: widget.onToggleLandscape,
      onOpenSettings: _openSettings,
      onEpisodeListVisibilityChanged: _onEpisodeListVisibilityChanged,
      onSkip: _skip,
      skipIntroLabel: _activeIntroSegment == null ? null : 'Skip intro',
      onSkipIntro: _skipIntro,
      onTogglePlayPause: _togglePlayPause,
      onChangeSource: () {
        _hideTimer?.cancel();
        widget.onChangeSource();
      },
      episodeEntries: _episodeEntries,
      currentEpisodeRef: widget.media.isEpisode ? widget.media.ref : null,
      onPlayEpisode: widget.onPlayEpisode,
      onOpenSubtitlePicker: _openSubtitlePicker,
      onOpenAudioPicker: audioTracks.length > 1 ? _openAudioPicker : null,
      onOpenMultiView: widget.onOpenMultiView,
      onOpenQualityPicker: _openQualityPicker,
      onTimelineChangeStart: (value) {
        _hideTimer?.cancel();
        _dragValueMs = value;
        _controlsCubit.setDragValue(value);
      },
      onTimelineChanged: (value) {
        _dragValueMs = value;
        _controlsCubit.setDragValue(value);
      },
      onTimelineChangeEnd: (value) {
        final current = _controlsCubit.state.value;
        final currentTimelineExtent = widget.isLive
            ? (_liveEdge > liveSeekEdge(current)
                  ? _liveEdge
                  : liveSeekEdge(current))
            : current.duration;
        final target = Duration(milliseconds: value.round());
        final seekTarget = widget.isLive
            ? liveSeekTarget(
                target,
                currentTimelineExtent,
                currentPosition: current.position,
              )
            : target;
        if (seekTarget != null) _seekTo(seekTarget);
        _dragValueMs = null;
        _controlsCubit.setDragValue(null);
        _revealControls();
      },
      playbackSegments: widget.playbackSegments,
      upNextCard: upNextCard,
      controlsCubit: _controlsCubit,
    );
  }
}
