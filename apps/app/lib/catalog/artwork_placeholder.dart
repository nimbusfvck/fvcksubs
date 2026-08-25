import 'package:flutter/material.dart';

import '../theme/tokens.dart';

class ArtworkPlaceholder extends StatelessWidget {
  const ArtworkPlaceholder({
    super.key,
    this.icon = Icons.image_outlined,
    this.iconSize = 36,
  });

  final IconData icon;
  final double iconSize;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'No artwork available',
    image: true,
    child: ExcludeSemantics(
      child: ColoredBox(
        color: AppColors.surfaceDarkElevated,
        child: Center(
          child: Icon(icon, size: iconSize, color: AppColors.onDarkSoft),
        ),
      ),
    ),
  );
}
