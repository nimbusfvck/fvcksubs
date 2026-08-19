import 'package:flutter/foundation.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';

enum PlaybackTarget {
  android,

  ios,

  unsupported;

  static PlaybackTarget detect() => switch (defaultTargetPlatform) {
    TargetPlatform.android => PlaybackTarget.android,
    TargetPlatform.iOS => PlaybackTarget.ios,
    _ => PlaybackTarget.unsupported,
  };

  bool canPlay(PlayableStream stream) => switch (this) {
    PlaybackTarget.android => stream.drm?.scheme != DrmScheme.unsupported,
    PlaybackTarget.ios =>
      stream.drm == null && stream.format != StreamFormat.dash,
    PlaybackTarget.unsupported => false,
  };
}
