import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';

import '../theme/tokens.dart';
import '../utils/date_formatters.dart';
import '../utils/media_item_metadata.dart';
import '../widgets/clickable.dart';
import 'artwork_placeholder.dart';
import 'generated_banner.dart';
import 'media_hero.dart';
import 'catalog_status_badges.dart';
import 'start_time_label.dart';

/// Whether [item] uses the generated portrait event artwork.
bool isMatchBannerItem(MediaItemV2 item) =>
    item is EventItemV2 &&
    item.participants.length == 2 &&
    item.artwork?.portrait == null;

class MediaCardV2 extends StatelessWidget {
  const MediaCardV2({
    super.key,
    required this.item,
    required this.onTap,
    this.showSubtitle = true,
    this.heroTag,
  });

  final MediaItemV2 item;
  final VoidCallback onTap;
  final bool showSubtitle;

  /// Optional route-specific tag used when the same item appears more than once.
  final Object? heroTag;

  @override
  Widget build(BuildContext context) =>
      Clickable(onTap: onTap, child: _content());

  Widget _content() {
    final value = item;
    final portrait = value.artwork?.portrait;
    if (portrait != null) {
      return _Poster(
        item: value,
        image: portrait,
        heroTag: heroTag ?? mediaArtworkHeroTag(value.ref),
        showSubtitle: showSubtitle,
      );
    }
    if (value is EventItemV2) {
      if (value.participants.length == 2) {
        return _Match(item: value, showSubtitle: showSubtitle);
      }
      if (_hasEventArtwork(value)) {
        return _SingleEvent(item: value, showSubtitle: showSubtitle);
      }
    }
    return _Summary(item: value, showSubtitle: showSubtitle);
  }
}

bool _hasEventArtwork(EventItemV2 item) =>
    item.artwork?.landscape != null ||
    item.artwork?.logo != null ||
    item.participants.any((participant) => participant.logo != null);

class _Poster extends StatelessWidget {
  const _Poster({
    required this.item,
    required this.image,
    required this.heroTag,
    required this.showSubtitle,
  });

  final MediaItemV2 item;
  final ImageRef image;
  final Object heroTag;
  final bool showSubtitle;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Hero(
              tag: heroTag,
              child: CachedNetworkImage(
                imageUrl: image.url,
                fit: BoxFit.cover,
                width: double.infinity,
                fadeInDuration: Duration.zero,
                placeholder: (_, _) =>
                    ArtworkPlaceholder(icon: _placeholderIcon(item)),
                errorWidget: (_, _, _) =>
                    ArtworkPlaceholder(icon: _placeholderIcon(item)),
              ),
            ),
            if (item.releaseDate case final releaseDate? when item.isUpcoming)
              _ReleaseDateBadge(releaseDate: releaseDate),
          ],
        ),
      ),
      _CardFooter(item: item, showSubtitle: showSubtitle),
    ],
  );
}

class _Match extends StatelessWidget {
  const _Match({required this.item, required this.showSubtitle});

  final EventItemV2 item;
  final bool showSubtitle;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: GeneratedBanner(
          participants: item.participants,
          eventName: item.subtitle ?? '',
          branding: item.branding,
        ),
      ),
      _CardFooter(item: item, showSubtitle: showSubtitle),
    ],
  );
}

class _SingleEvent extends StatelessWidget {
  const _SingleEvent({required this.item, required this.showSubtitle});

  final EventItemV2 item;
  final bool showSubtitle;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(child: _SingleEventArtwork(item: item)),
      _CardFooter(item: item, showSubtitle: showSubtitle),
    ],
  );
}

class _SingleEventArtwork extends StatelessWidget {
  const _SingleEventArtwork({required this.item});

  final EventItemV2 item;

