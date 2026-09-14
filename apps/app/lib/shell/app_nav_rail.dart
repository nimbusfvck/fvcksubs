import 'package:flutter/material.dart';

import '../home/category_chips.dart';
import '../theme/tokens.dart';
import 'app_destination.dart';

/// A side navigation rail with the label placed beside the icon, rather than
/// below it (the layout stock [NavigationRail] cannot produce).
class AppNavRail extends StatelessWidget {
  const AppNavRail({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    this.categories = const [],
    this.selectedCategory,
    this.onCategorySelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<String> categories;
  final String? selectedCategory;
  final ValueChanged<String>? onCategorySelected;

  static const double _width = 220;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surfaceDarkContainer,
    child: SafeArea(
      child: SizedBox(
        width: _width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: AppSpacing.md),
            for (final destination in AppDestination.values)
              if (destination != AppDestination.settings)
                _RailRow(
                  destination: destination,
                  selected: destination.index == selectedIndex,
                  onTap: () => onDestinationSelected(destination.index),
                ),
            if (categories.isNotEmpty) ...[
              Padding(
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.xs,
                ),
                child: Text('CATEGORIES', style: AppTypography.caption),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  itemCount: categories.length,
                  itemBuilder: (context, index) {
                    final category = categories[index];
                    return _CategoryRailRow(
                      category: category,
                      selected: category == selectedCategory,
                      onTap: onCategorySelected == null
                          ? null
                          : () => onCategorySelected!(category),
                    );
                  },
                ),
              ),
            ] else
              const Spacer(),
            _RailRow(
              destination: AppDestination.settings,
              selected: AppDestination.settings.index == selectedIndex,
              onTap: () => onDestinationSelected(AppDestination.settings.index),
            ),
          ],
        ),
      ),
    ),
  );
}

class _CategoryRailRow extends StatelessWidget {
  const _CategoryRailRow({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  final String category;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.onDark : AppColors.onDarkSoft;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xxs,
      ),
      child: Semantics(
        button: true,
        selected: selected,
        label: categoryLabel(category),
        child: Material(
          color: selected
              ? AppColors.brandAccent.withValues(alpha: 0.18)
              : Colors.transparent,
          borderRadius: AppRadius.md,
          child: InkWell(
            onTap: onTap,
            borderRadius: AppRadius.md,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xs,
              ),
              child: Row(
                children: [
                  if (category.toLowerCase() == 'live')
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: Center(
                        child: SizedBox(
                          width: 7,
                          height: 7,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: AppColors.liveAccent,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ),
                    )
                  else
                    Icon(categoryIcon(category), color: color, size: 18),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      categoryLabel(category),
                      style: AppTypography.bodyMd.copyWith(color: color),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RailRow extends StatelessWidget {
  const _RailRow({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final AppDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.brandAccent : AppColors.onDarkSoft;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xxs,
      ),
      child: Semantics(
        button: true,
        selected: selected,
        label: destination.label,
        child: Tooltip(
          message: destination.label,
          child: Material(
            color: selected
                ? AppColors.surfaceDarkElevated
                : Colors.transparent,
            borderRadius: AppRadius.md,
            child: InkWell(
              onTap: onTap,
              borderRadius: AppRadius.md,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                child: Row(
                  children: [
                    Icon(
                      selected ? destination.selectedIcon : destination.icon,
                      color: color,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        destination.label,
                        style: AppTypography.titleSm.copyWith(color: color),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
