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

const double _posterTitleHeight = 34;

double mediaCardPosterHeight(double width) =>
    width * 1.5 + AppSpacing.xs + _posterTitleHeight;

const double recommendationCardFooterHeight = 48;

double mediaRecommendationCardHeight(double width) =>
    width * 9 / 16 + AppSpacing.xs + recommendationCardFooterHeight;

class MediaCardV2 extends StatelessWidget {
  const MediaCardV2({
    super.key,
    required this.item,
    required this.onTap,
    this.onLongPress,
    this.showSubtitle = true,
    this.heroTag,
    this.enableHero = true,
    this.rank,
  });

  final MediaItemV2 item;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool showSubtitle;

  /// Optional route-specific tag used when the same item appears more than once.
  final Object? heroTag;

  /// Disables the shared artwork flight when a page renders many copies of
  /// the same Home cards at once.
  final bool enableHero;

  /// Optional rank badge used by the app-owned Top 10 shelf.
  final int? rank;

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
        heroTag: enableHero ? heroTag ?? mediaArtworkHeroTag(value.ref) : null,
        rank: rank,
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

/// A wider, landscape card for detail-page recommendations.
class MediaRecommendationCard extends StatelessWidget {
  const MediaRecommendationCard({
    super.key,
    required this.item,
    required this.onTap,
    this.onLongPress,
    this.heroTag,
  });

  final MediaItemV2 item;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final Object? heroTag;

  @override
  Widget build(BuildContext context) {
    const width = 216.0;
    final image =
        item.artwork?.landscape ??
        item.artwork?.backdrops.firstOrNull ??
        item.artwork?.portrait;
    final tag = heroTag ?? mediaArtworkHeroTag(item.ref);
    final metadata = [
      if (item.releaseYear case final year?) year.toString(),
      if (item.genres.isNotEmpty) item.genres.take(2).join(' · '),
    ].join(' • ');

    return SizedBox(
      width: width,
      height: mediaRecommendationCardHeight(width),
      child: Clickable(
        onTap: onTap,
        onLongPress: onLongPress,
        color: Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: width * 9 / 16,
              width: width,
              child: ClipRRect(
                borderRadius: AppRadius.lg,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (image == null)
                      ArtworkPlaceholder(title: item.title)
                    else
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final artwork = CachedNetworkImage(
                            imageUrl: image.url,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity,
                            fadeInDuration: Duration.zero,
                            useOldImageOnUrlChange: true,
                            memCacheWidth: artworkCacheDimension(
                              context,
                              constraints.maxWidth,
                            ),
                            placeholder: (_, _) =>
                                ArtworkPlaceholder(title: item.title),
                            errorWidget: (_, _, _) =>
                                ArtworkPlaceholder(title: item.title),
                          );
                          return Hero(
                            tag: tag,
                            transitionOnUserGestures: true,
                            flightShuttleBuilder:
                                mediaArtworkFlightShuttleBuilder,
                            child: artwork,
                          );
                        },
                      ),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Color(0xD9000000)],
                        ),
                      ),
                    ),
                    if (item.artwork?.logo case final logo?)
                      Positioned(
                        left: AppSpacing.sm,
                        right: AppSpacing.sm,
                        bottom: AppSpacing.sm,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: CachedNetworkImage(
                            imageUrl: logo.url,
                            height: 30,
                            width: width * 0.62,
                            fit: BoxFit.contain,
                            alignment: Alignment.centerLeft,
                            errorWidget: (_, _, _) => const SizedBox.shrink(),
                          ),
                        ),
                      ),
                    if (item.rating case final rating?)
                      _PosterRatingBadge(rating: rating),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.titleSm.copyWith(color: AppColors.onDark),
            ),
            if (metadata.isNotEmpty)
              Text.rich(
                TextSpan(
                  text: metadata,
                  style: AppTypography.caption.copyWith(
                    color: AppColors.onDarkSoft,
                  ),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
      ),
    );
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
    this.rank,
  });

  final MediaItemV2 item;
  final ImageRef image;
  final Object? heroTag;
  final int? rank;

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
              _PosterImage(item: item, image: image, heroTag: heroTag),
              if (item.rating case final rating?)
                _PosterRatingBadge(rating: rating),
              if (rank case final value?) _PosterRankBadge(rank: value),
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: AppRadius.lg,
                      border: Border.all(
                        color: AppColors.outlineDark,
                        width: 0.6,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: AppSpacing.xs),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
        child: SizedBox(
          height: _posterTitleHeight,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.bodySm.copyWith(color: AppColors.onDark),
              ),
              if (item.releaseYear case final year?)
                Text(
                  year.toString(),
                  maxLines: 1,
                  style: AppTypography.caption.copyWith(
                    color: AppColors.onDarkSoft,
                  ),
                ),
            ],
          ),
        ),
      ),
    ],
  );
}

class _PosterImage extends StatelessWidget {
  const _PosterImage({
    required this.item,
    required this.image,
    required this.heroTag,
  });

  final MediaItemV2 item;
  final ImageRef image;
  final Object? heroTag;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final imageWidget = CachedNetworkImage(
        imageUrl: image.url,
        fit: BoxFit.cover,
        width: double.infinity,
        fadeInDuration: const Duration(milliseconds: 220),
        fadeOutDuration: const Duration(milliseconds: 100),
        fadeInCurve: Curves.easeOut,
        useOldImageOnUrlChange: true,
        memCacheWidth: artworkCacheDimension(context, constraints.maxWidth),
        placeholder: (_, _) => ArtworkPlaceholder(title: item.title),
        errorWidget: (_, _, _) => ArtworkPlaceholder(title: item.title),
      );
      final tag = heroTag;
      return tag == null
          ? imageWidget
          : Hero(
              tag: tag,
              transitionOnUserGestures: true,
              flightShuttleBuilder: mediaArtworkFlightShuttleBuilder,
              child: imageWidget,
            );
    },
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
        vertical: AppSpacing.xxs,
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

class _PosterRankBadge extends StatelessWidget {
  const _PosterRankBadge({required this.rank});

  final int rank;

  @override
  Widget build(BuildContext context) => Positioned(
    top: 0,
    left: 0,
    child: Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: 2,
      ),
      decoration: const BoxDecoration(
        color: AppColors.liveAccent,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(AppRadius.lgValue),
          bottomRight: Radius.circular(AppRadius.smValue),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'TOP',
            style: AppTypography.liveBadge.copyWith(
              color: AppColors.onDark,
              fontSize: 8,
              height: 1,
            ),
          ),
          Text(
            rank.toString(),
            style: AppTypography.liveBadge.copyWith(
              color: AppColors.onDark,
              fontSize: 12,
              height: 1.1,
            ),
          ),
        ],
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
