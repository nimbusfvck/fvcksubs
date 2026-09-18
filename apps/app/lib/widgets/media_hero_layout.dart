import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../theme/breakpoints.dart';

/// Shared responsive sizing for prominent Home and Detail media artwork.
abstract final class MediaHeroLayout {
  static const double narrowBreakpoint = 600;
  static const double narrowHeightFactor = 1.4;

  /// Cinematic banner ratio for landscape artwork on wide screens.
  static const double wideAspectRatio = 2.2;
  static const double summaryBottom = 24;
  static const double homeSummaryBottom = 40;
  static const double homeIndicatorBottom = 8;
  static const double homeOverlayFadeDistance = 72;

  static bool isLargeScreen(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= AppBreakpoints.railWidth;

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
    final contentWidth = math.min(
      viewport.width,
      AppBreakpoints.maxContentWidth,
    );
    return contentWidth / wideAspectRatio;
  }
}
