import 'package:flutter/material.dart';

import '../theme/tokens.dart';

class CategoryChips extends StatelessWidget {
  const CategoryChips({
    super.key,
    required this.categories,
    required this.selected,
    required this.onSelected,
    this.backgroundColor = AppColors.surfaceDarkElevated,
    this.selectedColor = AppColors.onDark,
  });

  final List<String> categories;

  final String selected;

  final ValueChanged<String> onSelected;

  final Color backgroundColor;

  final Color selectedColor;

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
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => onSelected(category),
                borderRadius: AppRadius.pill,
                child: Ink(
                  decoration: BoxDecoration(
                    color: category == selected
                        ? selectedColor
                        : backgroundColor,
                    borderRadius: AppRadius.pill,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                    ),
                    child: SizedBox(
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
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );

  static String _label(String category) => category.isEmpty
      ? category
      : category[0].toUpperCase() + category.substring(1);
}
