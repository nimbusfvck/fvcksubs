import 'package:flutter/widgets.dart';

abstract final class AppBreakpoints {
  /// Minimum width for the side navigation rail.
  static const double railWidth = 840;

  /// A phone can be wider than [railWidth] when rotated. Keep the navigation
  /// bar on those short screens so changing orientation does not replace the
  /// active page subtree with the rail layout.
  static const double railMinShortestSide = 600;

  /// At/above this width, Home content is capped and centered instead of
  /// stretching full-bleed.
  static const double maxContentWidth = 1400;

  /// True below [railWidth] — phone-sized. Tablet, desktop, and TV windows
  /// are all "not phone" and should share the same non-phone treatment.
  static bool isPhone(BuildContext context) =>
      MediaQuery.sizeOf(context).width < railWidth;

  /// Whether a non-TV window has room for the side navigation rail.
  static bool usesNavigationRail(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return size.width >= railWidth && size.shortestSide >= railMinShortestSide;
  }
}
