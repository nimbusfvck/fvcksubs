// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// Contains plugin-class-level APIs.

import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/video_player_plugin_messages.g.dart',
    swiftOut:
        'darwin/video_player_avfoundation/Sources/video_player_avfoundation/VideoPlayerPluginMessages.g.swift',
    copyrightHeader: 'pigeons/copyright.txt',
  ),
)
/// Information passed to the platform view creation.
class PlatformVideoViewCreationParams {
  const PlatformVideoViewCreationParams({required this.playerId});

  final int playerId;
}

/// Pigeon equivalent of FairPlayDrmConfiguration.
class PlatformFairPlayDrmConfiguration {
  PlatformFairPlayDrmConfiguration({
    required this.certificateUri,
    required this.licenseUri,
    required this.licenseHeaders,
    this.contentId,
  });

  String certificateUri;
  String licenseUri;
  Map<String, String> licenseHeaders;
  String? contentId;
}

/// Pigeon equivalent of video_player_platform_interface's
/// VideoPlayerLiveOptions.
class PlatformLiveConfiguration {
  PlatformLiveConfiguration({
    required this.targetOffsetMs,
    required this.minOffsetMs,
    required this.maxOffsetMs,
    required this.minPlaybackSpeed,
    required this.maxPlaybackSpeed,
    required this.preferredForwardBufferDurationMs,
    required this.minBufferDurationMs,
    required this.maxBufferDurationMs,
    required this.bufferForPlaybackMs,
    required this.bufferForPlaybackAfterRebufferMs,
  });

  /// Desired distance behind the live edge when playback starts or catches up.
  int targetOffsetMs;
  /// Smallest allowed distance behind the live edge.
  int minOffsetMs;
  /// Largest allowed distance behind the live edge.
  int maxOffsetMs;
  /// Lowest playback speed used while correcting live latency.
  double minPlaybackSpeed;
  /// Highest playback speed used while correcting live latency.
  double maxPlaybackSpeed;
  /// Preferred AVPlayer read-ahead buffer duration.
  int preferredForwardBufferDurationMs;
  /// Minimum Android load-control buffer duration, unused on Darwin.
  int minBufferDurationMs;
  /// Maximum Android load-control buffer duration, unused on Darwin.
  int maxBufferDurationMs;
  /// Android buffer required before initial playback, unused on Darwin.
  int bufferForPlaybackMs;
  /// Android buffer required after a rebuffer, unused on Darwin.
  int bufferForPlaybackAfterRebufferMs;
}

class CreationOptions {
  CreationOptions({required this.uri, required this.httpHeaders});

  String uri;
  /// Whether the source is an unbounded live stream.
  bool? isLive;
  Map<String, String> httpHeaders;
  PlatformFairPlayDrmConfiguration? fairPlayDrm;
  /// Optional live playback tuning.
  PlatformLiveConfiguration? liveConfiguration;
}

class TexturePlayerIds {
  TexturePlayerIds({required this.playerId, required this.textureId});

  final int playerId;
  final int textureId;
}

@HostApi()
abstract class AVFoundationVideoPlayerApi {
  void initialize();
  // Creates a new player using a platform view for rendering and returns its
  // ID.
  @SwiftFunction('createPlatformViewPlayer(options:)')
  int createForPlatformView(CreationOptions params);
  // Creates a new player using a texture for rendering and returns its IDs.
  @SwiftFunction('createTexturePlayer(options:)')
  TexturePlayerIds createForTextureView(CreationOptions creationOptions);
  @SwiftFunction('setMixWithOthers(_:)')
  void setMixWithOthers(bool mixWithOthers);
  @SwiftFunction('fileURLForAsset(name:package:)')
  String? getAssetUrl(String asset, String? package);
}
