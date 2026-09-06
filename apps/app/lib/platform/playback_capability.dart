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
    PlaybackTarget.android =>
      stream.drm == null ||
          (stream.drm!.scheme == DrmScheme.widevine &&
              stream.drm!.licenseUrl?.isNotEmpty == true),
    PlaybackTarget.ios || PlaybackTarget.macos =>
      stream.drm == null ||
          (stream.drm!.scheme == DrmScheme.fairPlay &&
              stream.drm!.licenseUrl?.isNotEmpty == true &&
              stream.drm!.certificateUrl?.isNotEmpty == true),
    PlaybackTarget.unsupported => false,
  };
}
