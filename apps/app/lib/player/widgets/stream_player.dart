import 'package:flutter/material.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';

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
      SubtitleTrack? preferredExternalSubtitle,
      SubtitleAppearance? subtitleAppearance,
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
  SubtitleTrack? preferredExternalSubtitle,
  SubtitleAppearance? subtitleAppearance,
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
  key: key,
);
