// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package io.flutter.plugins.videoplayer;

/** Native representation of the Flutter live playback configuration. */
public final class LivePlaybackOptions {
  /** Desired distance behind the live edge when playback starts or catches up. */
  public final long targetOffsetMs;
  /** Smallest allowed distance behind the live edge. */
  public final long minOffsetMs;
  /** Largest allowed distance behind the live edge. */
  public final long maxOffsetMs;
  /** Lowest playback speed used while correcting live latency. */
  public final float minPlaybackSpeed;
  /** Highest playback speed used while correcting live latency. */
  public final float maxPlaybackSpeed;
  /** Preferred AVPlayer read-ahead duration, unused by Media3. */
  public final long preferredForwardBufferDurationMs;
  /** Minimum Media3 load-control buffer duration. */
  public final long minBufferDurationMs;
  /** Maximum Media3 load-control buffer duration. */
  public final long maxBufferDurationMs;
  /** Media3 buffer required before initial playback. */
  public final long bufferForPlaybackMs;
  /** Media3 buffer required after a rebuffer. */
  public final long bufferForPlaybackAfterRebufferMs;

  /**
   * Creates a validated native live playback configuration.
   *
   * @param targetOffsetMs desired distance behind the live edge.
   * @param minOffsetMs smallest allowed distance behind the live edge.
   * @param maxOffsetMs largest allowed distance behind the live edge.
   * @param minPlaybackSpeed lowest correction playback speed.
   * @param maxPlaybackSpeed highest correction playback speed.
   * @param preferredForwardBufferDurationMs preferred AVPlayer read-ahead duration.
   * @param minBufferDurationMs minimum Media3 load-control buffer duration.
   * @param maxBufferDurationMs maximum Media3 load-control buffer duration.
   * @param bufferForPlaybackMs buffer required before initial playback.
   * @param bufferForPlaybackAfterRebufferMs buffer required after a rebuffer.
   */
  LivePlaybackOptions(
      long targetOffsetMs,
      long minOffsetMs,
      long maxOffsetMs,
      double minPlaybackSpeed,
      double maxPlaybackSpeed,
      long preferredForwardBufferDurationMs,
      long minBufferDurationMs,
      long maxBufferDurationMs,
      long bufferForPlaybackMs,
      long bufferForPlaybackAfterRebufferMs) {
    if (targetOffsetMs < 0
        || minOffsetMs < 0
        || maxOffsetMs < 0
        || minOffsetMs > targetOffsetMs
        || targetOffsetMs > maxOffsetMs
        || preferredForwardBufferDurationMs < 0
        || minBufferDurationMs < 0
        || maxBufferDurationMs < minBufferDurationMs
        || bufferForPlaybackMs < 0
        || bufferForPlaybackAfterRebufferMs < 0
        || minPlaybackSpeed <= 0
        || maxPlaybackSpeed <= 0
        || minPlaybackSpeed > maxPlaybackSpeed) {
      throw new IllegalArgumentException("Invalid live playback configuration");
    }
    this.targetOffsetMs = targetOffsetMs;
    this.minOffsetMs = minOffsetMs;
    this.maxOffsetMs = maxOffsetMs;
    this.minPlaybackSpeed = (float) minPlaybackSpeed;
    this.maxPlaybackSpeed = (float) maxPlaybackSpeed;
    this.preferredForwardBufferDurationMs = preferredForwardBufferDurationMs;
    this.minBufferDurationMs = minBufferDurationMs;
    this.maxBufferDurationMs = maxBufferDurationMs;
    this.bufferForPlaybackMs = bufferForPlaybackMs;
    this.bufferForPlaybackAfterRebufferMs = bufferForPlaybackAfterRebufferMs;
  }

  /**
   * Clamps a duration to the integer range accepted by DefaultLoadControl.
   *
   * @param value duration in milliseconds.
   * @return the duration represented as an integer.
   */
  public static int asInt(long value) {
    return (int) Math.min(value, Integer.MAX_VALUE);
  }
}
