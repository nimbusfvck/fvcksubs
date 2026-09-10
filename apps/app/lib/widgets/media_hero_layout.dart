import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Shared responsive sizing for prominent Home and Detail media artwork.
abstract final class MediaHeroLayout {
  static const double narrowBreakpoint = 600;
  static const double narrowHeightFactor = 1.4;
  static const double wideMinHeight = 460;
  static const double wideMaxHeight = 520;
  static const double wideViewportHeightFactor = 0.57;
  static const double summaryBottom = 24;
  static const double homeSummaryBottom = 40;
  static const double homeIndicatorBottom = 8;
  static const double homeOverlayFadeDistance = 72;

  static double homeOverlayOpacity(double collapse, {double? maxCollapse}) {
    final fadeStart = maxCollapse == null
        ? 0.0
        : math.max(0, maxCollapse - homeOverlayFadeDistance).toDouble();
    return (1 - (collapse - fadeStart) / homeOverlayFadeDistance)
        .clamp(0.0, 1.0)
        .toDouble();
  }

  static double heightForViewport(Size viewport) {
    if (viewport.width <= narrowBreakpoint) {
      return viewport.width * narrowHeightFactor;
    }
    return math
        .min(
          wideMaxHeight,
          math.max(wideMinHeight, viewport.height * wideViewportHeightFactor),
        )
        .toDouble();
  }
}
