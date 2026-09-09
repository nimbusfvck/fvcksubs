import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fvcksubs_app/widgets/media_hero_layout.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';

import '../app_scope.dart';
import '../catalog/generated_banner.dart';
import '../detail/open_versioned_item.dart';
import '../library/library_controller.dart';
import '../player/widgets/trailer_preview.dart';
import '../player/workflow/play_item.dart';
import '../theme/tokens.dart';
import '../widgets/shimmer_placeholder.dart';
import '../widgets/media_hero_card.dart';
import '../widgets/media_hero_flexible_space.dart';
import '../widgets/media_hero_summary.dart';

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
          decoration: BoxDecoration(gradient: MediaHeroCard.gradient),
        ),
        Positioned(
          left: AppSpacing.md,
          right: AppSpacing.md,
          bottom: MediaHeroLayout.homeSummaryBottom,
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
    final oldRef = _page < oldWidget.items.length
        ? oldWidget.items[_page].item.ref
        : null;
    if (widget.items.isEmpty) {
      _page = 0;
      if (_pageController.hasClients) _pageController.jumpToPage(0);
      return;
    }

    final matchingPage = oldRef == null
        ? -1
        : widget.items.indexWhere((entry) => entry.item.ref == oldRef);
    final nextPage = matchingPage >= 0
        ? matchingPage
        : _page.clamp(0, widget.items.length - 1).toInt();
    _page = nextPage;
    if (_pageController.hasClients &&
        _pageController.page?.round() != nextPage) {
      _pageController.jumpToPage(nextPage);
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
    final overlayOpacity = MediaHeroLayout.homeOverlayOpacity(
      MediaHeroCollapseScope.of(context),
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: _onScrollNotification,
          child: PageView.builder(
            controller: _pageController,
            itemCount: widget.items.length,
            onPageChanged: (value) => setState(() => _page = value),
            itemBuilder: (context, index) {
              final item = widget.items[index];
              return _FeaturedSlide(
                key: ValueKey(item.item.ref),
                item: item,
                active: index == _page,
                scrolling: _scrolling,
              );
            },
          ),
        ),
        if (widget.items.length > 1)
          Positioned(
            key: const Key('featured-page-indicator'),
            left: 0,
            right: 0,
            bottom: MediaHeroLayout.homeIndicatorBottom,
            child: Opacity(
              opacity: overlayOpacity,
              child: Center(
                child: _FeaturedPageIndicator(
                  page: _page,
                  count: widget.items.length,
                ),
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
    super.key,
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
    if (item.item is! VideoItemV2 && item.item is! SeriesItemV2) {
      return null;
    }
    final registry = AppScope.of(context).registry;
    final manifest = registry.installed.where(
      (entry) => entry.id == item.item.ref.extensionId,
    );
    if (manifest.isEmpty || manifest.first.apiVersion < 2) return null;
    return registry.meta(item.item.ref);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<MediaDetailV2>(
    future: _detail,
    builder: (context, snapshot) {
      // FutureBuilder retains the previous snapshot while a new detail future
      // is waiting. Never let that old detail keep a trailer playing for the
      // item that now occupies this page position.
      final detail = snapshot.connectionState == ConnectionState.done
          ? snapshot.data
          : null;
      return _buildSlide(
        detail,
        !widget.active || detail == null ? null : _autoplayTrailer(detail),
      );
    },
  );

  Widget _buildSlide(MediaDetailV2? detail, MediaTrailer? preview) {
    final media = widget.item.item;
    final displayItem = widget.item;
    final fallbackArtwork = _fallbackArtwork(media);
    final overlayOpacity = MediaHeroLayout.homeOverlayOpacity(
      MediaHeroCollapseScope.of(context),
    );
    return RepaintBoundary(
      child: MediaHeroCard(
        item: media,
        fallback: fallbackArtwork,
        preview: preview == null
            ? null
            : ValueListenableBuilder<bool>(
                valueListenable: widget.scrolling,
                builder: (context, scrolling, child) => TrailerPreview(
                  trailer: preview,
                  playing: widget.active && !scrolling,
                ),
              ),
        foreground: Positioned(
          left: AppSpacing.md,
          right: AppSpacing.md,
          bottom: MediaHeroLayout.homeSummaryBottom,
          child: Opacity(
            opacity: overlayOpacity,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: SizedBox(
                  width: double.infinity,
                  child: _FeaturedDetails(item: displayItem),
                ),
              ),
            ),
          ),
        ),
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
  EventItemV2(:final participants, :final branding, :final subtitle)
      when participants.length == 2 =>
    GeneratedBanner(
      participants: participants,
      eventName: subtitle ?? '',
      brandAboveParticipants: true,
      centerContent: true,
      participantLogoSize: 56,
      showMatchup: false,
      showBrand: false,
      branding: branding,
    ),
  EventItemV2(:final participants, :final branding) => GeneratedLiveArtwork(
    seed: _artworkSeed(item),
    participants: participants,
    logo: item.artwork?.logo,
    branding: branding,
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
    return MediaHeroSummary(
      item: media,
      titleTextKey: const Key('featured-title-text'),
      titleLogoKey: const Key('featured-title-logo'),
      actions: Wrap(
        alignment: WrapAlignment.center,
        spacing: AppSpacing.xs,
        runSpacing: AppSpacing.xs,
        children: [
          FilledButton.icon(
            key: const Key('featured-play'),
            onPressed: () => unawaited(_play(context)),
            icon: const Icon(Icons.play_arrow),
            label: const Text('Watch Now'),
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
    );
  }

  Future<void> _play(BuildContext context) {
    return playItemV2(context, item.item);
  }
}
