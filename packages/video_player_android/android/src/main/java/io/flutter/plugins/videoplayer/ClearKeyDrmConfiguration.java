// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package io.flutter.plugins.videoplayer;

import androidx.annotation.NonNull;

/** The inline ClearKey DRM information needed by Media3. */
public final class ClearKeyDrmConfiguration {
  /** The JSON key set consumed by Media3's local DRM callback. */
  @NonNull public final String clearKeyJson;

  public ClearKeyDrmConfiguration(@NonNull String clearKeyJson) {
    this.clearKeyJson = clearKeyJson;
  }
}
