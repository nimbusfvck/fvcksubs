import 'package:flutter/material.dart';

/// Converts a rendered logical dimension into a bounded image decode size.
///
/// A small overscan keeps posters sharp during Retina scaling, hero
/// transitions, and desktop window resizing without decoding them at their
/// upstream resolution. A null result lets callers safely handle
/// unconstrained layouts.
int? artworkCacheDimension(BuildContext context, double logicalPixels) {
  if (!logicalPixels.isFinite || logicalPixels <= 0) return null;
  final physicalPixels =
      (logicalPixels * MediaQuery.devicePixelRatioOf(context) * 1.5).round();
  return physicalPixels > 0 ? physicalPixels : null;
}
