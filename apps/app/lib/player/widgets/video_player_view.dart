import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:video_player/video_player.dart' as vp;
import '../diagnostics/player_diagnostics.dart';
import '../models/app_player_controller.dart';
import '../state/player_wakelock.dart';
import '../state/quality_preference_controller.dart';
import '../state/subtitle_preference_controller.dart';
import 'player_subtitle_style.dart';
import 'subtitle_html_text.dart';
import '../mappers/video_player_drm_mapping.dart';

part 'video_player_view_controller.dart';
part 'video_player_view_subtitles.dart';

const _playbackDiagnosticsInterval = Duration(seconds: 2);
const _startupHealthTimeout = Duration(seconds: 8);

/// The app's native video player for HLS, DRM, live, and on-demand playback.
class VideoPlayerView extends StatefulWidget {
  const VideoPlayerView({
    super.key,
    required this.stream,
    this.isLive = false,
    this.liveOptions,
    this.onControllerCreated,
    this.onPlaybackReady,
    this.preferredSubtitleLanguage,
    this.preferredQualityMaxHeight,
    this.preferredExternalSubtitle,
    this.subtitleAppearance,
    this.muted = false,
    this.looping = false,
    this.playing = true,
    this.fit = BoxFit.contain,
    this.preview = false,
    this.wakelock,
  });

  final PlayableStream stream;
  final bool isLive;

  /// Optional live latency and buffering tuning passed to the native player.
  ///
  /// When omitted, Apple platforms use a more tolerant live default while
  /// Android keeps the Media3/ExoPlayer package defaults.
  final vp.VideoPlayerLiveOptions? liveOptions;
  final void Function(Object? controller)? onControllerCreated;
  final void Function(Object? controller)? onPlaybackReady;
  final String? preferredSubtitleLanguage;
  final int? preferredQualityMaxHeight;
  final SubtitleTrack? preferredExternalSubtitle;
  final SubtitleAppearance? subtitleAppearance;
  final bool muted;
  final bool looping;
  final bool playing;
  final BoxFit fit;
  final bool preview;
  final bool? wakelock;

  @override
  State<VideoPlayerView> createState() => _VideoPlayerViewState();
}

/// Returns the visible video area where a fixed-size subtitle should be
/// placed. The subtitle must not be a child of the [FittedBox], otherwise its
/// font size is scaled with the source video's intrinsic resolution.
@visibleForTesting
Rect subtitleOverlayRect({
  required Size videoSize,
  required Size viewportSize,
  required BoxFit fit,
}) {
  if (!videoSize.width.isFinite ||
      !videoSize.height.isFinite ||
      videoSize.width <= 0 ||
      videoSize.height <= 0 ||
      !viewportSize.width.isFinite ||
      !viewportSize.height.isFinite ||
      viewportSize.width <= 0 ||
      viewportSize.height <= 0) {
    return Offset.zero & viewportSize;
  }
  if (fit != BoxFit.contain) return Offset.zero & viewportSize;

  final scale = math.min(
    viewportSize.width / videoSize.width,
    viewportSize.height / videoSize.height,
  );
  final displayedSize = Size(videoSize.width * scale, videoSize.height * scale);
  return Rect.fromCenter(
    center: viewportSize.center(Offset.zero),
    width: displayedSize.width,
    height: displayedSize.height,
  );
}

