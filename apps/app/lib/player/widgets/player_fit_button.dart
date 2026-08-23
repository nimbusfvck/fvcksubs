import 'package:flutter/material.dart';

import '../models/app_player_controller.dart';

class PlayerFitButton extends StatelessWidget {
  const PlayerFitButton({
    super.key,
    required this.mode,
    required this.onToggle,
  });

  final PlayerFitMode mode;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) => IconButton(
    icon: Icon(
      mode == PlayerFitMode.contain
          ? Icons.fit_screen_rounded
          : Icons.aspect_ratio_rounded,
    ),
    color: Colors.white,
    iconSize: 24,
    tooltip: mode.toggled.label,
    onPressed: onToggle,
  );
}
