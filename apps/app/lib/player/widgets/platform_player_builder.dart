import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';

import 'video_player_vod.dart';
import 'media_kit_player.dart';
import 'stream_player.dart' show mobilePlayerBuilder;
import '../state/subtitle_preference_controller.dart';

/// Apple VOD uses the official video_player/AVFoundation backend. Live Apple
/// playback stays on MediaKit/libmpv; Android stays on BetterPlayer/ExoPlayer.
///
/// ExoPlayer and libmpv are retained for live streams because several live
/// providers mislabel MPEG-TS segments. AVFoundation is used for on-demand
/// streams where its seek and track APIs are the path we are optimizing.
@visibleForTesting
bool usesVideoPlayerVod({
  required TargetPlatform platform,
  required StreamFormat format,
  required bool isLive,
  required bool preview,
  required bool hasExternalAudio,
  required bool hasDrm,
}) =>
    (platform == TargetPlatform.macOS || platform == TargetPlatform.iOS) &&
    !isLive &&
    format != StreamFormat.dash &&
    !hasExternalAudio &&
    !hasDrm;

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
  int? preferredQualityMaxHeight,
  SubtitleTrack? preferredExternalSubtitle,
  SubtitleAppearance? subtitleAppearance,
  bool muted = false,
  bool looping = false,
  bool playing = true,
  bool preview = false,
  bool? wakelock,
  bool transparentBackground = false,
  BoxFit fit = BoxFit.contain,
  Key? key,
}) {
  if (usesVideoPlayerVod(
    platform: defaultTargetPlatform,
    format: stream.format,
    isLive: isLive,
    preview: preview,
    hasExternalAudio: stream.audioUrl?.isNotEmpty ?? false,
    hasDrm: stream.drm != null,
  )) {
    return VideoPlayerVodView(
      key: key,
      stream: stream,
      onControllerCreated: onControllerCreated,
      onPlaybackReady: onPlaybackReady,
      preferredSubtitleLanguage: preferredSubtitleLanguage,
      preferredQualityMaxHeight: preferredQualityMaxHeight,
      preferredExternalSubtitle: preferredExternalSubtitle,
      subtitleAppearance: subtitleAppearance,
      muted: muted,
      looping: looping,
      playing: playing,
      fit: fit,
    );
  }
  return defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.iOS
      ? MediaKitPlayerView(
          key: key,
          stream: stream,
          isLive: isLive,
          onControllerCreated: onControllerCreated,
          onPlaybackReady: onPlaybackReady,
          preferredSubtitleLanguage: preferredSubtitleLanguage,
          preferredQualityMaxHeight: preferredQualityMaxHeight,
          preferredExternalSubtitle: preferredExternalSubtitle,
          subtitleAppearance: subtitleAppearance,
          muted: muted,
          looping: looping,
          playing: playing,
          preview: preview,
          wakelock: wakelock,
          transparentBackground: transparentBackground,
          fit: fit,
        )
      : mobilePlayerBuilder(
          context,
          stream,
          isLive: isLive,
          onControllerCreated: onControllerCreated,
          onPlaybackReady: onPlaybackReady,
          customControlsBuilder: customControlsBuilder,
          preferredSubtitleLanguage: preferredSubtitleLanguage,
          preferredQualityMaxHeight: preferredQualityMaxHeight,
          preferredExternalSubtitle: preferredExternalSubtitle,
          subtitleAppearance: subtitleAppearance,
          muted: muted,
          looping: looping,
          playing: playing,
          preview: preview,
          wakelock: wakelock,
          transparentBackground: transparentBackground,
          fit: fit,
          key: key,
        );
}
