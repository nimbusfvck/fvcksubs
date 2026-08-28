import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'app_destination.dart';

/// A side navigation rail with the label placed beside the icon, rather than
/// below it (the layout stock [NavigationRail] cannot produce).
class AppNavRail extends StatelessWidget {
  const AppNavRail({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

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
              _RailRow(
                destination: destination,
                selected: destination.index == selectedIndex,
                onTap: () => onDestinationSelected(destination.index),
              ),
          ],
        ),
      ),
    ),
  );
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
            color: selected ? AppColors.surfaceDarkElevated : Colors.transparent,
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
