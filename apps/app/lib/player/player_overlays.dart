import 'package:flutter/material.dart';

import '../theme/tokens.dart';

class PlayerPlaybackErrorOverlay extends StatelessWidget {
  const PlayerPlaybackErrorOverlay({
    super.key,
    required this.message,
    required this.retrying,
    required this.onRetry,
    required this.onChangeSource,
    required this.onBack,
  });

  final String message;
  final bool retrying;
  final VoidCallback onRetry;
  final VoidCallback? onChangeSource;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Colors.black.withValues(alpha: 0.92),
    child: SafeArea(
      child: Stack(
        children: [
          Positioned(
            top: AppSpacing.xxs,
            left: AppSpacing.xs,
            child: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded),
              color: Colors.white,
              iconSize: 22,
              tooltip: 'Back',
              onPressed: onBack,
            ),
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.error_outline,
                    color: Colors.white70,
                    size: 48,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    "Couldn't play this source",
                    style: AppTypography.titleMd.copyWith(color: Colors.white),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    message,
                    style: AppTypography.bodySm.copyWith(
                      color: AppColors.onDarkSoft,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      OutlinedButton(
                        onPressed: retrying ? null : onRetry,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white54),
                          shape: const StadiumBorder(),
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.lg,
                            vertical: AppSpacing.sm,
                          ),
                        ),
                        child: retrying
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Try Again'),
                      ),
                      if (onChangeSource != null) ...[
                        const SizedBox(width: AppSpacing.sm),
                        ElevatedButton(
                          onPressed: onChangeSource,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.black,
                            shape: const StadiumBorder(),
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.lg,
                              vertical: AppSpacing.sm,
                            ),
                          ),
                          child: const Text('Change Source'),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class PlayerDragToClose extends StatefulWidget {
  const PlayerDragToClose({
    super.key,
    required this.onDismiss,
    required this.child,
  });

  final VoidCallback onDismiss;
  final Widget child;

  @override
  State<PlayerDragToClose> createState() => _PlayerDragToCloseState();
}

const double _kDismissThreshold = 200;
const double _kDismissVelocity = 800;

class _PlayerDragToCloseState extends State<PlayerDragToClose>
    with SingleTickerProviderStateMixin {
  double _dy = 0;
  late final AnimationController _snapCtrl;
  late Animation<double> _snapAnim;

  @override
  void initState() {
    super.initState();
    _snapCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
  }

  @override
  void dispose() {
    _snapCtrl.dispose();
    super.dispose();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (_snapCtrl.isAnimating) _snapCtrl.stop();
    setState(() => _dy = (_dy + details.delta.dy).clamp(0, double.infinity));
  }

  void _onDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (_dy > _kDismissThreshold || velocity > _kDismissVelocity) {
      widget.onDismiss();
    } else {
      _snapBack();
    }
  }

  void _snapBack() {
    final start = _dy;
    _snapAnim = Tween<double>(
      begin: start,
      end: 0,
    ).animate(CurvedAnimation(parent: _snapCtrl, curve: Curves.elasticOut));
    _snapCtrl.forward(from: 0);
    _snapAnim.addListener(() {
      if (mounted) setState(() => _dy = _snapAnim.value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final progress = (_dy / _kDismissThreshold).clamp(0.0, 1.0);
    return GestureDetector(
      onVerticalDragUpdate: _onDragUpdate,
      onVerticalDragEnd: _onDragEnd,
      onVerticalDragCancel: _snapBack,
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 1.0 - progress * 0.6),
        child: Transform.translate(offset: Offset(0, _dy), child: widget.child),
      ),
    );
  }
}

class PlayerUpNextCard extends StatefulWidget {
  const PlayerUpNextCard({
    super.key,
    required this.seriesTitle,
    required this.subtitle,
    required this.countdown,
    required this.paused,
    required this.onPlayNext,
    required this.onCancel,
  });

  final String seriesTitle;
  final String subtitle;
  final Duration countdown;
  final bool paused;
  final VoidCallback onPlayNext;
  final VoidCallback onCancel;

  @override
  State<PlayerUpNextCard> createState() => _PlayerUpNextCardState();
}

class _PlayerUpNextCardState extends State<PlayerUpNextCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.countdown)
      ..addStatusListener(_onStatusChanged)
      ..forward();
  }

  @override
  void didUpdateWidget(covariant PlayerUpNextCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.paused == oldWidget.paused) return;
    if (widget.paused) {
      _controller.stop();
    } else {
      _controller.forward();
    }
  }

  void _onStatusChanged(AnimationStatus status) {
    if (status == AnimationStatus.completed) widget.onPlayNext();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: Container(
      width: MediaQuery.sizeOf(context).width,
      padding: EdgeInsets.fromLTRB(
        AppSpacing.sm,
        widget.paused ? AppSpacing.xxs : AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.surfaceDark.withValues(alpha: 0.95),
        borderRadius: AppRadius.sm,
        border: Border.all(color: Colors.white24, width: 0.5),
      ),
      child: Column(
        children: [
          if (widget.paused)
            Align(
              alignment: Alignment.topLeft,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: widget.onCancel,
                child: const Padding(
                  padding: EdgeInsets.all(2),
                  child: Icon(
                    Icons.close_rounded,
                    size: 16,
                    color: AppColors.onDarkSoft,
                  ),
                ),
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.seriesTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodyMd.copyWith(
                        color: AppColors.onDark,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      widget.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodySm.copyWith(
                        color: AppColors.onDarkSoft,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              SizedBox(
                width: 46,
                height: 46,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    AnimatedBuilder(
                      animation: _controller,
                      builder: (context, _) => CircularProgressIndicator(
                        value: 1.0 - _controller.value,
                        strokeWidth: 2.5,
                        backgroundColor: Colors.white24,
                        valueColor: const AlwaysStoppedAnimation(
                          AppColors.brandAccent,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(1),
                      child: Material(
                        color: Colors.white,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: widget.onPlayNext,
                          child: const SizedBox(
                            width: 24,
                            height: 24,
                            child: Icon(
                              Icons.play_arrow_rounded,
                              color: Colors.black,
                              size: 18,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
