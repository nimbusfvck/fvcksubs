import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_app/player/widgets/platform_player_builder.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';

void main() {
  test('video_player handles Apple VOD while MediaKit remains for live', () {
    expect(
      usesVideoPlayerVod(
        platform: TargetPlatform.macOS,
        format: StreamFormat.hls,
        isLive: false,
        preview: false,
        hasExternalAudio: false,
        hasDrm: false,
      ),
      isTrue,
    );
    expect(
      usesVideoPlayerVod(
        platform: TargetPlatform.iOS,
        format: StreamFormat.hls,
        isLive: false,
        preview: false,
        hasExternalAudio: false,
        hasDrm: false,
      ),
      isTrue,
    );
    expect(
      usesVideoPlayerVod(
        platform: TargetPlatform.macOS,
        format: StreamFormat.hls,
        isLive: true,
        preview: false,
        hasExternalAudio: false,
        hasDrm: false,
      ),
      isFalse,
    );
    expect(
      usesVideoPlayerVod(
        platform: TargetPlatform.iOS,
        format: StreamFormat.hls,
        isLive: true,
        preview: false,
        hasExternalAudio: false,
        hasDrm: false,
      ),
      isFalse,
    );
    expect(
      usesVideoPlayerVod(
        platform: TargetPlatform.macOS,
        format: StreamFormat.other,
        isLive: false,
        preview: false,
        hasExternalAudio: false,
        hasDrm: false,
      ),
      isTrue,
    );
    expect(
      usesVideoPlayerVod(
        platform: TargetPlatform.macOS,
        format: StreamFormat.hls,
        isLive: false,
        preview: true,
        hasExternalAudio: false,
        hasDrm: false,
      ),
      isTrue,
    );
    expect(
      usesVideoPlayerVod(
        platform: TargetPlatform.macOS,
        format: StreamFormat.dash,
        isLive: false,
        preview: false,
        hasExternalAudio: false,
        hasDrm: false,
      ),
      isFalse,
    );
    expect(
      usesVideoPlayerVod(
        platform: TargetPlatform.macOS,
        format: StreamFormat.hls,
        isLive: false,
        preview: false,
        hasExternalAudio: true,
        hasDrm: false,
      ),
      isFalse,
    );
    expect(
      usesVideoPlayerVod(
        platform: TargetPlatform.macOS,
        format: StreamFormat.hls,
        isLive: false,
        preview: false,
        hasExternalAudio: false,
        hasDrm: true,
      ),
      isFalse,
    );
  });
}
