import 'package:flutter/material.dart';

import '../theme/tokens.dart';

class ArtworkPlaceholder extends StatelessWidget {
  const ArtworkPlaceholder({
    super.key,
    this.icon = Icons.image_outlined,
    this.iconSize = 36,
    this.title,
  });

  final IconData icon;
  final double iconSize;
  final String? title;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'No artwork available',
    image: true,
    child: Material(
      color: AppColors.surfaceDarkElevated,
      child: switch (title) {
        final label? => SizedBox.expand(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: AppTypography.bodySm.copyWith(color: AppColors.onDark),
                ),
              ),
            ),
          ),
        ),
        _ => ExcludeSemantics(
          child: Center(
            child: Icon(icon, size: iconSize, color: AppColors.onDarkSoft),
          ),
        ),
      },
    ),
  );
}
