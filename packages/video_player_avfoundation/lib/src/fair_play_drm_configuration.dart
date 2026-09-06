import 'package:flutter/foundation.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

/// FairPlay DRM configuration for the AVFoundation implementation.
///
/// The plugin fetches the application certificate, generates the SPC, and
/// exchanges it for a CKC at [licenseUri]. The license response must be the CKC
/// bytes directly; custom JSON or base64 wrapping is not supported.
@immutable
class FairPlayDrmConfiguration extends VideoDrmConfiguration {
  /// Creates a configuration for FairPlay playback.
  const FairPlayDrmConfiguration({
    required this.certificateUri,
    required this.licenseUri,
    this.licenseHeaders = const <String, String>{},
    this.contentId,
  });

  /// The URL of the FairPlay application certificate.
  final Uri certificateUri;

  /// The license acquisition URL of the FairPlay license server.
  final Uri licenseUri;

  /// Headers to attach to each license request.
  final Map<String, String> licenseHeaders;

  /// Optional content identifier used when generating the SPC.
  final String? contentId;
}
