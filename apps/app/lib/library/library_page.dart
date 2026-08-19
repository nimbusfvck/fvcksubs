import 'package:flutter/material.dart';
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';
import 'package:fvcksubs_storage/fvcksubs_storage.dart';

import '../app_scope.dart';
import '../catalog/media_card.dart';
import '../detail/open_item.dart';
import '../theme/tokens.dart';

class LibraryPage extends StatelessWidget {
  const LibraryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final controller = scope.libraryController;
    final continueWatching = controller.continueWatching;
    final favorites = controller.favorites;
    final history = controller.history;

    if (continueWatching.isEmpty && favorites.isEmpty && history.isEmpty) {
      return const _EmptyLibrary();
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      children: [
        if (continueWatching.isNotEmpty)
          _Section(
            title: 'Continue Watching',
            records: continueWatching,
            registry: scope.registry,
          ),
        if (favorites.isNotEmpty)
          _Section(
            title: 'Favorites',
            records: favorites,
            registry: scope.registry,
          ),
        if (history.isNotEmpty)
          _Section(
            title: 'History',
            records: history,
            registry: scope.registry,
          ),
      ],
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary();

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.bookmark_border,
            size: 48,
            color: AppColors.onDarkSoft,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Nothing here yet',
            style: AppTypography.titleMd.copyWith(color: AppColors.onDark),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Your favourites and watch history will live here.',
            textAlign: TextAlign.center,
            style: AppTypography.bodySm.copyWith(color: AppColors.onDarkSoft),
          ),
        ],
      ),
    ),
  );
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.records,
    required this.registry,
  });

  final String title;
  final List<UserMediaState> records;
  final ExtensionRegistry registry;

  @override
  Widget build(BuildContext context) {
    final posterMode = records.any((r) => r.item.poster != null);
    final itemWidth = posterMode ? 140.0 : 300.0;
    final height = posterMode ? 260.0 : 172.0;

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
            title,
            style: AppTypography.titleMd.copyWith(color: AppColors.onDark),
          ),
        ),
        SizedBox(
          height: height,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            itemCount: records.length,
            separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.md),
            itemBuilder: (context, i) => SizedBox(
              width: itemWidth,
              child: _RecordCard(record: records[i], registry: registry),
            ),
          ),
        ),
      ],
    );
  }
}

class _RecordCard extends StatelessWidget {
  const _RecordCard({required this.record, required this.registry});

  final UserMediaState record;
  final ExtensionRegistry registry;

  bool get _available =>
      registry.installed.any((m) => m.id == record.ref.extensionId);

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: _available ? 1 : 0.4,
    child: MediaCard(
      item: record.item,
      onTap: () => _available
          ? openItem(context, record.item)
          : ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Install "${record.ref.extensionId}" to watch this.',
                ),
              ),
            ),
    ),
  );
}
