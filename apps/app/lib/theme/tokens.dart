import 'package:flutter/material.dart';

abstract final class AppColors {
  static const Color primary = Color(0xFF111111);
  static const Color primaryActive = Color(0xFF242424);
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color primaryAction = Color(0xFFFFFFFF);
  static const Color onPrimaryAction = Color(0xFF111111);
  static const Color brandAccent = Color(0xFF2563EB);

  static const Color surfaceDark = Color(0xFF101010);
  static const Color surfaceDarkElevated = Color(0xFF1A1A1A);
  static const Color surfaceDarkContainer = Color(0xFF151515);
  static const Color surfaceDarkHighest = Color(0xFF2A2A2A);

  static const Color onDark = Color(0xFFFFFFFF);
  static const Color onDarkSoft = Color(0xFFA1A1AA);

  // Decorative separators may stay subtle. Interactive boundaries use
  // outlineDark so controls remain distinguishable from dark surfaces.
  static const Color hairlineDark = Color(0xFF3A3A3A);
  static const Color outlineDark = Color(0xFF737373);

  static const Color liveAccent = Color(0xFFF87171);
  static const Color ratingAccent = Color(0xFFFBBF24);
  static const Color success = Color(0xFF10B981);
  static const Color error = Color(0xFFF87171);
}

abstract final class AppSpacing {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
}

abstract final class AppRadius {
  static const double smValue = 6;
  static const double mdValue = 8;
  static const double lgValue = 12;
  static const double xlValue = 16;

  static final BorderRadius sm = BorderRadius.circular(smValue);
  static final BorderRadius md = BorderRadius.circular(mdValue);
  static final BorderRadius lg = BorderRadius.circular(lgValue);
  static final BorderRadius xl = BorderRadius.circular(xlValue);
  static final BorderRadius pill = BorderRadius.circular(9999);
}

abstract final class AppTypography {
  static const String _family = 'Inter';

  static TextStyle _inter({
    required double fontSize,
    required FontWeight fontWeight,
    double? letterSpacing,
    required double height,
  }) => TextStyle(
    fontFamily: _family,
    fontSize: fontSize,
    fontWeight: fontWeight,
    letterSpacing: letterSpacing,
    height: height,
    fontVariations: [FontVariation('wght', fontWeight.value.toDouble())],
  );

  static TextStyle get displayMd => _inter(
    fontSize: 28,
    fontWeight: FontWeight.w600,
    letterSpacing: -1,
    height: 1.15,
  );

  static TextStyle get displaySm => _inter(
    fontSize: 22,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.5,
    height: 1.2,
  );

  static TextStyle get titleLg =>
      _inter(fontSize: 18, fontWeight: FontWeight.w600, height: 1.4);

  static TextStyle get titleMd =>
      _inter(fontSize: 16, fontWeight: FontWeight.w600, height: 1.4);

  static TextStyle get titleSm =>
      _inter(fontSize: 14, fontWeight: FontWeight.w600, height: 1.4);

  static TextStyle get bodyMd =>
      _inter(fontSize: 14, fontWeight: FontWeight.w400, height: 1.5);

  static TextStyle get bodySm =>
      _inter(fontSize: 12, fontWeight: FontWeight.w400, height: 1.5);

  static TextStyle get caption =>
      _inter(fontSize: 11, fontWeight: FontWeight.w500, height: 1.4);

  static TextStyle get score =>
      _inter(fontSize: 24, fontWeight: FontWeight.w700, height: 1.2);

  static TextStyle get liveBadge =>
      _inter(fontSize: 10, fontWeight: FontWeight.w700, height: 1);
}
