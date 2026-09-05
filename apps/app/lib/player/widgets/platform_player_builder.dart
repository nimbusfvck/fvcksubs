import 'package:flutter/material.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';

import 'video_player_vod.dart';
import '../state/subtitle_preference_controller.dart';

/// Routes every supported playback source through the official video_player
/// backend while investigating live buffering across native player engines.
@visibleForTesting
bool usesVideoPlayer() => true;

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
  assert(usesVideoPlayer());
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
    preview: preview,
    wakelock: wakelock,
  );
}
