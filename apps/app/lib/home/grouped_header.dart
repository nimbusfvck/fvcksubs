import 'package:flutter/material.dart';

import '../theme/tokens.dart';

class GroupedHeader extends StatelessWidget {
  const GroupedHeader({
    super.key,
    required this.title,
    required this.options,
    required this.selectedIndex,
    required this.onSelected,
    this.onSeeMore,
  });

  final String title;
  final List<String> options;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final VoidCallback? onSeeMore;

  @override
  Widget build(BuildContext context) {
    final selectedLabel = options[selectedIndex];
    final titleStyle = AppTypography.titleMd.copyWith(color: AppColors.onDark);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.xs,
      ),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: titleStyle,
                  ),
                ),
                Text(' on ', style: titleStyle),
                PopupMenuButton<int>(
                  tooltip: 'Change service',
                  padding: EdgeInsets.zero,
                  onSelected: onSelected,
                  itemBuilder: (context) => [
                    for (final (index, option) in options.indexed)
                      PopupMenuItem<int>(
                        value: index,
                        child: Row(
                          children: [
                            Expanded(child: Text(option)),
                            if (index == selectedIndex)
                              const Icon(Icons.check, size: 18),
                          ],
                        ),
                      ),
                  ],
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xxs,
                      vertical: AppSpacing.xs,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          selectedLabel,
                          style: AppTypography.titleMd.copyWith(
                            color: AppColors.brandAccent,
                          ),
                        ),
                        const Icon(
                          Icons.keyboard_arrow_down,
                          color: AppColors.brandAccent,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (onSeeMore != null)
            TextButton(
              onPressed: onSeeMore,
              child: Text(
                'See more',
                style: AppTypography.titleSm.copyWith(
                  color: AppColors.brandAccent,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
