import 'package:flutter/material.dart';

import '../theme/tokens.dart';

class ArtworkPlaceholder extends StatelessWidget {
  const ArtworkPlaceholder({
    super.key,
    this.icon = Icons.image_outlined,
    this.iconSize = 36,
    this.title,
    this.titleAlignment = Alignment.center,
    this.titleTextAlign = TextAlign.center,
  });

  final IconData icon;
  final double iconSize;
  final String? title;
  final Alignment titleAlignment;
  final TextAlign titleTextAlign;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'No artwork available',
    image: true,
    child: Material(
      color: AppColors.surfaceDarkElevated,
      child: switch (title) {
        final label? => SizedBox.expand(
          child: Align(
            alignment: titleAlignment,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  textAlign: titleTextAlign,
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
