import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:video_player/video_player.dart' as vp;
import '../diagnostics/player_diagnostics.dart';
import '../data/local_hls_proxy.dart';
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
const _startupHealthMaxTimeout = Duration(seconds: 30);
const _livePlaybackProgressTolerance = Duration(milliseconds: 250);
const _variantSeekTimeout = Duration(seconds: 20);

void _logFullPlaybackUrl(String stage, String url) {
  if (!kDebugMode) return;
  debugPrint('[VideoPlayerVOD] ${stage}_full url=$url');
}

/// Progressive provider variants may not complete a remote seek until the
/// native player has started reading the asset.
@visibleForTesting
bool shouldWarmVariantBeforeSeek(StreamFormat format) =>
    format == StreamFormat.mp4 || format == StreamFormat.other;

/// Returns true only when startup has evidence that media can be rendered.
///
/// A native controller may report `isPlaying` while it is still waiting for a
/// first frame. For a buffering VOD, a non-zero position is only meaningful
/// after it has advanced from the first sample; buffered bytes alone are not a
/// first-frame signal.
@visibleForTesting
bool startupPlaybackIsReady({
  required bool isPlaying,
  required bool isBuffering,
  required bool isLive,
  required Duration bufferedPosition,
  required bool positionAdvanced,
}) {
  if (!isPlaying) return false;
  if (positionAdvanced) return true;
  return !isLive && !isBuffering && bufferedPosition > Duration.zero;
}

/// Controls whether the Flutter-rendered subtitle overlay is visible.
class PlayerSubtitleVisibility extends InheritedWidget {
  const PlayerSubtitleVisibility({
    super.key,
    required this.showSubtitles,
    required super.child,
  });

  final bool showSubtitles;

  static bool of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<PlayerSubtitleVisibility>()
          ?.showSubtitles ??
      true;

