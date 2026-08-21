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
    appBarTheme: const AppBarTheme(centerTitle: false),
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
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primaryAction,
        foregroundColor: AppColors.onPrimaryAction,
        disabledBackgroundColor: AppColors.surfaceDarkHighest,
        disabledForegroundColor: AppColors.onDarkSoft,
        elevation: 0,
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        textStyle: AppTypography.titleSm,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.md),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.onDark,
        disabledForegroundColor: AppColors.onDarkSoft,
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        textStyle: AppTypography.titleSm,
        side: const BorderSide(color: AppColors.outlineDark),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.md),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.onDark,
        textStyle: AppTypography.titleSm,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.md),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primaryAction,
        foregroundColor: AppColors.onPrimaryAction,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.md),
        elevation: 0,
        minimumSize: const Size(0, 44),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surfaceDarkContainer,
      hintStyle: AppTypography.bodyMd.copyWith(color: AppColors.onDarkSoft),
      labelStyle: AppTypography.bodySm.copyWith(color: AppColors.onDarkSoft),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      border: OutlineInputBorder(
        borderRadius: AppRadius.md,
        borderSide: const BorderSide(color: AppColors.outlineDark),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: AppRadius.md,
        borderSide: const BorderSide(color: AppColors.outlineDark),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: AppRadius.md,
        borderSide: const BorderSide(color: AppColors.brandAccent, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: AppRadius.md,
        borderSide: const BorderSide(color: AppColors.error),
      ),
    ),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: AppColors.surfaceDarkContainer,
      indicatorColor: AppColors.surfaceDarkElevated,
      iconTheme: WidgetStatePropertyAll(
        IconThemeData(color: AppColors.onDarkSoft),
      ),
    ),
    navigationRailTheme: const NavigationRailThemeData(
      backgroundColor: AppColors.surfaceDarkContainer,
      selectedIconTheme: IconThemeData(color: AppColors.brandAccent),
      unselectedIconTheme: IconThemeData(color: AppColors.onDarkSoft),
    ),
  );
}
