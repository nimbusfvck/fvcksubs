import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';
import 'package:fvcksubs_storage/fvcksubs_storage.dart';

import '../detail/detail_page_v2.dart';
import '../detail/open_versioned_item.dart';
import '../catalog/artwork_placeholder.dart';
import '../catalog/artwork_cache.dart';
import '../catalog/media_card_actions.dart';
import '../library/library_controller.dart';
import '../theme/tokens.dart';
import '../widgets/clickable.dart';

class ContinueWatchingShelf extends StatelessWidget {
  const ContinueWatchingShelf({
    super.key,
    required this.controller,
    required this.registry,
  });

  final LibraryController controller;
  final ExtensionRegistry registry;

  bool _isAvailable(UserMediaState record) {
    final installed = registry.installed.any(
      (manifest) => manifest.id == record.ref.extensionId,
    );
    if (!installed) return false;
    final rating = record.contentRating == ContentRating.unknown
        ? registry.contentRatingFor(record.ref)
        : record.contentRating;
    return !rating.isHiddenWhenNsfwDisabled(registry.showNsfw);
  }

  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<LibraryController, LibraryState>(
    bloc: controller,
    builder: (context, state) {
      final records = state.continueWatching.where(_isAvailable).toList();
      if (records.isEmpty) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.xs,
            ),
            child: Text(
              'Continue Watching',
              style: AppTypography.titleMd.copyWith(color: AppColors.onDark),
            ),
          ),
          SizedBox(
            height: 174 + Clickable.ringBleed * 2,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              itemCount: records.length,
              separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.md),
              itemBuilder: (context, index) => Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: Clickable.ringBleed,
                ),
                child: SizedBox(
                  width: 280,
                  child: _ContinueCard(
                    record: records[index],
                    onMarkAsWatched: () =>
                        controller.markAsWatched(records[index].item),
                    onLongPress: () => showMediaCardActions(
                      context,
                      records[index].item,
                      onViewDetails: () =>
                          openDetails(context, records[index].item),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}

class _ContinueCard extends StatelessWidget {
  const _ContinueCard({
    required this.record,
    required this.onMarkAsWatched,
    required this.onLongPress,
  });

  final UserMediaState record;
  final VoidCallback onMarkAsWatched;
  final VoidCallback onLongPress;

  double? get _progress {
    final duration = record.duration;
    final progress = record.progress;
    if (duration == null || progress == null || duration <= Duration.zero) {
      return null;
    }
    return progress.inMilliseconds / duration.inMilliseconds;
  }

  String get _title => switch (record.item) {
    EpisodeItemV2(:final subtitle?) => subtitle,
    _ => record.item.title,
  };

  String? get _context => switch (record.item) {
    EpisodeItemV2(:final episode) => 'Episode ${episode.position}',
    _ => null,
  };

  void _open(BuildContext context) {
    final item = record.item;
    if (item case EpisodeItemV2(:final episode, :final subtitle?)) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => DetailPageV2(
            item: SeriesItemV2(ref: episode.parentRef, title: subtitle),
          ),
        ),
      );
      return;
    }
    openVersionedItem(context, VersionedMediaItem(item: item));
  }

  @override
  Widget build(BuildContext context) {
    final item = record.item;
    final image = item.artwork?.landscape ?? item.artwork?.portrait;
    final progress = _progress;
    final contextLabel = _context;
    return Clickable(
      onTap: () => _open(context),
      onLongPress: onLongPress,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (image != null)
            LayoutBuilder(
              builder: (context, constraints) => CachedNetworkImage(
                imageUrl: image.url,
                fit: BoxFit.cover,
                memCacheWidth: artworkCacheDimension(
                  context,
                  constraints.maxWidth,
                ),
                memCacheHeight: artworkCacheDimension(
                  context,
                  constraints.maxHeight,
                ),
                placeholder: (_, _) =>
                    const ArtworkPlaceholder(icon: Icons.movie_outlined),
                errorWidget: (_, _, _) =>
                    const ArtworkPlaceholder(icon: Icons.movie_outlined),
              ),
            )
          else
            const ArtworkPlaceholder(icon: Icons.movie_outlined),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black87],
              ),
            ),
          ),
          Positioned(
            top: AppSpacing.xs,
            right: AppSpacing.xs,
            child: Material(
              color: Colors.black54,
              shape: const CircleBorder(),
              child: IconButton(
                tooltip: 'Mark as watched',
                onPressed: onMarkAsWatched,
                icon: const Icon(Icons.check_rounded),
                color: Colors.white,
                iconSize: 20,
                constraints: const BoxConstraints.tightFor(
                  width: 44,
                  height: 44,
                ),
                padding: EdgeInsets.zero,
              ),
            ),
          ),
          Positioned(
            left: AppSpacing.sm,
            right: AppSpacing.sm,
            bottom: AppSpacing.sm,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.titleSm.copyWith(color: Colors.white),
                ),
                if (contextLabel != null)
                  Text(
                    contextLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodySm.copyWith(
                      color: AppColors.onDarkSoft,
                    ),
                  ),
                if (progress != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  ClipRRect(
                    borderRadius: AppRadius.pill,
                    child: LinearProgressIndicator(
                      value: progress.clamp(0, 1),
                      minHeight: 4,
                      color: AppColors.brandAccent,
                      backgroundColor: Colors.white24,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
