import 'dart:async';

import 'package:better_player_plus/better_player_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';

import 'stream_player_mapping.dart';

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
  Key? key,
}) => BetterPlayerView(
  key: key,
  stream: stream,
  isLive: isLive,
  onControllerCreated: onControllerCreated,
  onPlaybackReady: onPlaybackReady,
  customControlsBuilder: customControlsBuilder,
  preferredSubtitleLanguage: preferredSubtitleLanguage,
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
    this.aspectRatio,
    this.looping = false,
    this.muted = false,
    this.fit = BoxFit.contain,
    this.playing = true,
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

  @override
  State<BetterPlayerView> createState() => _BetterPlayerViewState();
}

class _BetterPlayerViewState extends State<BetterPlayerView> {
  late final BetterPlayerController _controller;
  final GlobalKey _betterPlayerKey = GlobalKey();
  late final BetterPlayerSubtitlesSource? _preferredSubtitle;
  bool _waitingForPreferredSubtitle = false;
  bool _dataSourceReady = false;

  @override
  void didUpdateWidget(covariant BetterPlayerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playing == widget.playing ||
        !_dataSourceReady ||
        _waitingForPreferredSubtitle) {
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
    _preferredSubtitle = widget.isLive
        ? null
        : preferredSubtitleSource(
            widget.stream.subtitles,
            widget.preferredSubtitleLanguage,
          );
    _waitingForPreferredSubtitle = _preferredSubtitle != null;
    _controller = BetterPlayerController(
      BetterPlayerConfiguration(
        allowedScreenSleep: false,
        aspectRatio: widget.aspectRatio ?? 16 / 9,
        autoPlay: widget.playing && !_waitingForPreferredSubtitle,
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
                      controller,
                      onVisibilityChanged,
                    )
              : null,
        ),
      ),
    );
    widget.onControllerCreated?.call(_controller);
    _controller.setBetterPlayerGlobalKey(_betterPlayerKey);

    // Defer setup until mounting completes. BetterPlayer may emit a native
    // error synchronously, and its listener rebuilds the widget tree.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_setupPlayback());
    });
  }

  Future<void> _setupPlayback() async {
    try {
      await _controller.setupDataSource(
        betterPlayerDataSource(
          widget.stream,
          isLive: widget.isLive,
          preferredSubtitleLanguage: widget.preferredSubtitleLanguage,
        ),
      );
      if (!mounted) return;
      _dataSourceReady = true;
      if (widget.muted) await _controller.setVolume(0);
      widget.onPlaybackReady?.call(_controller);
      final preferredSubtitle = _preferredSubtitle;
      if (preferredSubtitle != null) {
        await _controller.setupSubtitleSource(preferredSubtitle);
      }
    } catch (_) {
      // A broken subtitle must not prevent playback of an otherwise valid VOD.
    } finally {
      if (mounted && _waitingForPreferredSubtitle) {
        setState(() => _waitingForPreferredSubtitle = false);
        if (widget.playing) unawaited(_controller.play());
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      BetterPlayer(key: _betterPlayerKey, controller: _controller);
}
