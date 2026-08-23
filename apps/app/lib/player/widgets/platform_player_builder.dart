import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';

import 'media_kit_player.dart';
import 'stream_player.dart' show mobilePlayerBuilder;

/// Apple platforms play through MediaKit/libmpv; Android stays on
/// BetterPlayer/ExoPlayer.
///
/// ExoPlayer sniffs a segment's container, so Android needs no help. AVPlayer
/// does not, and providers that mislabel MPEG-TS stall on it — so iOS pays
/// for libmpv's native payload to get those streams playing.
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
}) => defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.iOS
    ? MediaKitPlayerView(
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
