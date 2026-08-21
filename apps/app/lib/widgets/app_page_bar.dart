import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// The standard top bar for primary application pages.
class AppPageBar extends StatelessWidget implements PreferredSizeWidget {
  const AppPageBar({
    super.key,
    required this.title,
    this.actions,
    this.leading,
  });

  final String title;
  final List<Widget>? actions;
  final Widget? leading;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) => AppBar(
    backgroundColor: AppColors.surfaceDark,
    foregroundColor: AppColors.onDark,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    scrolledUnderElevation: 0,
    centerTitle: false,
    titleSpacing: AppSpacing.md,
    leading: leading,
    title: Text(
      title,
      style: AppTypography.titleLg.copyWith(color: AppColors.onDark),
    ),
    actions: actions,
  );
}
