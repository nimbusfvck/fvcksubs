import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';

import 'media_kit_macos_player.dart';
import 'stream_player.dart' show mobilePlayerBuilder;

/// Keeps MediaKit's native payload out of the mobile plugin graph: only the
/// macOS builder instantiates it. Mobile continues through BetterPlayer.
Widget platformPlayerBuilder(
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
}) => defaultTargetPlatform == TargetPlatform.macOS
    ? MediaKitMacosPlayerView(
        key: key,
        stream: stream,
        isLive: isLive,
        onControllerCreated: onControllerCreated,
        onPlaybackReady: onPlaybackReady,
        preferredSubtitleLanguage: preferredSubtitleLanguage,
      )
    : mobilePlayerBuilder(
        context,
        stream,
        isLive: isLive,
        onControllerCreated: onControllerCreated,
        onPlaybackReady: onPlaybackReady,
        customControlsBuilder: customControlsBuilder,
        preferredSubtitleLanguage: preferredSubtitleLanguage,
        key: key,
      );
