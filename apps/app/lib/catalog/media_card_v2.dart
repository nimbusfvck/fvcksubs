import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';

import '../theme/tokens.dart';
import '../utils/date_formatters.dart';
import '../utils/media_item_metadata.dart';
import '../widgets/clickable.dart';
import 'artwork_cache.dart';
import 'artwork_placeholder.dart';
import 'generated_banner.dart';
import 'media_hero.dart';
import 'catalog_status_badges.dart';
import 'start_time_label.dart';

/// Whether [item] uses the generated event banner.
bool isMatchBannerItem(MediaItemV2 item) =>
    item is EventItemV2 && item.participants.length == 2;

bool isPosterMediaItem(MediaItemV2 item) =>
    item.artwork?.portrait != null && item is! EventItemV2;

const double _posterTitleHeight = 18;

double mediaCardPosterHeight(double width) =>
    width * 1.5 + AppSpacing.xs + _posterTitleHeight;

class MediaCardV2 extends StatelessWidget {
  const MediaCardV2({
    super.key,
    required this.item,
    required this.onTap,
    this.onLongPress,
    this.showSubtitle = true,
    this.heroTag,
  });

  final MediaItemV2 item;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool showSubtitle;

  /// Optional route-specific tag used when the same item appears more than once.
  final Object? heroTag;

  @override
  Widget build(BuildContext context) => Clickable(
    onTap: onTap,
    onLongPress: onLongPress,
    color: Colors.transparent,
    child: _content(),
  );

  Widget _content() {
    final value = item;
    if (value is EventItemV2 && value.participants.length == 2) {
      return _Match(item: value, showSubtitle: showSubtitle);
    }
    final portrait = value.artwork?.portrait;
    if (portrait != null && value is! EventItemV2) {
      return _Poster(
        item: value,
        image: portrait,
        heroTag: heroTag ?? mediaArtworkHeroTag(value.ref),
      );
    }
    if (value is EventItemV2) {
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
  });

  final MediaItemV2 item;
  final ImageRef image;
  final Object heroTag;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(borderRadius: AppRadius.lg),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Hero(
                tag: heroTag,
                child: LayoutBuilder(
                  builder: (context, constraints) => CachedNetworkImage(
                    imageUrl: image.url,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    fadeInDuration: Duration.zero,
                    memCacheWidth: artworkCacheDimension(
                      context,
                      constraints.maxWidth,
                    ),
                    placeholder: (_, _) =>
                        ArtworkPlaceholder(title: item.title),
                    errorWidget: (_, _, _) =>
                        ArtworkPlaceholder(title: item.title),
                  ),
                ),
              ),
              if (item.rating case final rating?)
                _PosterRatingBadge(rating: rating),
              if (item.releaseYear case final year?)
                _PosterYearBadge(year: year),
            ],
          ),
        ),
      ),
      const SizedBox(height: AppSpacing.xs),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
        child: SizedBox(
          height: _posterTitleHeight,
          child: Text(
            item.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodySm.copyWith(color: AppColors.onDark),
          ),
        ),
      ),
    ],
  );
}

class _PosterRatingBadge extends StatelessWidget {
  const _PosterRatingBadge({required this.rating});

  final double rating;

  @override
  Widget build(BuildContext context) => Positioned(
    top: AppSpacing.xs,
    right: AppSpacing.xs,
    child: Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: AppColors.surfaceDark.withValues(alpha: 0.7),
        borderRadius: AppRadius.sm,
      ),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '★',
              style: AppTypography.liveBadge.copyWith(
                color: AppColors.ratingAccent,
              ),
            ),
            TextSpan(
              text: ' ${rating.toStringAsFixed(1)}',
              style: AppTypography.liveBadge.copyWith(color: AppColors.onDark),
            ),
          ],
        ),
      ),
    ),
  );
}

class _PosterYearBadge extends StatelessWidget {
  const _PosterYearBadge({required this.year});

  final int year;

  @override
  Widget build(BuildContext context) => Positioned(
    left: AppSpacing.xs,
    top: AppSpacing.xs,
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
        year.toString(),
        style: AppTypography.liveBadge.copyWith(color: AppColors.onDark),
      ),
    ),
  );
}

class _Match extends StatefulWidget {
  const _Match({required this.item, required this.showSubtitle});

  final EventItemV2 item;
  final bool showSubtitle;

  @override
  State<_Match> createState() => _MatchState();
}

class _MatchState extends State<_Match> {
  final Set<int> _failedParticipantLogos = {};

  bool get _hasAllParticipantLogoUrls => widget.item.participants.every(
    (participant) => participant.logo?.url.trim().isNotEmpty ?? false,
  );

  bool get _showLeaguePlaceholder =>
      !_hasAllParticipantLogoUrls || _failedParticipantLogos.isNotEmpty;

  void _onParticipantLogoStateChanged(int index, bool loaded) {
    if (!mounted) return;
    final changed = loaded
        ? _failedParticipantLogos.remove(index)
        : _failedParticipantLogos.add(index);
    if (changed) setState(() {});
  }

  @override
  void didUpdateWidget(covariant _Match oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.ref != widget.item.ref) {
      _failedParticipantLogos.clear();
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: GeneratedBanner(
          participants: widget.item.participants,
          eventName: _eventContextLabel(widget.item) ?? '',
          forceLeaguePlaceholder: _showLeaguePlaceholder,
          onParticipantLogoStateChanged: _onParticipantLogoStateChanged,
          branding: widget.item.branding,
        ),
      ),
      _CardFooter(item: widget.item, showSubtitle: widget.showSubtitle),
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
        : LayoutBuilder(
            builder: (context, constraints) => CachedNetworkImage(
              imageUrl: landscape.url,
              fit: BoxFit.cover,
              width: double.infinity,
              fadeInDuration: Duration.zero,
              memCacheWidth: artworkCacheDimension(
                context,
                constraints.maxWidth,
              ),
              placeholder: (_, _) =>
                  _EventArtworkFallback(label: _eventPlaceholderLabel(item)),
              errorWidget: (_, _, _) =>
                  _EventArtworkFallback(label: _eventPlaceholderLabel(item)),
            ),
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
  const _EventArtworkFallback({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) =>
      ArtworkPlaceholder(icon: Icons.live_tv_outlined, title: label);
}

String _eventPlaceholderLabel(EventItemV2 item) {
  return _eventContextLabel(item) ?? item.title;
}

String? _eventContextLabel(EventItemV2 item) {
  final label = item.subtitle?.trim();
  if (label == null || label.isEmpty || label.toLowerCase() == 'other') {
    return null;
  }
  return label;
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
    final placeholderTitle = item is EventItemV2
        ? _eventPlaceholderLabel(item as EventItemV2)
        : item.title;
    return Column(
      children: [
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              ArtworkPlaceholder(title: placeholderTitle),
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
            style:
                (event != null ? AppTypography.bodySm : AppTypography.titleSm)
                    .copyWith(color: AppColors.onDark),
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

  String? get _label =>
      schedule.label ?? eventTimeRangeLabel(schedule.startsAt, schedule.endsAt);
}

String? _eventMeta(EventItemV2 item) {
  if (item.schedule.state == ScheduleState.live &&
      item.schedule.label == null) {
    return null;
  }
  return item.schedule.label ??
      eventTimeRangeLabel(item.schedule.startsAt, item.schedule.endsAt);
}
