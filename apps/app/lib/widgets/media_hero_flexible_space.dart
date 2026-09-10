import 'package:flutter/material.dart';

/// Shared parallax and collapse behavior for Home and Detail hero cards.
class MediaHeroFlexibleSpace extends StatelessWidget {
  const MediaHeroFlexibleSpace({
    super.key,
    required this.expandedHeight,
    this.collapsedHeight = 0,
    required this.child,
  });

  final double expandedHeight;
  final double collapsedHeight;
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final settings = context
          .dependOnInheritedWidgetOfExactType<FlexibleSpaceBarSettings>();
      final maxExtent = settings?.maxExtent ?? expandedHeight;
      final minExtent = settings?.minExtent ?? collapsedHeight;
      final currentExtent = settings?.currentExtent ?? constraints.maxHeight;
      final maxCollapse = (maxExtent - minExtent)
          .clamp(0.0, maxExtent)
          .toDouble();
      final collapse = (maxExtent - currentExtent)
          .clamp(0.0, maxCollapse)
          .toDouble();
      return MediaHeroCollapseScope(
        collapse: collapse,
        maxCollapse: maxCollapse,
        child: child,
      );
    },
  );
}

class MediaHeroCollapseScope extends InheritedWidget {
  const MediaHeroCollapseScope({
    super.key,
    required this.collapse,
    required this.maxCollapse,
    required super.child,
  });

  final double collapse;
  final double maxCollapse;

  static double of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<MediaHeroCollapseScope>()
          ?.collapse ??
      0;

  static double maxCollapseOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<MediaHeroCollapseScope>()
          ?.maxCollapse ??
      0;

  @override
  bool updateShouldNotify(MediaHeroCollapseScope oldWidget) =>
      collapse != oldWidget.collapse || maxCollapse != oldWidget.maxCollapse;
}
