import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';
import 'package:fvcksubs_storage/fvcksubs_storage.dart';

import '../detail/open_versioned_item.dart';
import '../library/library_controller.dart';
import '../theme/tokens.dart';

class ContinueWatchingShelf extends StatelessWidget {
  const ContinueWatchingShelf({
    super.key,
    required this.controller,
    required this.registry,
  });

  final LibraryController controller;
  final ExtensionRegistry registry;

  bool _isAvailable(UserMediaState record) => registry.installed.any(
    (manifest) => manifest.id == record.ref.extensionId,
  );

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
            height: 174,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              itemCount: records.length,
              separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.md),
              itemBuilder: (context, index) => SizedBox(
                width: 280,
                child: _ContinueCard(record: records[index]),
              ),
            ),
          ),
        ],
      );
    },
  );
}

class _ContinueCard extends StatelessWidget {
  const _ContinueCard({required this.record});

  final UserMediaState record;

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

  @override
  Widget build(BuildContext context) {
    final item = record.item;
    final image = item.artwork?.landscape ?? item.artwork?.portrait;
    final progress = _progress;
    final contextLabel = _context;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => openVersionedItem(context, VersionedMediaItem(item: item)),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (image != null)
              CachedNetworkImage(
                imageUrl: image.url,
                fit: BoxFit.cover,
                errorWidget: (_, _, _) =>
                    const ColoredBox(color: AppColors.surfaceDarkElevated),
              )
            else
              const ColoredBox(color: AppColors.surfaceDarkElevated),
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
      ),
    );
  }
}
