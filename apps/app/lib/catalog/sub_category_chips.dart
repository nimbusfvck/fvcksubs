import 'package:flutter/material.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';

import '../theme/tokens.dart';

class SubCategoryChips extends StatelessWidget {
  const SubCategoryChips({
    super.key,
    required this.subCategories,
    required this.selected,
    required this.onSelected,
  });

  final List<SubCategory> subCategories;

  final String? selected;

  final ValueChanged<String?> onSelected;

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
        Padding(
          padding: const EdgeInsets.only(right: AppSpacing.xs),
          child: ChoiceChip(
            label: const Text('All'),
            selected: selected == null,
            onSelected: (_) => onSelected(null),
          ),
        ),
        for (final subCategory in subCategories)
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.xs),
            child: ChoiceChip(
              label: Text(subCategory.name),
              selected: selected == subCategory.id,
              onSelected: (_) => onSelected(subCategory.id),
            ),
          ),
      ],
    ),
  );
}
