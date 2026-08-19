import 'package:flutter/material.dart';

import 'tokens.dart';

ThemeData buildDarkTheme() {
  const scheme = ColorScheme.dark(
    primary: AppColors.brandAccent,
    onPrimary: AppColors.onDark,
    surface: AppColors.surfaceDark,
    onSurface: AppColors.onDark,
    error: AppColors.error,
  );

  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.surfaceDark,
  );

  return base.copyWith(
    textTheme: base.textTheme.copyWith(
      headlineMedium: AppTypography.displayMd,
      titleLarge: AppTypography.titleLg,
      titleMedium: AppTypography.titleMd,
      titleSmall: AppTypography.titleSm,
      bodyMedium: AppTypography.bodyMd,
      bodySmall: AppTypography.bodySm,
      labelSmall: AppTypography.caption,
    ),
    cardTheme: CardThemeData(
      color: AppColors.surfaceDarkElevated,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.lg),
    ),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: AppColors.surfaceDarkContainer,
      indicatorColor: AppColors.surfaceDarkHighest,
    ),
    navigationRailTheme: const NavigationRailThemeData(
      backgroundColor: AppColors.surfaceDarkContainer,
      selectedIconTheme: IconThemeData(color: AppColors.brandAccent),
    ),
  );
}
