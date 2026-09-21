import 'package:flutter/material.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';

import '../models/playback_start_position.dart';
import '../state/subtitle_preference_controller.dart';
import 'platform_player_builder.dart';

/// Builds the app-owned player while keeping native playback injectable in
/// tests and alternate shells.
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
      int? preferredQualityMaxHeight,
      PlaybackStartPosition? startPosition,
      SubtitleTrack? preferredExternalSubtitle,
      SubtitleAppearance? subtitleAppearance,
      bool muted,
      bool playing,
      bool? wakelock,
      BoxFit fit,
      Key? key,
    });

/// Creates the single native player used by the app's full-playback route.
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
  int? preferredQualityMaxHeight,
  PlaybackStartPosition? startPosition,
  SubtitleTrack? preferredExternalSubtitle,
  SubtitleAppearance? subtitleAppearance,
  bool muted = false,
  bool playing = true,
  bool? wakelock,
  BoxFit fit = BoxFit.contain,
  Key? key,
}) => platformPlayerBuilder(
  context,
  stream,
  isLive: isLive,
  onControllerCreated: onControllerCreated,
  onPlaybackReady: onPlaybackReady,
  customControlsBuilder: customControlsBuilder,
  preferredExternalSubtitle: preferredExternalSubtitle,
  subtitleAppearance: subtitleAppearance,
  preferredSubtitleLanguage: preferredSubtitleLanguage,
  preferredQualityMaxHeight: preferredQualityMaxHeight,
  startPosition: startPosition,
  key: key,
  muted: muted,
  playing: playing,
  wakelock: wakelock,
  fit: fit,
);
