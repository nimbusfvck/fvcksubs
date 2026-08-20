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
  customControlsBuilder: customControlsBuilder,
  preferredSubtitleLanguage: preferredSubtitleLanguage,
);

class BetterPlayerView extends StatefulWidget {
  const BetterPlayerView({
    super.key,
    required this.stream,
    required this.isLive,
    this.onControllerCreated,
    this.customControlsBuilder,
    this.preferredSubtitleLanguage,
  });

  final PlayableStream stream;

  final bool isLive;

  final void Function(Object? controller)? onControllerCreated;

  final Widget Function(
    BuildContext context,
    Object? controller,
    void Function(bool visibility) onVisibilityChanged,
  )?
  customControlsBuilder;

  final String? preferredSubtitleLanguage;

  @override
  State<BetterPlayerView> createState() => _BetterPlayerViewState();
}

class _BetterPlayerViewState extends State<BetterPlayerView> {
  late final BetterPlayerController _controller;
  final GlobalKey _betterPlayerKey = GlobalKey();
  late final BetterPlayerSubtitlesSource? _preferredSubtitle;
  bool _waitingForPreferredSubtitle = false;

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
        aspectRatio: 16 / 9,
        autoPlay: !_waitingForPreferredSubtitle,
        fit: BoxFit.contain,
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
      final preferredSubtitle = _preferredSubtitle;
      if (preferredSubtitle != null) {
        await _controller.setupSubtitleSource(preferredSubtitle);
      }
    } catch (_) {
      // A broken subtitle must not prevent playback of an otherwise valid VOD.
    } finally {
      if (mounted && _waitingForPreferredSubtitle) {
        setState(() => _waitingForPreferredSubtitle = false);
        unawaited(_controller.play());
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      BetterPlayer(key: _betterPlayerKey, controller: _controller),
      if (_waitingForPreferredSubtitle)
        const ColoredBox(
          color: Colors.black54,
          child: Center(child: CircularProgressIndicator()),
        ),
    ],
  );
}
