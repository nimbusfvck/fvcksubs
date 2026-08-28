import 'package:flutter/material.dart';

import '../theme/breakpoints.dart';

/// Caps [child] to [maxWidth] and centers it horizontally. A no-op once the
/// available width is already at or below [maxWidth].
class CenteredContent extends StatelessWidget {
  const CenteredContent({
    super.key,
    required this.child,
    this.maxWidth = AppBreakpoints.maxContentWidth,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: child,
    ),
  );
}
