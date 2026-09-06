// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

void main() {
  test('VideoPlayerOptions allowBackgroundPlayback defaults to false', () {
    final options = VideoPlayerOptions();
    expect(options.allowBackgroundPlayback, false);
  });
  test('VideoPlayerOptions mixWithOthers defaults to false', () {
    final options = VideoPlayerOptions();
    expect(options.mixWithOthers, false);
  });
  test(
    'VideoPlayerOptions preventsDisplaySleepDuringVideoPlayback defaults to true',
    () {
      final options = VideoPlayerOptions();
      expect(options.preventsDisplaySleepDuringVideoPlayback, true);
    },
  );
  test('VideoPlayerOptions backBufferDurationMs defaults to null', () {
    final options = VideoPlayerOptions();
    expect(options.backBufferDurationMs, null);
  });
  test('VideoPlayerOptions backBufferDurationMs stores configured value', () {
    final options = VideoPlayerOptions(backBufferDurationMs: 20000);
    expect(options.backBufferDurationMs, 20000);
  });

  test('VideoPlayerLiveOptions uses conservative native defaults', () {
    const options = VideoPlayerLiveOptions();

    expect(options.targetOffsetMs, 5000);
    expect(options.minOffsetMs, 3000);
    expect(options.maxOffsetMs, 10000);
    expect(options.minPlaybackSpeed, 0.98);
    expect(options.maxPlaybackSpeed, 1.02);
    expect(options.preferredForwardBufferDurationMs, 5000);
    expect(options.minBufferDurationMs, 5000);
    expect(options.maxBufferDurationMs, 15000);
    expect(options.bufferForPlaybackMs, 1500);
    expect(options.bufferForPlaybackAfterRebufferMs, 2500);
  });

  test('VideoPlayerLiveOptions accepts partial overrides', () {
    const options = VideoPlayerLiveOptions(targetOffsetMs: 7000);

    expect(options.targetOffsetMs, 7000);
    expect(options.minOffsetMs, 3000);
    expect(options.maxOffsetMs, 10000);
  });
}
