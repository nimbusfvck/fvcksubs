import 'package:flutter/foundation.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';

enum PlaybackTarget {
  android,

  ios,

  macos,

  unsupported;

  static PlaybackTarget detect() => switch (defaultTargetPlatform) {
    TargetPlatform.android => PlaybackTarget.android,
    TargetPlatform.iOS => PlaybackTarget.ios,
    TargetPlatform.macOS => PlaybackTarget.macos,
    _ => PlaybackTarget.unsupported,
  };

  bool canPlay(PlayableStream stream) => switch (this) {
    // The temporary unified video_player route has no tested DRM license
    // flow on any supported platform.
    PlaybackTarget.android ||
    PlaybackTarget.ios ||
    PlaybackTarget.macos => stream.drm == null,
    PlaybackTarget.unsupported => false,
  };
}
