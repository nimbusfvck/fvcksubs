import 'package:flutter/widgets.dart';

abstract final class AppBreakpoints {
  /// Below this width: bottom NavigationBar. At/above it: side rail.
  static const double railWidth = 840;

  /// At/above this width, Home content is capped and centered instead of
  /// stretching full-bleed.
  static const double maxContentWidth = 1400;

  /// True below [railWidth] — phone-sized. Tablet, desktop, and TV windows
  /// are all "not phone" and should share the same non-phone treatment.
  static bool isPhone(BuildContext context) =>
      MediaQuery.sizeOf(context).width < railWidth;
}
