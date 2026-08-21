import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';

import '../app_scope.dart';
import '../catalog/generated_banner.dart';
import '../catalog/start_time_label.dart';
import '../detail/open_versioned_item.dart';
import '../library/library_controller.dart';
import '../player/play_item.dart';
import '../player/trailer_preview.dart';
import '../theme/tokens.dart';
import '../widgets/shimmer_placeholder.dart';

class FeaturedHero extends StatefulWidget {
  const FeaturedHero({super.key, required this.items});

  final List<VersionedMediaItem> items;

  @override
  State<FeaturedHero> createState() => _FeaturedHeroState();
}

/// Keeps the expanded app bar stable while the featured feed is loading.
class FeaturedHeroPlaceholder extends StatelessWidget {
  const FeaturedHeroPlaceholder({super.key});

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Stack(
      key: const Key('featured-hero-placeholder'),
      fit: StackFit.expand,
      children: [
        const Positioned.fill(child: ShimmerPlaceholder(height: null)),
        const DecoratedBox(
          decoration: BoxDecoration(gradient: _featuredGradient),
        ),
        Positioned(
          left: AppSpacing.md,
          right: AppSpacing.md,
          bottom: 64,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const ShimmerPlaceholder(
                width: 180,
                height: 24,
                borderRadius: BorderRadius.all(Radius.circular(4)),
              ),
              const SizedBox(height: AppSpacing.sm),
              const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ShimmerPlaceholder(
                    width: 56,
                    height: 14,
                    borderRadius: BorderRadius.all(Radius.circular(4)),
                  ),
                  SizedBox(width: AppSpacing.xs),
                  ShimmerPlaceholder(
                    width: 56,
                    height: 14,
                    borderRadius: BorderRadius.all(Radius.circular(4)),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              const ShimmerPlaceholder(
                width: 280,
                height: 14,
                borderRadius: BorderRadius.all(Radius.circular(4)),
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: AppSpacing.xs,
                children: [
                  ShimmerPlaceholder(
                    width: 92,
                    height: 40,
                    borderRadius: AppRadius.md,
                  ),
                  ShimmerPlaceholder(
                    width: 40,
                    height: 40,
                    borderRadius: AppRadius.md,
                  ),
                  ShimmerPlaceholder(
                    width: 40,
                    height: 40,
                    borderRadius: AppRadius.md,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _FeaturedHeroState extends State<FeaturedHero> {
  late final PageController _pageController;
  final ValueNotifier<bool> _scrolling = ValueNotifier(false);
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void didUpdateWidget(covariant FeaturedHero oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.items.isEmpty || _page >= widget.items.length) {
      _page = 0;
      if (_pageController.hasClients) _pageController.jumpToPage(0);
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _scrolling.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();
    return Stack(
      fit: StackFit.expand,
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: _onScrollNotification,
          child: PageView.builder(
            controller: _pageController,
            itemCount: widget.items.length,
            onPageChanged: (value) => setState(() => _page = value),
            itemBuilder: (context, index) => _FeaturedSlide(
              item: widget.items[index],
              active: index == _page,
              scrolling: _scrolling,
            ),
          ),
        ),
        if (widget.items.length > 1)
          Positioned(
            key: const Key('featured-page-indicator'),
            left: 0,
            right: 0,
            bottom: AppSpacing.md,
            child: Center(
              child: _FeaturedPageIndicator(
                page: _page,
                count: widget.items.length,
              ),
            ),
          ),
      ],
    );
  }

  bool _onScrollNotification(ScrollNotification notification) {
    if (notification is ScrollStartNotification) {
      _setScrolling(true);
    } else if (notification is ScrollEndNotification) {
      _setScrolling(false);
    }
    return false;
  }

  void _setScrolling(bool scrolling) {
    if (!mounted || _scrolling.value == scrolling) return;
    // Only the preview reacts; rebuilding PageView during a drag can stall the
    // gesture when its active page contains a native video texture.
    _scrolling.value = scrolling;
  }
}

class _FeaturedPageIndicator extends StatelessWidget {
  const _FeaturedPageIndicator({required this.page, required this.count});

  final int page;
  final int count;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Featured item ${page + 1} of $count',
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceDark.withValues(alpha: 0.82),
        borderRadius: AppRadius.pill,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: AppSpacing.xxs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var index = 0; index < count; index++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  width: index == page ? 20 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: index == page
                        ? AppColors.primaryAction
                        : AppColors.onDarkSoft.withValues(alpha: 0.7),
                    borderRadius: AppRadius.pill,
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class _FeaturedSlide extends StatefulWidget {
  const _FeaturedSlide({
    required this.item,
    required this.active,
    required this.scrolling,
  });

  final VersionedMediaItem item;
  final bool active;
  final ValueListenable<bool> scrolling;

  @override
  State<_FeaturedSlide> createState() => _FeaturedSlideState();
}

class _FeaturedSlideState extends State<_FeaturedSlide> {
  Future<MediaDetailV2>? _detail;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ensureDetailLoaded();
  }

  @override
  void didUpdateWidget(covariant _FeaturedSlide oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.item.ref != widget.item.item.ref) {
      _detail = null;
    }
    _ensureDetailLoaded();
  }

  void _ensureDetailLoaded() {
    if (!widget.active || _detail != null) return;
    _detail = _loadDetail();
  }

  Future<MediaDetailV2>? _loadDetail() {
    final item = widget.item;
    if (item.legacyItem != null ||
        (item.item is! VideoItemV2 && item.item is! SeriesItemV2)) {
      return null;
    }
    final registry = AppScope.of(context).registry;
    final manifest = registry.installed.where(
      (entry) => entry.id == item.item.ref.extensionId,
    );
    if (manifest.isEmpty || manifest.first.apiVersion < 2) return null;
    return registry.metaV2(item.item.ref);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<MediaDetailV2>(
    future: _detail,
    builder: (context, snapshot) => _buildSlide(
      !widget.active || snapshot.data == null
          ? null
          : _autoplayTrailer(snapshot.data!),
    ),
  );

  Widget _buildSlide(MediaTrailer? preview) {
    final media = widget.item.item;
    final artwork = media.artwork;
    final image = artwork?.portrait ?? artwork?.landscape;
    final fallbackArtwork = _fallbackArtwork(media);
    final cacheWidth =
        (MediaQuery.sizeOf(context).width *
                MediaQuery.devicePixelRatioOf(context))
            .round();
    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (image != null)
            CachedNetworkImage(
              imageUrl: image.url,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              fadeInDuration: Duration.zero,
              memCacheWidth: cacheWidth,
              placeholder: (_, _) =>
                  const ColoredBox(color: AppColors.surfaceDarkElevated),
              errorWidget: (_, _, _) => fallbackArtwork,
            )
          else
            fallbackArtwork,
          if (preview != null)
            Positioned.fill(
              child: ValueListenableBuilder<bool>(
                valueListenable: widget.scrolling,
                builder: (context, scrolling, child) => TrailerPreview(
                  trailer: preview,
                  playing: widget.active && !scrolling,
                ),
              ),
            ),
          const DecoratedBox(
            decoration: BoxDecoration(gradient: _featuredGradient),
          ),
          Positioned(
            left: AppSpacing.md,
            right: AppSpacing.md,
            bottom: 64,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: SizedBox(
                  width: double.infinity,
                  child: _FeaturedDetails(item: widget.item),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

MediaTrailer? _autoplayTrailer(MediaDetailV2 detail) {
  for (final trailer in detail.trailers) {
    if (trailer.mimeType?.toLowerCase().startsWith('video/') ?? false) {
      return trailer;
    }
  }
  return null;
}

Widget _fallbackArtwork(MediaItemV2 item) => switch (item) {
  EventItemV2(:final participants) => GeneratedLiveArtwork(
    seed: _artworkSeed(item),
    participants: participants,
    logo: item.artwork?.logo,
  ),
  ChannelItemV2() => GeneratedLiveArtwork(
    seed: _artworkSeed(item),
    logo: item.artwork?.logo,
  ),
  _ => const ColoredBox(
    color: AppColors.surfaceDarkElevated,
    child: Icon(Icons.movie_outlined, color: AppColors.onDarkSoft, size: 48),
  ),
};

String _artworkSeed(MediaItemV2 item) {
  final ref = item.ref;
  return '${ref.extensionId}|${ref.providerId}|${ref.id}|${item.title}';
}

class _FeaturedDetails extends StatelessWidget {
  const _FeaturedDetails({required this.item});

  final VersionedMediaItem item;

  @override
  Widget build(BuildContext context) {
    final media = item.item;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        _FeaturedTitle(item: media),
        const SizedBox(height: AppSpacing.xs),
        _FeaturedMeta(item: media),
        if (media.subtitle != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            media.subtitle!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: AppTypography.bodySm.copyWith(
              color: AppColors.onDarkSoft,
              shadows: _featuredTextShadows,
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            FilledButton.icon(
              key: const Key('featured-play'),
              onPressed: () => unawaited(_play(context)),
              icon: const Icon(Icons.play_arrow),
              label: const Text('Play'),
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: AppRadius.lg),
              ),
            ),
            BlocBuilder<LibraryController, LibraryState>(
              bloc: AppScope.of(context).libraryController,
              builder: (context, state) {
                final favorite = state.isFavorite(media.ref);
                return IconButton(
                  key: const Key('featured-favorite'),
                  tooltip: favorite ? 'In favorites' : 'Add to favorites',
                  style: IconButton.styleFrom(
                    foregroundColor: AppColors.onDark,
                    side: const BorderSide(color: AppColors.outlineDark),
                    shape: RoundedRectangleBorder(borderRadius: AppRadius.lg),
                  ),
                  icon: Icon(favorite ? Icons.check : Icons.add),
                  onPressed: () => AppScope.of(
                    context,
                  ).libraryController.toggleFavorite(media),
                );
              },
            ),
            IconButton(
              key: const Key('featured-info'),
              tooltip: 'Open details',
              style: IconButton.styleFrom(
                foregroundColor: AppColors.onDark,
                backgroundColor: AppColors.surfaceDarkElevated.withValues(
                  alpha: 0.86,
                ),
                side: const BorderSide(color: AppColors.outlineDark),
                shape: RoundedRectangleBorder(borderRadius: AppRadius.lg),
              ),
              icon: const Icon(Icons.info_outline),
              onPressed: () => openVersionedItem(context, item),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _play(BuildContext context) {
    final legacy = item.legacyItem;
    return legacy == null
        ? playItemV2(context, item.item)
        : playItem(context, legacy);
  }
}

class _FeaturedTitle extends StatelessWidget {
  const _FeaturedTitle({required this.item});

  final MediaItemV2 item;

  @override
  Widget build(BuildContext context) {
    final logo = switch (item) {
      VideoItemV2() || SeriesItemV2() => item.artwork?.logo,
      _ => null,
    };
    final fallback = _FeaturedTitleText(title: item.title);
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
              key: const Key('featured-title-logo'),
              imageUrl: logo.url,
              fit: BoxFit.contain,
              fadeInDuration: Duration.zero,
              placeholder: (_, _) => Center(child: fallback),
              errorWidget: (_, _, _) => Center(child: fallback),
            ),
          ),
        ),
      ),
    );
  }
}

class _FeaturedTitleText extends StatelessWidget {
  const _FeaturedTitleText({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => Text(
    title,
    key: const Key('featured-title-text'),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    textAlign: TextAlign.center,
    style: AppTypography.titleLg.copyWith(
      color: AppColors.onDark,
      shadows: _featuredTextShadows,
    ),
  );
}

class _FeaturedMeta extends StatelessWidget {
  const _FeaturedMeta({required this.item});

  final MediaItemV2 item;

  @override
  Widget build(BuildContext context) {
    final event = item is EventItemV2 ? item as EventItemV2 : null;
    final eventLabel =
        event == null || event.schedule.state == ScheduleState.live
        ? null
        : event.schedule.label ?? startTimeLabel(event.schedule.startsAt);
    final values = <Widget>[
      Text(
        _kindLabel(item),
        style: AppTypography.bodySm.copyWith(
          color: AppColors.onDarkSoft,
          shadows: _featuredTextShadows,
        ),
      ),
      if (item.releaseYear != null)
        Text(
          item.releaseYear.toString(),
          style: AppTypography.bodySm.copyWith(
            color: AppColors.onDarkSoft,
            shadows: _featuredTextShadows,
          ),
        ),
      if (item.rating != null) ...[
        const Icon(Icons.star, size: 15, color: Colors.amber),
        Text(
          item.rating!.toStringAsFixed(1),
          style: AppTypography.bodySm.copyWith(
            color: AppColors.onDark,
            shadows: _featuredTextShadows,
          ),
        ),
      ],
      if (eventLabel != null)
        Text(
          eventLabel,
          style: AppTypography.bodySm.copyWith(
            color: AppColors.onDarkSoft,
            shadows: _featuredTextShadows,
          ),
        ),
      if (event?.schedule.state == ScheduleState.live)
        Text(
          'LIVE',
          style: AppTypography.caption.copyWith(
            color: AppColors.liveAccent,
            shadows: _featuredTextShadows,
          ),
        ),
    ];
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xxs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: values,
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

const _featuredTextShadows = [
  Shadow(color: Colors.black87, blurRadius: 4, offset: Offset(0, 1)),
];

const _featuredGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [
    Color(0xD9000000),
    Color(0x40000000),
    Color(0xF0101010),
    Color(0xFF101010),
  ],
  stops: [0, 0.24, 0.58, 1],
);
