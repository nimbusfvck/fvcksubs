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
        final offset = (_controller.value * 2) - 1;
        return LinearGradient(
          begin: Alignment(offset - 1, 0),
          end: Alignment(offset + 1, 0),
          colors: const [
            AppColors.surfaceDarkContainer,
            AppColors.surfaceDarkHighest,
            AppColors.surfaceDarkContainer,
          ],
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
