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
    // iOS and macOS both play through libmpv, which handles clear HLS and
    // DASH alike. DRM schemes stay blocked on both until a platform-specific
    // license flow has been implemented and tested — libmpv has no CDM.
    PlaybackTarget.ios || PlaybackTarget.macos => stream.drm == null,
    PlaybackTarget.unsupported => false,
  };
}
