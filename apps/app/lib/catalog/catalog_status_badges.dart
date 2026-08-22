import 'package:flutter/material.dart';

import '../theme/tokens.dart';

class LiveBadge extends StatelessWidget {
  const LiveBadge({super.key});

  @override
  Widget build(BuildContext context) => const _StatusPill(
    text: 'LIVE',
    color: AppColors.liveAccent,
    foregroundColor: AppColors.primary,
  );
}

class UpcomingBadge extends StatelessWidget {
  const UpcomingBadge({super.key});

  @override
  Widget build(BuildContext context) =>
      const _StatusPill(text: 'UPCOMING', color: AppColors.brandAccent);
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.text,
    required this.color,
    this.foregroundColor = AppColors.primary,
  });

  final String text;
  final Color color;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 2),
    decoration: BoxDecoration(color: color, borderRadius: AppRadius.sm),
    child: Text(
      text,
      style: AppTypography.liveBadge.copyWith(color: foregroundColor),
    ),
  );
}
