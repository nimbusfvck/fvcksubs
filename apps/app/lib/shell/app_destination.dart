import 'package:flutter/material.dart';

enum AppDestination {
  home('Home', Icons.home_outlined, Icons.home),

  library('Library', Icons.bookmark_border, Icons.bookmark),

  addons('Addons', Icons.extension_outlined, Icons.extension);

  const AppDestination(this.label, this.icon, this.selectedIcon);

  final String label;

  final IconData icon;

  final IconData selectedIcon;
}
