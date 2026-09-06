// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/foundation.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

/// Inline ClearKey DRM configuration for Android Media3/ExoPlayer playback.
@immutable
class ClearKeyDrmConfiguration extends VideoDrmConfiguration {
  /// Creates an inline ClearKey configuration.
  const ClearKeyDrmConfiguration({required this.clearKeyJson});

  /// JSON key set consumed by Media3's ClearKey DRM callback.
  final String clearKeyJson;
}
