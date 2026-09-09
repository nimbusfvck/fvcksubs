import 'package:flutter/material.dart';

class PlayerOrientationButton extends StatelessWidget {
  const PlayerOrientationButton({
    super.key,
    required this.landscapeLocked,
    required this.onToggle,
  });

  final bool landscapeLocked;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) => IconButton(
    icon: Icon(
      landscapeLocked
          ? Icons.screen_lock_landscape_rounded
          : Icons.screen_rotation_alt_rounded,
    ),
    color: Colors.white,
    iconSize: 24,
    tooltip: landscapeLocked ? 'Use device orientation' : 'Landscape player',
    onPressed: onToggle,
  );
}
