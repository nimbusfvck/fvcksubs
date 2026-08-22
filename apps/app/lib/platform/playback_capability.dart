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
    PlaybackTarget.android => stream.drm?.scheme != DrmScheme.unsupported,
    PlaybackTarget.ios =>
      stream.drm == null && stream.format != StreamFormat.dash,
    // libmpv handles clear HLS/DASH on macOS. DRM schemes stay blocked until
    // a platform-specific license flow has been implemented and tested.
    PlaybackTarget.macos => stream.drm == null,
    PlaybackTarget.unsupported => false,
  };
}
