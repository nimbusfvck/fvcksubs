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
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (category.toLowerCase() == 'live') ...[
                              const _LiveIndicator(),
                              const SizedBox(width: AppSpacing.xs),
                            ] else ...[
                              Icon(
                                categoryIcon(category),
                                size: 16,
                                color: category == selected
                                    ? AppColors.surfaceDark
                                    : AppColors.onDark,
                              ),
                              const SizedBox(width: AppSpacing.xs),
                            ],
                            Text(
                              categoryLabel(category),
                              style: AppTypography.titleSm.copyWith(
                                color: category == selected
                                    ? AppColors.surfaceDark
                                    : AppColors.onDark,
                              ),
                            ),
                          ],
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
}

String categoryLabel(String category) {
  if (category.toLowerCase() == 'tv') return 'Shows';
  if (category.toLowerCase() == 'movie') return 'Movies';
  if (category.toLowerCase() == 'sport') return 'Sports';
  return category.isEmpty
      ? category
      : category[0].toUpperCase() + category.substring(1);
}

IconData categoryIcon(String category) {
  return switch (category.toLowerCase()) {
    'live' => Icons.live_tv_outlined,
    'movie' => Icons.movie_outlined,
    'tv' => Icons.tv_outlined,
    'anime' => Icons.animation_outlined,
    'sport' || 'sports' => Icons.sports_soccer_outlined,
    _ => Icons.category_outlined,
  };
}

class _LiveIndicator extends StatefulWidget {
  const _LiveIndicator();

  @override
  State<_LiveIndicator> createState() => _LiveIndicatorState();
}

class _LiveIndicatorState extends State<_LiveIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  var _animationsDisabled = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animationsDisabled = MediaQuery.disableAnimationsOf(context);
    if (_animationsDisabled == animationsDisabled) return;
    _animationsDisabled = animationsDisabled;
    if (_animationsDisabled) {
      _controller.stop(canceled: false);
    } else {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      key: const Key('live-category-indicator'),
      width: 10,
      height: 10,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final progress = _animationsDisabled ? 0.0 : _controller.value;
          return Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 7 + (progress * 3),
                height: 7 + (progress * 3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.liveAccent.withValues(
                    alpha: 0.24 * (1 - progress),
                  ),
                ),
              ),
              child!,
            ],
          );
        },
        child: const SizedBox(
          width: 6,
          height: 6,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.liveAccent,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    ),
  );
}