  @override
  Widget build(BuildContext context) {
    final landscape = item.artwork?.landscape;
    final artwork = landscape == null
        ? GeneratedLiveArtwork(
            seed: _eventArtworkSeed(item),
            participants: item.participants,
            logo: item.artwork?.logo,
            branding: item.branding,
          )
        : CachedNetworkImage(
            imageUrl: landscape.url,
            fit: BoxFit.cover,
            width: double.infinity,
            fadeInDuration: Duration.zero,
            placeholder: (_, _) => const _EventArtworkFallback(),
            errorWidget: (_, _, _) => const _EventArtworkFallback(),
          );

    return Stack(
      fit: StackFit.expand,
      children: [
        artwork,
        if (landscape != null)
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  AppColors.surfaceDark.withValues(alpha: 0.6),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _EventArtworkFallback extends StatelessWidget {
  const _EventArtworkFallback();

  @override
  Widget build(BuildContext context) => const ColoredBox(
    color: AppColors.surfaceDarkElevated,
    child: Center(
      child: Icon(Icons.live_tv_outlined, color: AppColors.onDarkSoft),
    ),
  );
}

String _eventArtworkSeed(EventItemV2 item) {
  final ref = item.ref;
  return '${ref.extensionId}|${ref.providerId}|${ref.id}|${item.title}';
}

class _Summary extends StatelessWidget {
  const _Summary({required this.item, required this.showSubtitle});

  final MediaItemV2 item;
  final bool showSubtitle;

  @override
  Widget build(BuildContext context) {
    final icon = item is EventItemV2
        ? Icons.live_tv_outlined
        : Icons.movie_outlined;
    return Column(
      children: [
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              ArtworkPlaceholder(icon: icon),
              if (item.releaseDate case final releaseDate? when item.isUpcoming)
                _ReleaseDateBadge(releaseDate: releaseDate),
            ],
          ),
        ),
        _CardFooter(item: item, showSubtitle: showSubtitle),
      ],
    );
  }
}

class _ReleaseDateBadge extends StatelessWidget {
  const _ReleaseDateBadge({required this.releaseDate});

  final DateTime releaseDate;

  @override
  Widget build(BuildContext context) => Positioned(
    top: AppSpacing.xs,
    left: AppSpacing.xs,
    child: Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: AppColors.surfaceDark.withValues(alpha: 0.7),
        borderRadius: AppRadius.sm,
      ),
      child: Text(
        formatShortReleaseDate(releaseDate.toLocal()),
        style: AppTypography.liveBadge.copyWith(color: AppColors.onDark),
      ),
    ),
  );
}

class _CardFooter extends StatelessWidget {
  const _CardFooter({required this.item, required this.showSubtitle});

  final MediaItemV2 item;
  final bool showSubtitle;

  @override
  Widget build(BuildContext context) {
    final event = item is EventItemV2 ? item as EventItemV2 : null;
    final detail = event != null
        ? _eventMeta(event)
        : showSubtitle
        ? mediaItemSecondaryText(item)
        : null;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (event != null) ...[
            _ScheduleStatus(schedule: event.schedule, showLabel: false),
            const SizedBox(height: AppSpacing.xxs),
          ],
          Text(
            item.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.titleSm.copyWith(color: AppColors.onDark),
          ),
          if (detail != null)
            event != null
                ? Text(
                    detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodySm.copyWith(
                      color: AppColors.onDarkSoft,
                    ),
                  )
                : Text.rich(
                    mediaItemSecondarySpan(
                      item,
                      style: AppTypography.bodySm.copyWith(
                        color: AppColors.onDarkSoft,
                      ),
                      ratingColor: AppColors.ratingAccent,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
        ],
      ),
    );
  }
}

IconData _placeholderIcon(MediaItemV2 item) =>
    item is EventItemV2 ? Icons.live_tv_outlined : Icons.movie_outlined;

class _ScheduleStatus extends StatelessWidget {
  const _ScheduleStatus({required this.schedule, this.showLabel = true});

  final Schedule schedule;
  final bool showLabel;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      if (schedule.state == ScheduleState.live)
        const LiveBadge()
      else if (schedule.state == ScheduleState.scheduled)
        const UpcomingBadge(),
      if (showLabel && _label != null) ...[
        const SizedBox(width: AppSpacing.xs),
        Flexible(
          child: Text(
            _label!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.caption.copyWith(color: AppColors.onDarkSoft),
          ),
        ),
      ],
    ],
  );

  String? get _label => schedule.label ?? startTimeLabel(schedule.startsAt);
}

String? _eventMeta(EventItemV2 item) {
  return item.schedule.label ?? startTimeLabel(item.schedule.startsAt);
}
