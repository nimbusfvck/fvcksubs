import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';

import '../catalog/artwork_cache.dart';
import '../catalog/generated_banner.dart';
import '../catalog/start_time_label.dart';
import '../theme/tokens.dart';
import 'shimmer_placeholder.dart';

/// Shared centered title and metadata used by Home and Detail hero cards.
class MediaHeroSummary extends StatelessWidget {
  const MediaHeroSummary({
    super.key,
    required this.item,
    this.extra,
    this.actions,
    this.titleTextKey,
    this.titleLogoKey,
  });

  static const textShadows = [
    Shadow(color: Colors.black87, blurRadius: 4, offset: Offset(0, 1)),
  ];

  final MediaItemV2 item;
  final Widget? extra;
  final Widget? actions;
  final Key? titleTextKey;
  final Key? titleLogoKey;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.center,
    mainAxisSize: MainAxisSize.min,
    children: [
      _MediaHeroTitle(item: item, textKey: titleTextKey, logoKey: titleLogoKey),
      const SizedBox(height: AppSpacing.xs),
      _MediaHeroMeta(item: item),
      if (item.subtitle case final subtitle?) ...[
        const SizedBox(height: AppSpacing.xs),
        Text(
          subtitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: AppTypography.bodySm.copyWith(
            color: AppColors.onDarkSoft,
            shadows: textShadows,
          ),
        ),
      ],
      if (extra case final extra?) ...[
        const SizedBox(height: AppSpacing.xs),
        extra,
      ],
      if (actions case final actions?) ...[
        const SizedBox(height: AppSpacing.sm),
        actions,
      ],
    ],
  );
}

class _MediaHeroTitle extends StatelessWidget {
  const _MediaHeroTitle({required this.item, this.textKey, this.logoKey});

  final MediaItemV2 item;
  final Key? textKey;
  final Key? logoKey;

  @override
  Widget build(BuildContext context) {
    if (item case EventItemV2(
      :final participants,
      :final branding,
    ) when participants.length == 2) {
      return MatchupText(
        home: participants[0].name,
        away: participants[1].name,
        accent: GeneratedBanner.accentFor(participants, branding: branding),
        singleLine: true,
        uppercase: true,
        textKey: textKey,
      );
    }
    final logo = switch (item) {
      VideoItemV2() || SeriesItemV2() => item.artwork?.logo,
      _ => null,
    };
    final fallback = Text(
      item.title,
      key: textKey,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: AppTypography.displaySm.copyWith(
        color: AppColors.onDark,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.7,
        shadows: MediaHeroSummary.textShadows,
      ),
    );
    if (logo == null) return fallback;
    return Semantics(
      label: item.title,
      image: true,
      child: ExcludeSemantics(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280),
          child: SizedBox(
            height: 56,
            child: CachedNetworkImage(
              key: logoKey,
              imageUrl: logo.url,
              fit: BoxFit.contain,
              fadeInDuration: Duration.zero,
              memCacheWidth: artworkCacheDimension(context, 280),
              placeholder: (_, _) => Center(
                child: ShimmerPlaceholder(
                  width: 180,
                  height: 32,
                  borderRadius: AppRadius.sm,
                ),
              ),
              errorWidget: (_, _, _) => Center(child: fallback),
            ),
          ),
        ),
      ),
    );
  }
}

class _MediaHeroMeta extends StatelessWidget {
  const _MediaHeroMeta({required this.item});

  final MediaItemV2 item;

  @override
  Widget build(BuildContext context) {
    final event = item is EventItemV2 ? item as EventItemV2 : null;
    final eventLabel =
        event == null || event.schedule.state == ScheduleState.live
        ? null
        : event.schedule.label ?? startTimeLabel(event.schedule.startsAt);
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xxs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          _kindLabel(item),
          style: AppTypography.bodySm.copyWith(
            color: AppColors.onDarkSoft,
            shadows: MediaHeroSummary.textShadows,
          ),
        ),
        if (item.releaseYear case final year?)
          Text(
            year.toString(),
            style: AppTypography.bodySm.copyWith(
              color: AppColors.onDarkSoft,
              shadows: MediaHeroSummary.textShadows,
            ),
          ),
        if (item.rating case final rating?) ...[
          const Icon(Icons.star, size: 15, color: Colors.amber),
          Text(
            rating.toStringAsFixed(1),
            style: AppTypography.bodySm.copyWith(
              color: AppColors.onDark,
              shadows: MediaHeroSummary.textShadows,
            ),
          ),
        ],
        if (eventLabel != null)
          Text(
            eventLabel,
            style: AppTypography.bodySm.copyWith(
              color: AppColors.onDarkSoft,
              shadows: MediaHeroSummary.textShadows,
            ),
          ),
        if (event?.schedule.state == ScheduleState.live)
          Text(
            'LIVE',
            style: AppTypography.caption.copyWith(
              color: AppColors.liveAccent,
              shadows: MediaHeroSummary.textShadows,
            ),
          ),
      ],
    );
  }
}

String _kindLabel(MediaItemV2 item) => switch (item.kind) {
  MediaKindV2.video => 'Movie',
  MediaKindV2.series => 'Series',
  MediaKindV2.episode => 'Episode',
  MediaKindV2.channel => 'Live',
  MediaKindV2.event => 'Live event',
};
