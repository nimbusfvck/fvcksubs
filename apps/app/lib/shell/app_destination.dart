import 'package:flutter/material.dart';

enum AppDestination {
  home('Home', Icons.home_outlined, Icons.home),

  library('Library', Icons.bookmark_border, Icons.bookmark),

  shorts('Shorts', Icons.play_circle_outline, Icons.play_circle),

  settings('Settings', Icons.settings_outlined, Icons.settings);

  const AppDestination(this.label, this.icon, this.selectedIcon);

  final String label;

  final IconData icon;

  final IconData selectedIcon;
}
