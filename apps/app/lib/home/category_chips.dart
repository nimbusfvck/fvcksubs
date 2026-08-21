import 'package:flutter/material.dart';

import '../theme/tokens.dart';

class CategoryChips extends StatelessWidget {
  const CategoryChips({
    super.key,
    required this.categories,
    required this.selected,
    required this.onSelected,
  });

  final List<String> categories;

  final String selected;

  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.md,
      vertical: AppSpacing.xs,
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final category in categories)
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.xs),
            child: ChoiceChip(
              label: SizedBox(
                height: 28,
                child: Center(
                  child: Text(
                    _label(category),
                    style: AppTypography.titleSm.copyWith(
                      color: category == selected
                          ? AppColors.surfaceDark
                          : AppColors.onDark,
                    ),
                  ),
                ),
              ),
              selected: category == selected,
              onSelected: (_) => onSelected(category),
              showCheckmark: false,
              labelPadding: EdgeInsets.zero,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              backgroundColor: AppColors.surfaceDarkElevated,
              selectedColor: AppColors.onDark,
              side: BorderSide.none,
              shape: RoundedRectangleBorder(borderRadius: AppRadius.pill),
            ),
          ),
      ],
    ),
  );

  static String _label(String category) => category.isEmpty
      ? category
      : category[0].toUpperCase() + category.substring(1);
}
