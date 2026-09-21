import 'package:flutter/material.dart';

import '../theme/tokens.dart';

class ShimmerPlaceholder extends StatefulWidget {
  const ShimmerPlaceholder({
    super.key,
    this.width,
    this.height = 120,
    this.borderRadius = BorderRadius.zero,
  });

  final double? width;
  final double? height;
  final BorderRadiusGeometry borderRadius;

  @override
  State<ShimmerPlaceholder> createState() => _ShimmerPlaceholderState();
}

class _ShimmerPlaceholderState extends State<ShimmerPlaceholder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, _) => ShaderMask(
      blendMode: BlendMode.srcATop,
      shaderCallback: (bounds) {
        // Move through one complete repeated gradient period. The first and
        // last frames are identical, so AnimationController.repeat() does not
        // produce a visible jump when it wraps back to zero.
        final phase = _controller.value;
        return LinearGradient(
          begin: Alignment(-3 + (phase * 2), 0),
          end: Alignment(-1 + (phase * 2), 0),
          colors: const [
            AppColors.surfaceDarkContainer,
            AppColors.surfaceDarkHighest,
            AppColors.surfaceDarkContainer,
          ],
          tileMode: TileMode.repeated,
        ).createShader(bounds);
      },
      child: ClipRRect(
        borderRadius: widget.borderRadius,
        child: ColoredBox(
          color: AppColors.surfaceDarkContainer,
          child: SizedBox(width: widget.width, height: widget.height),
        ),
      ),
    ),
  );
}
