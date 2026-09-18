import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';

import '../catalog/artwork_cache.dart';
import '../catalog/generated_banner.dart';
import '../catalog/start_time_label.dart';
import '../theme/tokens.dart';
import 'media_hero_layout.dart';

/// Shared centered title and metadata used by Home and Detail hero cards.
class MediaHeroSummary extends StatelessWidget {
  const MediaHeroSummary({
    super.key,
    required this.item,
    this.extra,
    this.actions,
    this.titleTextKey,
    this.titleLogoKey,
    this.alignStart = false,
    this.showRatings = false,
  });

  static const textShadows = [
    Shadow(color: Colors.black87, blurRadius: 4, offset: Offset(0, 1)),
  ];

  final MediaItemV2 item;
  final Widget? extra;
  final Widget? actions;
  final Key? titleTextKey;
  final Key? titleLogoKey;
  final bool alignStart;
  final bool showRatings;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: alignStart
        ? CrossAxisAlignment.start
        : CrossAxisAlignment.center,
    mainAxisSize: MainAxisSize.min,
    children: [
      _MediaHeroTitle(
        item: item,
        textKey: titleTextKey,
        logoKey: titleLogoKey,
        alignStart: alignStart,
      ),
      const SizedBox(height: AppSpacing.xs),
      _MediaHeroMeta(
        item: item,
        alignStart: alignStart,
        showRatings: showRatings,
      ),
      if (item.subtitle case final subtitle?) ...[
        const SizedBox(height: AppSpacing.xs),
        Text(
          subtitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: alignStart ? TextAlign.start : TextAlign.center,
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
  const _MediaHeroTitle({
    required this.item,
    this.textKey,
    this.logoKey,
    required this.alignStart,
  });

  final MediaItemV2 item;
  final Key? textKey;
  final Key? logoKey;
  final bool alignStart;

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
        wrapLong: true,
        uppercase: true,
        textAlign: alignStart ? TextAlign.start : TextAlign.center,
        textKey: textKey,
      );
    }
    final logo = switch (item) {
      VideoItemV2() || SeriesItemV2() => item.artwork?.logo,
      _ => null,
    };
    final titleAlignment = alignStart ? Alignment.centerLeft : Alignment.center;
    final fallback = Text(
      item.title,
      key: textKey,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: alignStart ? TextAlign.start : TextAlign.center,
      style: AppTypography.displaySm.copyWith(
        fontSize: 26,
        color: AppColors.onDark,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.7,
        shadows: MediaHeroSummary.textShadows,
      ),
    );
    if (logo == null) return fallback;
    final largeScreen = MediaHeroLayout.isLargeScreen(context);
    final logoWidth = largeScreen ? 360.0 : 280.0;
    final logoHeight = largeScreen ? 68.0 : 56.0;
    return Semantics(
      label: item.title,
      image: true,
      child: ExcludeSemantics(
        child: Align(
          alignment: titleAlignment,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: logoWidth),
            child: SizedBox(
              width: double.infinity,
              height: logoHeight,
              child: CachedNetworkImage(
                key: logoKey,
                imageUrl: logo.url,
                alignment: titleAlignment,
                fit: BoxFit.contain,
                fadeInDuration: const Duration(milliseconds: 320),
                fadeInCurve: Curves.easeOutCubic,
                memCacheWidth: artworkCacheDimension(context, logoWidth),
                placeholder: (_, _) => const SizedBox.shrink(),
                errorWidget: (_, _, _) =>
                    Align(alignment: titleAlignment, child: fallback),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MediaHeroMeta extends StatelessWidget {
  const _MediaHeroMeta({
    required this.item,
    required this.alignStart,
    required this.showRatings,
  });

  final MediaItemV2 item;
  final bool alignStart;
  final bool showRatings;

  @override
  Widget build(BuildContext context) {
    final event = item is EventItemV2 ? item as EventItemV2 : null;
    final eventLabel =
        event == null || event.schedule.state == ScheduleState.live
        ? null
        : eventStartLabel(event.schedule.startsAt);
    return Wrap(
      alignment: alignStart ? WrapAlignment.start : WrapAlignment.center,
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
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.star, size: 15, color: Colors.amber),
              const SizedBox(width: AppSpacing.xxs),
              Text(
                rating.toStringAsFixed(1),
                style: AppTypography.bodySm.copyWith(
                  color: AppColors.onDark,
                  shadows: MediaHeroSummary.textShadows,
                ),
              ),
            ],
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
        if (showRatings)
          for (final rating in item.ratings) _MediaRatingChip(rating: rating),
      ],
    );
  }
}

class _MediaRatingChip extends StatelessWidget {
  const _MediaRatingChip({required this.rating});

  final MediaRating rating;

  @override
  Widget build(BuildContext context) {
    final score = rating.scale == 10
        ? '${rating.score.toStringAsFixed(1)}/10'
        : '${rating.score.toStringAsFixed(0)}/${rating.scale.toStringAsFixed(0)}';
    final icon = rating.icon;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: CachedNetworkImage(
              imageUrl: icon.url,
              width: 16,
              height: 16,
              fit: BoxFit.contain,
              errorWidget: (_, _, _) => _ratingFallbackIcon(rating.source),
            ),
          )
        else
          _ratingFallbackIcon(rating.source),
        const SizedBox(width: AppSpacing.xxs),
        Text(
          '${_ratingLabel(rating.source)} $score',
          style: AppTypography.bodySm.copyWith(
            color: AppColors.onDark,
            shadows: MediaHeroSummary.textShadows,
          ),
        ),
      ],
    );
  }
}

Widget _ratingFallbackIcon(String source) => Container(
  width: 16,
  height: 16,
  alignment: Alignment.center,
  decoration: BoxDecoration(
    color: Colors.white.withValues(alpha: 0.18),
    borderRadius: BorderRadius.circular(3),
  ),
  child: Text(
    _ratingLabel(source).substring(0, 1),
    style: const TextStyle(
      color: Colors.white,
      fontSize: 9,
      fontWeight: FontWeight.w800,
    ),
  ),
);

String _ratingLabel(String source) => switch (source) {
  'imdb' => 'IMDb',
  'rottenTomatoes' => 'RT',
  'metacritic' => 'MC',
  _ => source,
};

String _kindLabel(MediaItemV2 item) => switch (item.kind) {
  MediaKindV2.video => 'Movie',
  MediaKindV2.series => 'Series',
  MediaKindV2.episode => 'Episode',
  MediaKindV2.channel => 'Live',
  MediaKindV2.event => 'Live event',
};
