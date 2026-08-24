import 'dart:async';

import 'package:better_player_plus/better_player_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';

import '../diagnostics/player_diagnostics.dart';
import '../mappers/stream_player_mapping.dart';
import '../state/player_wakelock.dart';
import 'better_player_controller_adapter.dart';
import 'platform_player_builder.dart';

typedef PlayerBuilder =
    Widget Function(
      BuildContext context,
      PlayableStream stream, {
      required bool isLive,
      void Function(Object? controller)? onControllerCreated,
      void Function(Object? controller)? onPlaybackReady,
      Widget Function(
        BuildContext context,
        Object? controller,
        void Function(bool visibility) onVisibilityChanged,
      )?
      customControlsBuilder,
      String? preferredSubtitleLanguage,
      SubtitleTrack? preferredExternalSubtitle,
      Key? key,
    });

Widget defaultPlayerBuilder(
  BuildContext context,
  PlayableStream stream, {
  required bool isLive,
  void Function(Object? controller)? onControllerCreated,
  void Function(Object? controller)? onPlaybackReady,
  Widget Function(
    BuildContext context,
    Object? controller,
    void Function(bool visibility) onVisibilityChanged,
  )?
  customControlsBuilder,
  String? preferredSubtitleLanguage,
  SubtitleTrack? preferredExternalSubtitle,
  Key? key,
}) => platformPlayerBuilder(
  context,
  stream,
  isLive: isLive,
  onControllerCreated: onControllerCreated,
  onPlaybackReady: onPlaybackReady,
  customControlsBuilder: customControlsBuilder,
  preferredExternalSubtitle: preferredExternalSubtitle,
  preferredSubtitleLanguage: preferredSubtitleLanguage,
  key: key,
);

Widget mobilePlayerBuilder(
  BuildContext context,
  PlayableStream stream, {
  required bool isLive,
  void Function(Object? controller)? onControllerCreated,
  void Function(Object? controller)? onPlaybackReady,
  Widget Function(
    BuildContext context,
    Object? controller,
    void Function(bool visibility) onVisibilityChanged,
  )?
  customControlsBuilder,
  String? preferredSubtitleLanguage,
  SubtitleTrack? preferredExternalSubtitle,
  Key? key,
}) => BetterPlayerView(
  key: key,
  stream: stream,
  isLive: isLive,
  onControllerCreated: onControllerCreated,
  onPlaybackReady: onPlaybackReady,
  customControlsBuilder: customControlsBuilder,
  preferredSubtitleLanguage: preferredSubtitleLanguage,
  preferredExternalSubtitle: preferredExternalSubtitle,
);

class BetterPlayerView extends StatefulWidget {
  const BetterPlayerView({
    super.key,
    required this.stream,
    required this.isLive,
    this.onControllerCreated,
    this.onPlaybackReady,
    this.customControlsBuilder,
    this.preferredSubtitleLanguage,
    this.preferredExternalSubtitle,
    this.aspectRatio,
    this.looping = false,
    this.muted = false,
    this.fit = BoxFit.contain,
    this.playing = true,
    this.preview = false,
  });

  final PlayableStream stream;

  final bool isLive;

  final void Function(Object? controller)? onControllerCreated;

  final void Function(Object? controller)? onPlaybackReady;

  final Widget Function(
    BuildContext context,
    Object? controller,
    void Function(bool visibility) onVisibilityChanged,
  )?
  customControlsBuilder;

  final String? preferredSubtitleLanguage;

  final SubtitleTrack? preferredExternalSubtitle;

  /// Optional container ratio used by embedded previews.
  final double? aspectRatio;

  /// Repeats a short embedded preview instead of stopping at its end.
  final bool looping;

  /// Starts playback without audio, useful for autoplay previews.
  final bool muted;

  /// How the video fills its layout bounds.
  final BoxFit fit;

  /// Controls playback without destroying the native player view.
  final bool playing;

  /// Uses a small buffer and skips disk caching for short embedded previews.
  final bool preview;

  @override
  State<BetterPlayerView> createState() => _BetterPlayerViewState();
}

