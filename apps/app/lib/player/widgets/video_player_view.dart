import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:video_player/video_player.dart' as vp;
import '../diagnostics/player_diagnostics.dart';
import '../mappers/startup_stream.dart';
import '../models/playback_start_position.dart';
import '../state/video_player_startup.dart';
import '../models/app_player_controller.dart';
import '../state/player_wakelock.dart';
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
    this.startPosition,
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
  final PlaybackStartPosition? startPosition;

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
  Future<void>? _variantSwitch;
  int _playerGeneration = 0;

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
    final variant = preferredStartupVariant(
      widget.stream,
      widget.preferredQualityMaxHeight,
    );
    _preferredQualitySelectionDone = variant != null;
    _activeStream = streamForVariant(widget.stream, variant);
    _player = _createPlayer(_activeStream);
    _videoSurface = vp.VideoPlayer(_player);
    _adapter = _VideoPlayerControllerAdapter(
      _player,
      onSetFit: (mode) {
        if (mounted) setState(() => _fitMode = mode);
      },
      onSelectVariant: _selectVariant,
      streamUrl: widget.stream.url,
      variants: _activeStream.variants,
    );
    _adapter.setActiveUrl(_activeStream.url);
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
    final needsVideoPlayerOptions =
        widget.isLive ||
        allowBackgroundPlayback ||
        (Platform.isIOS && widget.preview);
    return vp.VideoPlayerController.networkUrl(
      Uri.parse(stream.url),
      httpHeaders: stream.headers,
      isLive: widget.isLive,
      videoPlayerOptions: needsVideoPlayerOptions
          ? vp.VideoPlayerOptions(
              allowBackgroundPlayback: allowBackgroundPlayback,
              allowPictureInPicture: !widget.preview,
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

  Future<void> _selectVariant(StreamVariant? variant) {
    final previous = _variantSwitch ?? Future<void>.value();
    final next = previous.then<void>((_) => _selectVariantNow(variant));
    _variantSwitch = next;
    unawaited(
      next.whenComplete(() {
        if (identical(_variantSwitch, next)) _variantSwitch = null;
      }),
    );
    return next;
  }

  Future<void> _selectVariantNow(StreamVariant? variant) async {
    if (!_isActive) return;
    final generation = ++_playerGeneration;
    final oldPlayer = _player;
    final restorePlaying = oldPlayer.value.isPlaying;
    var oldPlayerPaused = false;
    final nextStream = streamForVariant(widget.stream, variant);
    final nextPlayer = _createPlayer(nextStream);
    final stopwatch = Stopwatch()..start();
    var swapped = false;
    try {
      _logOpenStage(
        'quality_initialize_start',
        stopwatch,
        details:
            'url=${safePlaybackUrlForLog(nextStream.url)} '
            'format=${nextStream.format.name}',
      );
      // Prepare the replacement while the current player remains alive. A
      // slow extension rendition must not turn a quality change into a black
      // screen or make the player appear dead.
      await nextPlayer.initialize();
      if (!_isCurrentGeneration(generation)) {
        await nextPlayer.dispose();
        return;
      }
      _logOpenStage(
        'quality_initialize_done',
        stopwatch,
        details:
            'duration=${nextPlayer.value.duration.inMilliseconds}ms '
            'size=${nextPlayer.value.size.width}x${nextPlayer.value.size.height}',
      );
      await nextPlayer.setLooping(widget.looping);
      if (!_isCurrentGeneration(generation)) {
        await nextPlayer.dispose();
        return;
      }
      await nextPlayer.setVolume(widget.muted ? 0 : 1);
      if (!_isCurrentGeneration(generation)) {
        await nextPlayer.dispose();
        return;
      }
      if (restorePlaying) {
        await oldPlayer.pause();
        oldPlayerPaused = true;
        _logOpenStage('quality_old_player_paused', stopwatch);
      }
      final restorePosition = oldPlayer.value.position;
      if (restorePosition > Duration.zero) {
        final duration = nextPlayer.value.duration;
        final target = duration > Duration.zero && restorePosition > duration
            ? duration
            : restorePosition;
        _logOpenStage(
          'quality_seek_start',
          stopwatch,
          details: 'target_ms=${target.inMilliseconds}',
        );
        await nextPlayer.seekTo(target);
        if (!_isCurrentGeneration(generation)) {
          await nextPlayer.dispose();
          return;
        }
        _logOpenStage('quality_seek_done', stopwatch);
      }

      await _videoEventSubscription?.cancel();
      _videoEventSubscription = null;
      oldPlayer.removeListener(_onValueChanged);
      _playbackDiagnosticsTimer?.cancel();
      _startupHealthStartedAt = null;
      _startupHealthPassed = false;
      _activeStream = nextStream;
      _player = nextPlayer;
      swapped = true;
      _videoSurface = vp.VideoPlayer(_player);
      _adapter.attachPlayer(_player);
      _adapter.setActiveUrl(_activeStream.url);
      _bindPlayer();
      if (mounted) setState(() {});
      await oldPlayer.dispose();
      await _open(
        restorePlaying: restorePlaying,
        applyPreferredQuality: false,
        initialized: true,
        generation: generation,
        stopwatch: stopwatch,
      );
    } catch (error) {
      if (!swapped) await nextPlayer.dispose();
      if (!_isCurrentGeneration(generation)) return;
      if (oldPlayerPaused) {
        try {
          await oldPlayer.play();
          _logOpenStage('quality_old_player_resumed', stopwatch);
        } catch (_) {
          // Preserve the switch error; the old player may already be invalid.
        }
      }
      _logOpenStage(
        'quality_switch_failed',
        stopwatch,
        details: 'error=${redactPlaybackLogText(error)}',
      );
      // The old player was intentionally kept alive until initialization
      // succeeded, so a failed rendition leaves playback usable.
    }
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
    bool initialized = false,
    int? generation,
    Stopwatch? stopwatch,
  }) async {
    final clock = stopwatch ?? (Stopwatch()..start());
    final currentGeneration = generation ?? _playerGeneration;
    _openStopwatch = clock;
    final startup = VideoPlayerStartup(
      player: _player,
      controller: _adapter,
      stream: _activeStream,
      refreshTracks: _adapter.refreshTracks,
      isCurrent: () => _isCurrentGeneration(currentGeneration),
      log: (stage, {details}) => _logOpenStage(stage, clock, details: details),
      maxHeight: widget.preferredQualityMaxHeight,
      preferredQualityDone:
          !applyPreferredQuality || _preferredQualitySelectionDone,
    );
    try {
      final playing = restorePlaying ?? widget.playing;
      final opened = await startup.open(
        initialized: initialized,
        looping: widget.looping,
        muted: widget.muted,
        playing: playing,
        isLive: widget.isLive,
        startPosition: restorePosition == null
            ? widget.startPosition
            : PlaybackStartPosition.exact(restorePosition),
        subtitleLanguage: widget.preferredSubtitleLanguage,
        externalSubtitle: widget.preferredExternalSubtitle,
      );
      if (!opened || !_isCurrentGeneration(currentGeneration)) return;
      _preferredQualitySelectionDone = startup.preferredQualityDone;
      unawaited(startup.refreshAfterMetadata());
      if (playing) {
        _startPlaybackDiagnostics(clock);
      } else {
        _reportPlaybackReady(clock);
      }
    } catch (error) {
      if (!_isCurrentGeneration(currentGeneration)) return;
      _logOpenStage(
        'failed',
        clock,
        details: 'error=${redactPlaybackLogText(error)}',
      );
      _adapter.reportError(error);
    }
  }

  bool _isCurrentGeneration(int? generation) =>
      _isActive && (generation == null || generation == _playerGeneration);

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
