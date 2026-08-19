import 'package:flutter/material.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';

import '../theme/tokens.dart';

class PluginSelector extends StatelessWidget {
  const PluginSelector({
    super.key,
    required this.plugins,
    required this.selectedId,
    required this.onSelected,
  });

  final List<Manifest> plugins;

  final String selectedId;

  final ValueChanged<String> onSelected;

  Manifest get _selected => plugins.firstWhere(
    (p) => p.id == selectedId,
    orElse: () => plugins.first,
  );

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    initialValue: _selected.id,
    onSelected: onSelected,
    child: Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.surfaceDarkContainer,
        borderRadius: AppRadius.pill,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _selected.name,
            style: AppTypography.bodySm.copyWith(color: AppColors.onDark),
          ),
          const SizedBox(width: 4),
          const Icon(
            Icons.arrow_drop_down,
            color: AppColors.onDarkSoft,
            size: 18,
          ),
        ],
      ),
    ),
    itemBuilder: (context) => [
      for (final plugin in plugins)
        PopupMenuItem(value: plugin.id, child: Text(plugin.name)),
    ],
  );
}