class _VideoPlayerViewState extends State<VideoPlayerView>
    with WidgetsBindingObserver {
  late vp.VideoPlayerController _player;
  late PlayableStream _activeStream;
  late final _VideoPlayerControllerAdapter _adapter;
  late Widget _videoSurface;
  late PlayerFitMode _fitMode;
  bool _readyReported = false;
  bool _preferredQualitySelectionDone = false;
  Stopwatch? _openStopwatch;
  bool _nativePlayingReported = false;
  bool _openStarted = false;
  Timer? _wakelockRefreshTimer;
  PlayerWakelockLease? _wakelock;
  Timer? _playbackDiagnosticsTimer;
  StreamSubscription<vp.VideoEvent>? _videoEventSubscription;
  DateTime? _startupHealthStartedAt;
  bool _startupHealthPassed = false;
  bool _disposed = false;

  bool get _isActive => mounted && !_disposed;

  @override
  void initState() {
    super.initState();
    _fitMode = widget.fit == BoxFit.contain
        ? PlayerFitMode.contain
        : PlayerFitMode.cover;
    if (widget.wakelock ?? !widget.preview) {
      WidgetsBinding.instance.addObserver(this);
      _wakelock = PlayerWakelockLease.acquire();
      _wakelockRefreshTimer = Timer.periodic(
        const Duration(seconds: 15),
        (_) => _wakelock?.refresh(),
      );
    }
    _activeStream = widget.stream;
    _player = _createPlayer(_activeStream);
    _videoSurface = vp.VideoPlayer(_player);
    _adapter = _VideoPlayerControllerAdapter(
      _player,
      onSetFit: (mode) {
        if (mounted) setState(() => _fitMode = mode);
      },
      onSelectVariant: _selectVariant,
      streamUrl: _activeStream.url,
      variants: _activeStream.variants,
    );
    _bindPlayer();
    widget.onControllerCreated?.call(_adapter);
    if (!widget.preview || widget.playing) _startOpen();
  }

  void _startOpen() {
    if (_openStarted) return;
    _openStarted = true;
    unawaited(_open());
  }

  vp.VideoPlayerController _createPlayer(PlayableStream stream) {
    // The texture backend owns an invisible AVPlayerLayer on iOS, which is
    // enough for AVKit PiP while keeping Flutter controls above the video.
    // A platform view is still required for protected streams.
    final usePlatformView = stream.isProtected;
    final allowBackgroundPlayback = Platform.isIOS && !widget.preview;
    return vp.VideoPlayerController.networkUrl(
      Uri.parse(stream.url),
      httpHeaders: stream.headers,
      isLive: widget.isLive,
      videoPlayerOptions: widget.isLive || allowBackgroundPlayback
          ? vp.VideoPlayerOptions(
              allowBackgroundPlayback: allowBackgroundPlayback,
              liveConfiguration: widget.isLive
                  ? widget.liveOptions ?? _defaultLiveOptions()
                  : null,
            )
          : null,
      drmConfiguration: videoPlayerDrmConfiguration(stream),
      viewType: usePlatformView
          ? vp.VideoViewType.platformView
          : vp.VideoViewType.textureView,
    );
  }

  void _bindPlayer() {
    _player.addListener(_onValueChanged);
    _videoEventSubscription = _player.videoEvents.listen((event) {
      switch (event.eventType) {
        case vp.VideoEventType.pictureInPictureStarted:
          _adapter.reportPictureInPictureStarted();
        case vp.VideoEventType.pictureInPictureRestore:
          _adapter.reportPictureInPictureRestore();
        case vp.VideoEventType.pictureInPictureClosed:
          _adapter.reportPictureInPictureClosed();
        default:
          break;
      }
    });
  }

  Future<void> _selectVariant(StreamVariant? variant) async {
    if (!_isActive) return;
    final oldPlayer = _player;
    final restorePosition = oldPlayer.value.position;
    final restorePlaying = oldPlayer.value.isPlaying;
    await _videoEventSubscription?.cancel();
    _videoEventSubscription = null;
    oldPlayer.removeListener(_onValueChanged);
    await oldPlayer.dispose();
    if (!_isActive) return;

    _activeStream = variant == null
        ? widget.stream
        : PlayableStream(
            url: variant.url,
            headers: variant.headers.isEmpty
                ? widget.stream.headers
                : variant.headers,
            format: variant.format,
            drm: widget.stream.drm,
            audioUrl: widget.stream.audioUrl,
            label: variant.label,
            subtitles: widget.stream.subtitles,
            variants: widget.stream.variants,
          );
    _player = _createPlayer(_activeStream);
    _videoSurface = vp.VideoPlayer(_player);
    _adapter.attachPlayer(_player);
    _adapter.setActiveUrl(_activeStream.url);
    _bindPlayer();
    if (mounted) setState(() {});
    await _open(
      restorePosition: restorePosition,
      restorePlaying: restorePlaying,
      applyPreferredQuality: false,
    );
  }

  /// Selects app-level live defaults without changing the shared package API.
  vp.VideoPlayerLiveOptions _defaultLiveOptions() {
    final isApple =
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
    if (!isApple) return const vp.VideoPlayerLiveOptions();
    return const vp.VideoPlayerLiveOptions(
      targetOffsetMs: 8000,
      minOffsetMs: 5000,
      maxOffsetMs: 15000,
      preferredForwardBufferDurationMs: 10000,
    );
  }

  Future<void> _open({
    Duration? restorePosition,
    bool? restorePlaying,
    bool applyPreferredQuality = true,
  }) async {
    final stopwatch = Stopwatch()..start();
    _openStopwatch = stopwatch;
    try {
      final audioUrl = _activeStream.audioUrl;
      if (audioUrl != null && audioUrl.isNotEmpty) {
        throw UnsupportedError(
          'The native player does not support a separate audio URL.',
        );
      }
      _logOpenStage(
        'initialize_start',
        stopwatch,
        details:
            'url=${safePlaybackUrlForLog(_activeStream.url)} '
            'format=${_activeStream.format.name}',
      );
      await _player.initialize();
      if (!_isActive) return;
      _logOpenStage(
        'initialize_done',
        stopwatch,
        details:
            'duration=${_player.value.duration.inMilliseconds}ms '
            'size=${_player.value.size.width}x${_player.value.size.height}',
      );
      await _player.setLooping(widget.looping);
      if (!_isActive) return;
      await _player.setVolume(widget.muted ? 0 : 1);
      if (!_isActive) return;
      if (restorePosition != null && restorePosition > Duration.zero) {
        final duration = _player.value.duration;
        final target = duration > Duration.zero && restorePosition > duration
            ? duration
            : restorePosition;
        await _player.seekTo(target);
        if (!_isActive) return;
      }
      _logOpenStage('player_configured', stopwatch);
      await _adapter.refreshTracks();
      if (!_isActive) return;
      _logOpenStage(
        'tracks_initial_done',
        stopwatch,
        details:
            'audio=${_adapter.audioTracks.length} '
            'video=${_adapter.qualityTracks.length}',
      );
      if (applyPreferredQuality) await _applyPreferredQuality();
      if (!_isActive) return;
      _logOpenStage(
        'quality_initial_done',
        stopwatch,
        details: 'active=${_adapter.activeQuality?.id ?? 'auto'}',
      );
      // AVFoundation can report the first frame before it has finished
      // populating its HLS media-selection and variant groups. FlyStream's
      // large master can take seconds, so keep checking briefly rather than
      // freezing the picker empty at the instant its first frame appears.
      unawaited(_refreshTracksAfterMetadata(stopwatch));
      final subtitle = _preferredSubtitle();
      if (subtitle != null) {
        _logOpenStage(
          'subtitle_start',
          stopwatch,
          details: 'language=${subtitle.language}',
        );
        try {
          await _adapter.setSubtitle(subtitle);
        } catch (_) {
          // An external caption must not make an otherwise playable video fail.
        }
        if (!_isActive) return;
        _logOpenStage('subtitle_done', stopwatch);
      } else {
        _logOpenStage('subtitle_skipped', stopwatch);
      }
      if (restorePlaying ?? widget.playing) {
        _logOpenStage('play_start', stopwatch);
        await _player.play();
        if (!_isActive) return;
        _logOpenStage('play_done', stopwatch);
        _startPlaybackDiagnostics(stopwatch);
      } else {
        _logOpenStage('play_skipped', stopwatch);
        _reportPlaybackReady(stopwatch);
      }
    } catch (error) {
      if (!_isActive) return;
      _logOpenStage(
        'failed',
        stopwatch,
        details: 'error=${redactPlaybackLogText(error)}',
      );
      _adapter.reportError(error);
    }
  }

  void _logOpenStage(String stage, Stopwatch stopwatch, {String? details}) {
    if (!kDebugMode) return;
    debugPrint(
      '[VideoPlayerVOD] open_stage=$stage '
      'elapsed=${stopwatch.elapsedMilliseconds}ms'
      '${details == null ? '' : ' $details'}',
    );
  }

  void _startPlaybackDiagnostics(Stopwatch stopwatch) {
    _startupHealthStartedAt = DateTime.now();
    _playbackDiagnosticsTimer?.cancel();
    _playbackDiagnosticsTimer = Timer.periodic(
      _playbackDiagnosticsInterval,
      (_) => _samplePlaybackHealth(stopwatch),
    );
    _samplePlaybackHealth(stopwatch);
  }

  void _samplePlaybackHealth(Stopwatch stopwatch) {
    if (!mounted) return;
    final value = _player.value;
    final bufferedPosition = value.buffered.fold<Duration>(
      Duration.zero,
      (latest, range) => range.end > latest ? range.end : latest,
    );
    final ahead = bufferedPosition > value.position
        ? bufferedPosition - value.position
        : Duration.zero;
    final seekablePosition = value.seekable.fold<Duration>(
      Duration.zero,
      (latest, range) => range.end > latest ? range.end : latest,
    );
    _logOpenStage(
      'playback_state',
      stopwatch,
      details:
          'live=${widget.isLive} '
          'position_ms=${value.position.inMilliseconds} '
          'buffered_ms=${bufferedPosition.inMilliseconds} '
          'seekable_ms=${seekablePosition.inMilliseconds} '
          'ahead_ms=${ahead.inMilliseconds} '
          'is_playing=${value.isPlaying} '
          'is_buffering=${value.isBuffering} '
          'duration_ms=${value.duration.inMilliseconds}',
    );

    if (!_startupHealthPassed) {
      final hasMediaProgress =
          value.position > Duration.zero || bufferedPosition > Duration.zero;
      if (value.isPlaying && !value.isBuffering && hasMediaProgress) {
        _startupHealthPassed = true;
        _reportPlaybackReady(stopwatch);
        return;
      }
      final startedAt = _startupHealthStartedAt;
      if (startedAt != null &&
          DateTime.now().difference(startedAt) >= _startupHealthTimeout) {
        _startupHealthPassed = true;
        _logOpenStage(
          'startup_health_failed',
          stopwatch,
          details: 'reason=no_media_progress timeout_s=8',
        );
        _adapter.reportError(
          StateError('Playback made no media progress during startup.'),
        );
      }
    }
  }

  void _reportPlaybackReady(Stopwatch stopwatch) {
    if (!mounted || _readyReported) return;
    _readyReported = true;
    _logOpenStage('ready_reported', stopwatch);
    widget.onPlaybackReady?.call(_adapter);
  }

  Future<void> _refreshTracksAfterMetadata(Stopwatch stopwatch) async {
    var attempt = 0;
    for (final delay in const [
      Duration(seconds: 1),
      Duration(seconds: 3),
      Duration(seconds: 6),
    ]) {
      await Future<void>.delayed(delay);
      if (!mounted) return;
      attempt++;
      if (!_isActive) return;
      _logOpenStage(
        'tracks_retry_start',
        stopwatch,
        details: 'attempt=$attempt',
      );
      try {
        await _adapter.refreshTracks();
        if (!_isActive) return;
        await _applyPreferredQuality();
        if (!_isActive) return;
        _logOpenStage(
          'tracks_retry_done',
          stopwatch,
          details:
              'attempt=$attempt audio=${_adapter.audioTracks.length} '
              'video=${_adapter.qualityTracks.length}',
        );
      } catch (_) {
        // An HLS source with no selectable group simply keeps an empty picker.
        _logOpenStage(
          'tracks_retry_failed',
          stopwatch,
          details: 'attempt=$attempt',
        );
      }
    }
  }

  Future<void> _applyPreferredQuality() async {
    if (_preferredQualitySelectionDone) return;
    final track = preferredQualityTrack(
      tracks: _adapter.qualityTracks,
      maxHeight: widget.preferredQualityMaxHeight,
    );
    if (track == null) return;
    if (track.id == _adapter.activeQuality?.id) {
      _preferredQualitySelectionDone = true;
      return;
    }
    try {
      await _adapter.setQuality(track);
      if (!_isActive) return;
      _preferredQualitySelectionDone = true;
    } catch (error) {
      if (kDebugMode) {
        debugPrint(
          '[VideoPlayerVOD] preferred_quality_unavailable '
          '${error.runtimeType}',
        );
      }
    }
  }

  SubtitleTrack? _preferredSubtitle() {
    final external = widget.preferredExternalSubtitle;
    if (external != null) return external;
    final language = widget.preferredSubtitleLanguage;
    if (language == null) return null;
    for (final track in _activeStream.subtitles) {
      if (subtitleLanguageKey(track.language) ==
          subtitleLanguageKey(language)) {
        return track;
      }
    }
    return null;
  }

  void _onValueChanged() {
    _adapter.syncValue();
    final value = _player.value;
    if (value.isPlaying && !_nativePlayingReported) {
      _nativePlayingReported = true;
      final stopwatch = _openStopwatch;
      if (stopwatch != null) {
        _logOpenStage('native_playing', stopwatch);
      }
    }
    if (value.hasError) {
      _adapter.reportError(value.errorDescription!);
    }
    if (value.isCompleted) {
      _playbackDiagnosticsTimer?.cancel();
      _playbackDiagnosticsTimer = null;
      _adapter.reportCompleted();
    }
  }

  @override
  void didUpdateWidget(covariant VideoPlayerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fit != widget.fit) {
      final nextFit = widget.fit == BoxFit.contain
          ? PlayerFitMode.contain
          : PlayerFitMode.cover;
      if (_fitMode != nextFit) setState(() => _fitMode = nextFit);
    }
    if (oldWidget.playing != widget.playing) {
      if (widget.playing) {
        if (_openStarted) {
          unawaited(_player.play());
        } else {
          _startOpen();
        }
      } else if (_openStarted && _player.value.isInitialized) {
        unawaited(_player.pause());
      }
    }
    if (oldWidget.muted != widget.muted) {
      unawaited(_player.setVolume(widget.muted ? 0 : 1));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _wakelock?.refresh();
  }

  @override
  void dispose() {
    _disposed = true;
    _playbackDiagnosticsTimer?.cancel();
    _wakelockRefreshTimer?.cancel();
    if (widget.wakelock ?? !widget.preview) {
      WidgetsBinding.instance.removeObserver(this);
      _wakelock?.release();
    }
    _player.removeListener(_onValueChanged);
    unawaited(_videoEventSubscription?.cancel());
    _adapter.dispose();
    unawaited(_player.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<vp.VideoPlayerValue>(
        valueListenable: _player,
        builder: (context, value, child) {
          if (!value.isInitialized) {
            return const ColoredBox(color: Colors.black);
          }
          final videoSize = value.size;
          final fit = _fitMode == PlayerFitMode.contain
              ? BoxFit.contain
              : BoxFit.cover;
          return ColoredBox(
            color: Colors.black,
            child: ClipRect(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final viewportSize = Size(
                    constraints.maxWidth,
                    constraints.maxHeight,
                  );
                  final subtitleRect = subtitleOverlayRect(
                    videoSize: videoSize,
                    viewportSize: viewportSize,
                    fit: fit,
                  );
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      FittedBox(
                        fit: fit,
                        alignment: Alignment.center,
                        clipBehavior: Clip.hardEdge,
                        child: SizedBox(
                          width: videoSize.width,
                          height: videoSize.height,
                          child: child!,
                        ),
                      ),
                      Positioned.fromRect(
                        rect: subtitleRect,
                        child: SubtitleHtmlText(
                          text: value.caption.text,
                          textStyle:
                              widget.subtitleAppearance?.textStyle ??
                              playerSubtitleTextStyle,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          );
        },
        child: _videoSurface,
      );
}
