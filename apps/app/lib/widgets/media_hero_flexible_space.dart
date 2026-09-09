import 'package:flutter/material.dart';

/// Shared parallax and collapse behavior for Home and Detail hero cards.
class MediaHeroFlexibleSpace extends StatelessWidget {
  const MediaHeroFlexibleSpace({
    super.key,
    required this.expandedHeight,
    required this.child,
  });

  final double expandedHeight;
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final collapse = (expandedHeight - constraints.maxHeight)
          .clamp(0.0, expandedHeight)
          .toDouble();
      return MediaHeroCollapseScope(collapse: collapse, child: child);
    },
  );
}

class MediaHeroCollapseScope extends InheritedWidget {
  const MediaHeroCollapseScope({
    super.key,
    required this.collapse,
    required super.child,
  });

  final double collapse;

  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MediaHeroCollapseScope>()
          ?.collapse ??
      0;

  @override
  bool updateShouldNotify(MediaHeroCollapseScope oldWidget) =>
      collapse != oldWidget.collapse;
}
