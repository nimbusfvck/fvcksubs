// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package io.flutter.plugins.videoplayer;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

public class VideoPlayerOptions {
  /** Whether audio can be mixed with other audio sources. */
  public boolean mixWithOthers;
  /** Whether the source is an unbounded live stream. */
  public boolean isLive;
  /** Optional live latency and buffering configuration. */
  @Nullable public LivePlaybackOptions liveConfiguration;

  /**
   * The duration of the back buffer in milliseconds, used to configure ExoPlayer's load control.
   */
  @Nullable public Long backBufferDurationMs;

  public VideoPlayerOptions() {}

  /** Copy constructor to ensure all options are reliably copied. */
  public VideoPlayerOptions(@NonNull VideoPlayerOptions other) {
    this.mixWithOthers = other.mixWithOthers;
    this.isLive = other.isLive;
    this.liveConfiguration = other.liveConfiguration;
    this.backBufferDurationMs = other.backBufferDurationMs;
  }
}
