import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../theme/breakpoints.dart';

/// Shared responsive sizing for prominent Home and Detail media artwork.
abstract final class MediaHeroLayout {
  static const double narrowBreakpoint = 600;
  static const double narrowHeightFactor = 1.4;

  /// Landscape artwork ratio used by the large-screen hero frame.
  ///
  /// Artwork references currently carry only a URL, not intrinsic dimensions,
  /// so a stable 16:9 frame keeps Home and Detail aligned as items change.
  static const double wideAspectRatio = 16 / 9;
  static const double summaryBottom = 24;
  static const double homeSummaryBottom = 40;
  static const double homeIndicatorBottom = 8;
  static const double homeOverlayFadeDistance = 72;

  static bool isLargeScreen(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= AppBreakpoints.railWidth;

  static double widthForViewport(Size viewport) =>
      viewport.width <= narrowBreakpoint
      ? viewport.width
      : math.min(viewport.width, AppBreakpoints.maxContentWidth);

  /// Aligns a hero boundary to a physical device pixel.
  static double snapToDevicePixel(BuildContext context, double value) {
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    return (value * devicePixelRatio).round() / devicePixelRatio;
  }

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
    return widthForViewport(viewport) / wideAspectRatio;
  }
}
