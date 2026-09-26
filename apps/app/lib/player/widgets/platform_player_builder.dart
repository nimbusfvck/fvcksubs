import 'package:flutter/material.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:video_player/video_player.dart' as vp;

import '../models/playback_start_position.dart';
import 'video_player_view.dart';
import '../state/subtitle_preference_controller.dart';

/// Routes every supported playback source through the app's native player.
@visibleForTesting
bool usesVideoPlayer() => true;

Widget platformPlayerBuilder(
  BuildContext context,
  PlayableStream stream, {
  required bool isLive,
  vp.VideoPlayerLiveOptions? liveOptions,
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
  PlaybackStartPosition? startPosition,
  SubtitleTrack? preferredExternalSubtitle,
  SubtitleAppearance? subtitleAppearance,
  bool muted = false,
  bool mixWithOthers = false,
  bool looping = false,
  bool playing = true,
  bool preview = false,
  bool? wakelock,
  bool transparentBackground = false,
  BoxFit fit = BoxFit.contain,
  Key? key,
}) {
  assert(usesVideoPlayer());
  return VideoPlayerView(
    key: key,
    stream: stream,
    isLive: isLive,
    liveOptions: liveOptions,
    onControllerCreated: onControllerCreated,
    onPlaybackReady: onPlaybackReady,
    preferredSubtitleLanguage: preferredSubtitleLanguage,
    preferredQualityMaxHeight: preferredQualityMaxHeight,
    startPosition: startPosition,
    preferredExternalSubtitle: preferredExternalSubtitle,
    subtitleAppearance: subtitleAppearance,
    muted: muted,
    mixWithOthers: mixWithOthers,
    looping: looping,
    playing: playing,
    fit: fit,
    preview: preview,
    wakelock: wakelock,
  );
}
