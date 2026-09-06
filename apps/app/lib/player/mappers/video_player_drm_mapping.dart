import 'package:flutter/foundation.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:video_player/video_player.dart' as vp;
import 'package:video_player_android/video_player_android.dart' as android;
import 'package:video_player_avfoundation/video_player_avfoundation.dart'
    as avf;

/// Converts the app-owned DRM contract to the configuration type owned by the
/// active official video_player implementation.
vp.VideoDrmConfiguration? videoPlayerDrmConfiguration(PlayableStream stream) {
  final drm = stream.drm;
  if (drm == null) return null;

  if (defaultTargetPlatform == TargetPlatform.android &&
      drm.scheme == DrmScheme.widevine &&
      drm.licenseUrl != null) {
    return android.WidevineDrmConfiguration(
      licenseUri: Uri.parse(drm.licenseUrl!),
      licenseHeaders: stream.headers,
    );
  }

  if ((defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS) &&
      drm.scheme == DrmScheme.fairPlay &&
      drm.certificateUrl != null &&
      drm.licenseUrl != null) {
    return avf.FairPlayDrmConfiguration(
      certificateUri: Uri.parse(drm.certificateUrl!),
      licenseUri: Uri.parse(drm.licenseUrl!),
      licenseHeaders: stream.headers,
      contentId: drm.contentId,
    );
  }

  return null;
}
