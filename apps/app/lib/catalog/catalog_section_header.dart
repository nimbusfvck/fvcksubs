import 'package:flutter/material.dart';

import '../theme/tokens.dart';

class CatalogSectionHeader extends StatelessWidget {
  const CatalogSectionHeader({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.md,
      AppSpacing.md,
      AppSpacing.md,
      AppSpacing.sm,
    ),
    child: Text(
      label,
      style: AppTypography.titleSm.copyWith(color: AppColors.onDarkSoft),
    ),
  );
}
