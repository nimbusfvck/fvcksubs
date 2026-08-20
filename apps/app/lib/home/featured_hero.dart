import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';

import '../app_scope.dart';
import '../detail/open_versioned_item.dart';
import '../library/library_controller.dart';
import '../player/play_item.dart';
import '../theme/tokens.dart';

class FeaturedHero extends StatefulWidget {
  const FeaturedHero({super.key, required this.items});

  final List<VersionedMediaItem> items;

  @override
  State<FeaturedHero> createState() => _FeaturedHeroState();
}

class _FeaturedHeroState extends State<FeaturedHero> {
  late final PageController _pageController;
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();
    return Stack(
      fit: StackFit.expand,
      children: [
        PageView.builder(
          controller: _pageController,
          itemCount: widget.items.length,
          onPageChanged: (value) => setState(() => _page = value),
          itemBuilder: (context, index) =>
              _FeaturedSlide(item: widget.items[index]),
        ),
        if (widget.items.length > 1)
          Positioned(
            right: AppSpacing.md,
            bottom: AppSpacing.md,
            child: Semantics(
              label: 'Featured item ${_page + 1} of ${widget.items.length}',
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var index = 0; index < widget.items.length; index++)
                    Padding(
                      padding: const EdgeInsets.only(left: AppSpacing.xxs),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: index == _page ? 18 : 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: index == _page
                              ? AppColors.onDark
                              : AppColors.onDarkSoft.withValues(alpha: 0.65),
                          borderRadius: AppRadius.pill,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _FeaturedSlide extends StatelessWidget {
  const _FeaturedSlide({required this.item});

  final VersionedMediaItem item;

  @override
  Widget build(BuildContext context) {
    final media = item.item;
    final artwork = media.artwork;
    final image = artwork?.portrait ?? artwork?.landscape ?? artwork?.logo;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (image != null)
          CachedNetworkImage(
            imageUrl: image.url,
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
            fadeInDuration: Duration.zero,
            placeholder: (_, _) =>
                const ColoredBox(color: AppColors.surfaceDarkElevated),
            errorWidget: (_, _, _) => const ColoredBox(
              color: AppColors.surfaceDarkElevated,
              child: Icon(
                Icons.movie_outlined,
                color: AppColors.onDarkSoft,
                size: 48,
              ),
            ),
          )
        else
          const ColoredBox(color: AppColors.surfaceDarkElevated),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xC9000000), Color(0x18000000), Color(0xF2101010)],
              stops: [0, 0.42, 1],
            ),
          ),
        ),
        Positioned.fill(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              72,
              AppSpacing.md,
              76,
            ),
            child: Align(
              alignment: Alignment.center,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: _FeaturedDetails(item: item),
              ),
            ),
          ),
        ),
      ],
    );
  }
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
        Text(
          media.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: AppTypography.displaySm.copyWith(color: AppColors.onDark),
        ),
        const SizedBox(height: AppSpacing.xs),
        _FeaturedMeta(item: media),
        if (media.subtitle != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            media.subtitle!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: AppTypography.bodySm.copyWith(color: AppColors.onDarkSoft),
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FilledButton.icon(
              key: const Key('featured-play'),
              onPressed: () => unawaited(_play(context)),
              icon: const Icon(Icons.play_arrow),
              label: const Text('Play'),
            ),
            const SizedBox(width: AppSpacing.xs),
            BlocBuilder<LibraryController, LibraryState>(
              bloc: AppScope.of(context).libraryController,
              builder: (context, state) {
                final favorite = state.isFavorite(media.ref);
                return IconButton(
                  key: const Key('featured-favorite'),
                  tooltip: favorite
                      ? 'Remove from favorites'
                      : 'Add to favorites',
                  style: IconButton.styleFrom(
                    foregroundColor: AppColors.onDark,
                    backgroundColor: AppColors.surfaceDarkElevated.withValues(
                      alpha: 0.86,
                    ),
                    side: const BorderSide(color: AppColors.outlineDark),
                  ),
                  icon: Icon(favorite ? Icons.favorite : Icons.favorite_border),
                  onPressed: () => AppScope.of(
                    context,
                  ).libraryController.toggleFavorite(media),
                );
              },
            ),
            const SizedBox(width: AppSpacing.xs),
            IconButton(
              key: const Key('featured-info'),
              tooltip: 'Open details',
              style: IconButton.styleFrom(
                foregroundColor: AppColors.onDark,
                backgroundColor: AppColors.surfaceDarkElevated.withValues(
                  alpha: 0.86,
                ),
                side: const BorderSide(color: AppColors.outlineDark),
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

class _FeaturedMeta extends StatelessWidget {
  const _FeaturedMeta({required this.item});

  final MediaItemV2 item;

  @override
  Widget build(BuildContext context) {
    final values = <Widget>[
      Text(
        _kindLabel(item),
        style: AppTypography.bodySm.copyWith(color: AppColors.onDarkSoft),
      ),
      if (item.releaseYear != null)
        Text(
          item.releaseYear.toString(),
          style: AppTypography.bodySm.copyWith(color: AppColors.onDarkSoft),
        ),
      if (item.rating != null) ...[
        const Icon(Icons.star, size: 15, color: Colors.amber),
        Text(
          item.rating!.toStringAsFixed(1),
          style: AppTypography.bodySm.copyWith(color: AppColors.onDark),
        ),
      ],
      if (item is EventItemV2 &&
          (item as EventItemV2).schedule.state == ScheduleState.live)
        Text(
          'LIVE',
          style: AppTypography.caption.copyWith(color: AppColors.liveAccent),
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