  @override
  bool updateShouldNotify(PlayerSubtitleVisibility oldWidget) =>
      showSubtitles != oldWidget.showSubtitles;
}

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
  vp.VideoPlayerController? _player;
  late PlayableStream _activeStream;
  _VideoPlayerControllerAdapter? _adapter;
  Widget _videoSurface = const ColoredBox(color: Colors.black);
  late PlayerFitMode _fitMode;
  bool _readyReported = false;
  bool _preferredQualitySelectionDone = false;
  Stopwatch? _openStopwatch;
  bool _nativePlayingReported = false;
  bool _openStarted = false;
  Timer? _wakelockRefreshTimer;
  PlayerWakelockLease? _wakelock;
  Timer? _playbackDiagnosticsTimer;
  Timer? _livePlaybackKickTimer;
  StreamSubscription<vp.VideoEvent>? _videoEventSubscription;
  DateTime? _startupHealthStartedAt;
  DateTime? _startupHealthLastProgressAt;
  Duration? _startupHealthLastPosition;
  Duration? _startupHealthLastContiguousBuffered;
  bool _startupHealthPassed = false;
  bool _disposed = false;
  Future<bool>? _variantSwitch;
  LocalHlsProxy? _playbackProxy;
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
    if (widget.isLive && !widget.preview && !_activeStream.isProtected) {
      _playbackProxy = LocalHlsProxy(logger: kDebugMode ? debugPrint : null);
    }
    unawaited(_preparePlayer());
  }

  Future<void> _preparePlayer() async {
    final stopwatch = Stopwatch()..start();
    final originalStream = _activeStream;
    var playerStream = originalStream;
    final proxy = _playbackProxy;
    _logProxy(
      'prepare_start live=${widget.isLive} '
      'url=${safePlaybackUrlForLog(originalStream.url)}',
    );
    if (proxy != null) {
      try {
        playerStream = await proxy.wrap(originalStream);
        _logProxy(
          'enabled elapsed=${stopwatch.elapsedMilliseconds}ms '
          'url=${safePlaybackUrlForLog(originalStream.url)}',
        );
      } catch (error) {
        await proxy.dispose();
        _playbackProxy = null;
        _logProxy('disabled reason=${redactPlaybackLogText(error)}');
      }
    }
    if (!_isActive) return;
    _activeStream = playerStream;
    final player = _createPlayer(playerStream);
    _logFullPlaybackUrl('player_url', playerStream.url);
    final adapter = _VideoPlayerControllerAdapter(
      player,
      onSetFit: (mode) {
        if (mounted) setState(() => _fitMode = mode);
      },
      onSelectVariant: _selectVariant,
      streamUrl: widget.stream.url,
      variants: originalStream.variants,
    );
    _player = player;
    _adapter = adapter;
    _videoSurface = vp.VideoPlayer(player);
    adapter.setActiveUrl(playerStream.url);
    _bindPlayer();
    widget.onControllerCreated?.call(adapter);
    _logProxy(
      'player_created elapsed=${stopwatch.elapsedMilliseconds}ms '
      'url=${safePlaybackUrlForLog(playerStream.url)}',
    );
    if (mounted) setState(() {});
    if (!widget.preview || widget.playing) _startOpen();
  }

  void _startOpen() {
    if (_openStarted || _player == null || _adapter == null) return;
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
    final player = _player;
    final adapter = _adapter;
    if (player == null || adapter == null) return;
    player.addListener(_onValueChanged);
    _videoEventSubscription = player.videoEvents.listen((event) {
      switch (event.eventType) {
        case vp.VideoEventType.pictureInPictureStarted:
          adapter.reportPictureInPictureStarted();
        case vp.VideoEventType.pictureInPictureRestore:
          adapter.reportPictureInPictureRestore();
        case vp.VideoEventType.pictureInPictureClosed:
          adapter.reportPictureInPictureClosed();
        default:
          break;
      }
    });
  }

  Future<bool> _selectVariant(StreamVariant? variant) {
    final previous = _variantSwitch ?? Future<bool>.value(true);
    final next = previous.then<bool>((_) => _selectVariantNow(variant));
    _variantSwitch = next;
    unawaited(
      next.whenComplete(() {
        if (identical(_variantSwitch, next)) _variantSwitch = null;
      }),
    );
    return next;
  }

  Future<bool> _selectVariantNow(StreamVariant? variant) async {
    final oldPlayer = _player;
    final adapter = _adapter;
    if (!_isActive || oldPlayer == null || adapter == null) return false;
    final generation = ++_playerGeneration;
    final restorePlaying = oldPlayer.value.isPlaying;
    var oldPlayerPaused = false;
    final originalNextStream = streamForVariant(widget.stream, variant);
    var nextStream = originalNextStream;
    final proxy = _playbackProxy;
    if (proxy != null) {
      try {
        nextStream = await proxy.wrap(originalNextStream);
      } catch (error) {
        _logProxy('variant_disabled reason=${redactPlaybackLogText(error)}');
        _playbackProxy = null;
        await proxy.dispose();
      }
    }
    if (!_isCurrentGeneration(generation)) return false;
    final nextPlayer = _createPlayer(nextStream);
    _logFullPlaybackUrl('quality_url', nextStream.url);
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
        return false;
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
        return false;
      }
      await nextPlayer.setVolume(widget.muted ? 0 : 1);
      if (!_isCurrentGeneration(generation)) {
        await nextPlayer.dispose();
        return false;
      }
      final restorePosition = oldPlayer.value.position;
      if (restorePlaying && shouldWarmVariantBeforeSeek(nextStream.format)) {
        // Some remote MP4 origins do not complete a seek until playback has
        // started. Warm the replacement while the old controller remains
        // visible, then seek to the matching position before swapping.
        await nextPlayer.play();
        _logOpenStage('quality_prepare_play', stopwatch);
      }
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
        // Keep the old player running while the replacement seeks. AVPlayer's
        // completion callback can be delayed by a slow rendition; the old
        // player must remain usable if that happens.
        await nextPlayer.seekTo(target).timeout(_variantSeekTimeout);
        if (!_isCurrentGeneration(generation)) {
          await nextPlayer.dispose();
          return false;
        }
        _logOpenStage('quality_seek_done', stopwatch);
      }

      if (restorePlaying) {
        await oldPlayer.pause();
        oldPlayerPaused = true;
        _logOpenStage('quality_old_player_paused', stopwatch);
      }

      await _videoEventSubscription?.cancel();
      _videoEventSubscription = null;
      oldPlayer.removeListener(_onValueChanged);
      _playbackDiagnosticsTimer?.cancel();
      _startupHealthStartedAt = null;
      _startupHealthLastProgressAt = null;
      _startupHealthLastPosition = null;
      _startupHealthLastContiguousBuffered = null;
      _startupHealthPassed = false;
      _activeStream = nextStream;
      _player = nextPlayer;
      swapped = true;
      // Detach the old texture before disposing its native player. The widget
      // tree may still contain the previous TextureLayer until the scheduled
      // frame is committed; disposing the player immediately can make the
      // macOS raster thread resolve an already-unregistered texture.
      _videoSurface = const ColoredBox(color: Colors.black);
      adapter.attachPlayer(nextPlayer);
      adapter.setActiveUrl(_activeStream.url);
      _bindPlayer();
      if (mounted) setState(() {});
      if (mounted) await WidgetsBinding.instance.endOfFrame;
      await oldPlayer.dispose();
      _videoSurface = vp.VideoPlayer(nextPlayer);
      if (mounted) setState(() {});
      await _open(
        restorePlaying: restorePlaying,
        applyPreferredQuality: false,
        initialized: true,
        skipStartPosition: true,
        generation: generation,
        stopwatch: stopwatch,
      );
      return true;
    } catch (error) {
      if (!swapped) await nextPlayer.dispose();
      if (!_isCurrentGeneration(generation)) return false;
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
      return false;
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
    bool skipStartPosition = false,
    int? generation,
    Stopwatch? stopwatch,
  }) async {
    final player = _player;
    final adapter = _adapter;
    if (player == null || adapter == null) return;
    final clock = stopwatch ?? (Stopwatch()..start());
    final currentGeneration = generation ?? _playerGeneration;
    _openStopwatch = clock;
    final startup = VideoPlayerStartup(
      player: player,
      controller: adapter,
      stream: _activeStream,
      refreshTracks: adapter.refreshTracks,
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
        startPosition: skipStartPosition
            ? null
            : restorePosition == null
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
        _scheduleLivePlaybackKick(player, currentGeneration, clock);
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
      adapter.reportError(error);
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

  void _logProxy(String message) {
    if (!kDebugMode) return;
    debugPrint('[LocalHlsProxy] $message');
  }

  void _startPlaybackDiagnostics(Stopwatch stopwatch) {
    _startupHealthStartedAt = DateTime.now();
    _startupHealthLastProgressAt = null;
    _startupHealthLastPosition = null;
    _startupHealthLastContiguousBuffered = null;
    _startupHealthPassed = false;
    _playbackDiagnosticsTimer?.cancel();
    _playbackDiagnosticsTimer = Timer.periodic(
      _playbackDiagnosticsInterval,
      (_) => _samplePlaybackHealth(stopwatch),
    );
    _samplePlaybackHealth(stopwatch);
  }

  void _scheduleLivePlaybackKick(
    vp.VideoPlayerController player,
    int generation,
    Stopwatch stopwatch,
  ) {
    if (!widget.isLive) return;
    _livePlaybackKickTimer?.cancel();
    final initialPosition = player.value.position;
    _livePlaybackKickTimer = Timer(const Duration(seconds: 1), () async {
      _livePlaybackKickTimer = null;
      if (!_isCurrentGeneration(generation) || !player.value.isInitialized) {
        return;
      }
      if (player.value.position >
          initialPosition + _livePlaybackProgressTolerance) {
        return;
      }
      _logOpenStage('live_play_kick_start', stopwatch);
      await player.play();
      if (_isCurrentGeneration(generation)) {
        _logOpenStage('live_play_kick_done', stopwatch);
      }
    });
  }

  void _samplePlaybackHealth(Stopwatch stopwatch) {
    final player = _player;
    final adapter = _adapter;
    if (!mounted || player == null || adapter == null) return;
    final value = player.value;
    final bufferedPosition = value.buffered.fold<Duration>(
      Duration.zero,
      (latest, range) => range.end > latest ? range.end : latest,
    );
    final appValue = adapter.value.value;
    final contiguousBufferedPosition = bufferedEndAtPosition(
      position: value.position,
      ranges: appValue.bufferedRanges,
    );
    final contiguousAhead = contiguousBufferedPosition > value.position
        ? contiguousBufferedPosition - value.position
        : Duration.zero;
    final previousPosition = _startupHealthLastPosition;
    final previousContiguousBuffered = _startupHealthLastContiguousBuffered;
    final positionAdvanced =
        previousPosition != null &&
        value.position > previousPosition + _livePlaybackProgressTolerance;
    final bufferAdvanced =
        previousContiguousBuffered != null &&
        contiguousBufferedPosition >
            previousContiguousBuffered + _livePlaybackProgressTolerance;
    final now = DateTime.now();
    _startupHealthLastPosition = value.position;
    _startupHealthLastContiguousBuffered = contiguousBufferedPosition;
    if (positionAdvanced || bufferAdvanced) {
      _startupHealthLastProgressAt = now;
    }
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
          'contiguous_buffered_ms=${contiguousBufferedPosition.inMilliseconds} '
          'seekable_ms=${seekablePosition.inMilliseconds} '
          'ahead_ms=${contiguousAhead.inMilliseconds} '
          'is_playing=${value.isPlaying} '
          'is_buffering=${value.isBuffering} '
          'duration_ms=${value.duration.inMilliseconds}',
    );

    if (!_startupHealthPassed) {
      if (startupPlaybackIsReady(
        isPlaying: value.isPlaying,
        isBuffering: value.isBuffering,
        isLive: widget.isLive,
        bufferedPosition: bufferedPosition,
        positionAdvanced: positionAdvanced,
      )) {
        _startupHealthPassed = true;
        _reportPlaybackReady(stopwatch);
        return;
      }
      final startedAt = _startupHealthStartedAt;
      final lastProgressAt = _startupHealthLastProgressAt;
      final elapsed = startedAt == null
          ? Duration.zero
          : now.difference(startedAt);
      final idle = lastProgressAt == null
          ? elapsed
          : now.difference(lastProgressAt);
      final exceededIdleBudget = idle >= _startupHealthTimeout;
      final exceededMaxBudget = elapsed >= _startupHealthMaxTimeout;
      if (startedAt != null && (exceededIdleBudget || exceededMaxBudget)) {
        _startupHealthPassed = true;
        _logOpenStage(
          'startup_health_failed',
          stopwatch,
          details:
              'reason=${lastProgressAt == null ? 'no_media_progress' : 'startup_progress_stalled'} '
              'idle_s=${idle.inSeconds} max_timeout_s=${_startupHealthMaxTimeout.inSeconds}',
        );
        adapter.reportError(
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
    final player = _player;
    final adapter = _adapter;
    if (player == null || adapter == null) return;
    adapter.syncValue();
    final value = player.value;
    if (value.isPlaying && !_nativePlayingReported) {
      _nativePlayingReported = true;
      final stopwatch = _openStopwatch;
      if (stopwatch != null) {
        _logOpenStage('native_playing', stopwatch);
      }
    }
    if (value.hasError) {
      adapter.reportError(value.errorDescription!);
    }
    if (value.isCompleted) {
      _playbackDiagnosticsTimer?.cancel();
      _playbackDiagnosticsTimer = null;
      _livePlaybackKickTimer?.cancel();
      _livePlaybackKickTimer = null;
      adapter.reportCompleted();
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
          final player = _player;
          if (player != null) unawaited(player.play());
        } else {
          _startOpen();
        }
      } else {
        final player = _player;
        if (_openStarted && player?.value.isInitialized == true) {
          unawaited(player!.pause());
        }
      }
    }
    if (oldWidget.muted != widget.muted) {
      final player = _player;
      if (player != null) {
        unawaited(player.setVolume(widget.muted ? 0 : 1));
      }
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
    _livePlaybackKickTimer?.cancel();
    _wakelockRefreshTimer?.cancel();
    if (widget.wakelock ?? !widget.preview) {
      WidgetsBinding.instance.removeObserver(this);
      _wakelock?.release();
    }
    final player = _player;
    final adapter = _adapter;
    player?.removeListener(_onValueChanged);
    unawaited(_videoEventSubscription?.cancel());
    adapter?.dispose();
    unawaited(player?.dispose() ?? Future<void>.value());
    unawaited(_playbackProxy?.dispose() ?? Future<void>.value());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final player = _player;
    if (player == null) return const ColoredBox(color: Colors.black);
    return ValueListenableBuilder<vp.VideoPlayerValue>(
      valueListenable: player,
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
                    if (PlayerSubtitleVisibility.of(context))
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
}
