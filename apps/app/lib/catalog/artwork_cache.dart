import 'package:flutter/material.dart';

/// Converts a rendered logical dimension into a bounded image decode size.
///
/// Keeping this at the display size avoids decoding a poster or logo at its
/// upstream resolution when the widget only occupies a small part of the
/// screen. A null result lets callers safely handle unconstrained layouts.
int? artworkCacheDimension(BuildContext context, double logicalPixels) {
  if (!logicalPixels.isFinite || logicalPixels <= 0) return null;
  final physicalPixels =
      (logicalPixels * MediaQuery.devicePixelRatioOf(context)).round();
  return physicalPixels > 0 ? physicalPixels : null;
}