class _BetterPlayerViewState extends State<BetterPlayerView>
    with WidgetsBindingObserver {
  late final BetterPlayerController _controller;
  late final BetterPlayerControllerAdapter _adapter;
  final GlobalKey _betterPlayerKey = GlobalKey();
  final Stopwatch _diagnosticClock = Stopwatch();
  Timer? _liveHeartbeatTimer;
  Timer? _bufferingDiagnosticTimer;
  Timer? _wakelockRefreshTimer;
  PlayerWakelockLease? _wakelock;
  bool _dataSourceReady = false;

  @override
  void didUpdateWidget(covariant BetterPlayerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.aspectRatio != widget.aspectRatio &&
        widget.aspectRatio != null) {
      _controller.setOverriddenAspectRatio(widget.aspectRatio!);
      // setOverriddenAspectRatio updates the controller value without
      // emitting a rebuild event. Fit emits one and lets BetterPlayer repaint
      // its layout while preserving the native playback controller.
      _controller.setOverriddenFit(widget.fit);
    }
    if (oldWidget.playing == widget.playing || !_dataSourceReady) {
      return;
    }
    final playing = widget.playing;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_dataSourceReady || widget.playing != playing) return;
      if (playing) {
        unawaited(_controller.play());
      } else {
        unawaited(_controller.pause());
      }
    });
  }

  @override
  void initState() {
    super.initState();
    if (!widget.preview) {
      WidgetsBinding.instance.addObserver(this);
      _wakelock = PlayerWakelockLease.acquire();
      _wakelockRefreshTimer = Timer.periodic(
        const Duration(seconds: 15),
        (_) => _wakelock?.refresh(),
      );
    }
    _controller = BetterPlayerController(
      BetterPlayerConfiguration(
        allowedScreenSleep: false,
        aspectRatio: widget.aspectRatio ?? 16 / 9,
        autoPlay: widget.playing,
        looping: widget.looping,
        fit: widget.fit,
        autoDetectFullscreenDeviceOrientation: true,
        deviceOrientationsAfterFullScreen: const [
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
        ],

        controlsConfiguration: BetterPlayerControlsConfiguration(
          playerTheme: widget.customControlsBuilder != null
              ? BetterPlayerTheme.custom
              : BetterPlayerTheme.material,
          showControls: widget.customControlsBuilder != null,
          customControlsBuilder: widget.customControlsBuilder != null
              ? (controller, onVisibilityChanged, config) =>
                    widget.customControlsBuilder!(
                      context,
                      _adapter,
                      onVisibilityChanged,
                    )
              : null,
        ),
      ),
    );
    _adapter = BetterPlayerControllerAdapter(_controller);
    if (kDebugMode) {
      _diagnosticClock.start();
      _controller.addEventsListener(_onDiagnosticEvent);
      _logPlayback('controller_created');
    }
    widget.onControllerCreated?.call(_adapter);
    _controller.setBetterPlayerGlobalKey(_betterPlayerKey);

    // Defer setup until mounting completes. BetterPlayer may emit a native
    // error synchronously, and its listener rebuilds the widget tree.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_setupPlayback());
    });
  }

  Future<void> _setupPlayback() async {
    _logPlayback('setup_start');
    try {
      await _controller.setupDataSource(
        betterPlayerDataSource(
          widget.stream,
          isLive: widget.isLive,
          preferredSubtitleLanguage: widget.preferredSubtitleLanguage,
          skipPreferredSubtitle: widget.preferredExternalSubtitle != null,
          preview: widget.preview,
        ),
      );
      if (!mounted) return;
      _dataSourceReady = true;
      _logPlayback('setup_ready');
      _startLiveHeartbeat();
      if (widget.muted) await _controller.setVolume(0);
      if (!widget.playing) await _controller.pause();
      _adapter.syncValue();
      widget.onPlaybackReady?.call(_adapter);
      final preferredExternal = widget.preferredExternalSubtitle;
      if (preferredExternal != null) {
        await _controller.setupSubtitleSource(subtitleSourceFor(preferredExternal));
      }
    } catch (error) {
      _logPlayback('setup_error error=${redactPlaybackLogText(error)}');
    }
  }

  @override
  void dispose() {
    _liveHeartbeatTimer?.cancel();
    _bufferingDiagnosticTimer?.cancel();
    _wakelockRefreshTimer?.cancel();
    if (!widget.preview) {
      WidgetsBinding.instance.removeObserver(this);
      _wakelock?.release();
    }
    if (kDebugMode) {
      _controller.removeEventsListener(_onDiagnosticEvent);
      _logPlayback('dispose');
    }
    _controller.dispose();
    _adapter.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _wakelock?.refresh();
  }

  @override
  Widget build(BuildContext context) =>
      BetterPlayer(key: _betterPlayerKey, controller: _controller);

  void _onDiagnosticEvent(BetterPlayerEvent event) {
    switch (event.betterPlayerEventType) {
      case BetterPlayerEventType.bufferingStart:
        _logPlayback('buffering_start ${_playbackSnapshot()}');
        _bufferingDiagnosticTimer?.cancel();
        _bufferingDiagnosticTimer = Timer.periodic(
          const Duration(seconds: 5),
          (_) => _logPlayback('buffering_wait ${_playbackSnapshot()}'),
        );
      case BetterPlayerEventType.bufferingEnd:
        _bufferingDiagnosticTimer?.cancel();
        _bufferingDiagnosticTimer = null;
        _logPlayback('buffering_end ${_playbackSnapshot()}');
      case BetterPlayerEventType.exception:
        _bufferingDiagnosticTimer?.cancel();
        _bufferingDiagnosticTimer = null;
        final error = event.parameters?['exception'];
        _logPlayback(
          'exception error=${redactPlaybackLogText(error)} '
          '${_playbackSnapshot()}',
        );
      case BetterPlayerEventType.initialized:
      case BetterPlayerEventType.play:
      case BetterPlayerEventType.pause:
      case BetterPlayerEventType.seekTo:
      case BetterPlayerEventType.finished:
        _logPlayback(
          '${event.betterPlayerEventType.name} ${_playbackSnapshot()}',
        );
      case BetterPlayerEventType.openFullscreen:
      case BetterPlayerEventType.hideFullscreen:
      case BetterPlayerEventType.setVolume:
      case BetterPlayerEventType.progress:
      case BetterPlayerEventType.controlsVisible:
      case BetterPlayerEventType.controlsHiddenStart:
      case BetterPlayerEventType.controlsHiddenEnd:
      case BetterPlayerEventType.setSpeed:
      case BetterPlayerEventType.changedSubtitles:
      case BetterPlayerEventType.changedTrack:
      case BetterPlayerEventType.changedPlayerVisibility:
      case BetterPlayerEventType.changedResolution:
      case BetterPlayerEventType.pipStart:
      case BetterPlayerEventType.pipStop:
      case BetterPlayerEventType.setupDataSource:
      case BetterPlayerEventType.bufferingUpdate:
      case BetterPlayerEventType.changedPlaylistItem:
        break;
    }
  }

  void _startLiveHeartbeat() {
    if (!kDebugMode || !widget.isLive) return;
    _liveHeartbeatTimer?.cancel();
    _liveHeartbeatTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _logPlayback('heartbeat ${_playbackSnapshot()}'),
    );
  }

  String _playbackSnapshot() {
    final value = _controller.videoPlayerController?.value;
    if (value == null) return 'state=unavailable';
    var bufferedEdge = Duration.zero;
    for (final range in value.buffered) {
      if (range.end > bufferedEdge) bufferedEdge = range.end;
    }
    final bufferedAhead = bufferedEdge > value.position
        ? bufferedEdge - value.position
        : Duration.zero;
    return 'position=${value.position.inMilliseconds}ms '
        'bufferedAhead=${bufferedAhead.inMilliseconds}ms '
        'playing=${value.isPlaying} buffering=${value.isBuffering} '
        'initialized=${value.initialized}';
  }

  void _logPlayback(String message) {
    if (!kDebugMode) return;
    final elapsed = _diagnosticClock.elapsedMilliseconds;
    final source = safePlaybackUrlForLog(widget.stream.url);
    debugPrint(
      '[LivePlayback] elapsed=${elapsed}ms live=${widget.isLive} '
      'format=${widget.stream.format.name} source=$source $message',
    );
  }
}
