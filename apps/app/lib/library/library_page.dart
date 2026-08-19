import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';
import 'package:fvcksubs_storage/fvcksubs_storage.dart';

import '../app_scope.dart';
import '../catalog/media_card.dart';
import '../catalog/media_card_v2.dart';
import '../detail/open_item.dart';
import '../detail/open_versioned_item.dart';
import 'library_controller.dart';
import 'library_controller_v2.dart';
import '../theme/tokens.dart';

class LibraryPage extends StatelessWidget {
  const LibraryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return BlocBuilder<LibraryControllerV2, LibraryStateV2>(
      bloc: scope.libraryControllerV2,
      builder: (context, v2) => ListenableBuilder(
        listenable: scope.libraryController,
        builder: (context, _) => _LibraryContent(
          legacy: scope.libraryController,
          v2: v2,
          registry: scope.registry,
        ),
      ),
    );
  }
}

class _LibraryContent extends StatelessWidget {
  const _LibraryContent({
    required this.legacy,
    required this.v2,
    required this.registry,
  });

  final LibraryController legacy;
  final LibraryStateV2 v2;
  final ExtensionRegistry registry;

  @override
  Widget build(BuildContext context) {
    final empty =
        legacy.continueWatching.isEmpty &&
        legacy.favorites.isEmpty &&
        legacy.history.isEmpty &&
        v2.continueWatching.isEmpty &&
        v2.favorites.isEmpty &&
        v2.history.isEmpty;
    if (empty) return const _EmptyLibrary();

    return ListView(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      children: [
        if (v2.continueWatching.isNotEmpty)
          _SectionV2(
            title: 'Continue Watching',
            records: v2.continueWatching,
            registry: registry,
          ),
        if (v2.favorites.isNotEmpty)
          _SectionV2(
            title: 'Favorites',
            records: v2.favorites,
            registry: registry,
          ),
        if (v2.history.isNotEmpty)
          _SectionV2(title: 'History', records: v2.history, registry: registry),
        if (legacy.continueWatching.isNotEmpty)
          _Section(
            title: 'Continue Watching',
            records: legacy.continueWatching,
            registry: registry,
          ),
        if (legacy.favorites.isNotEmpty)
          _Section(
            title: 'Favorites',
            records: legacy.favorites,
            registry: registry,
          ),
        if (legacy.history.isNotEmpty)
          _Section(
            title: 'History',
            records: legacy.history,
            registry: registry,
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

class _SectionV2 extends StatelessWidget {
  const _SectionV2({
    required this.title,
    required this.records,
    required this.registry,
  });

  final String title;
  final List<UserMediaStateV2> records;
  final ExtensionRegistry registry;

  @override
  Widget build(BuildContext context) {
    final portrait = records.any(
      (record) => record.item.artwork?.portrait != null,
    );
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
          height: portrait ? 260 : 172,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            itemCount: records.length,
            separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.md),
            itemBuilder: (context, index) => SizedBox(
              width: portrait ? 140 : 300,
              child: _RecordCardV2(record: records[index], registry: registry),
            ),
          ),
        ),
      ],
    );
  }
}

class _RecordCardV2 extends StatelessWidget {
  const _RecordCardV2({required this.record, required this.registry});

  final UserMediaStateV2 record;
  final ExtensionRegistry registry;

  bool get _available => registry.installed.any(
    (manifest) => manifest.id == record.ref.extensionId,
  );

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: _available ? 1 : 0.4,
    child: MediaCardV2(
      item: record.item,
      onTap: () => _available
          ? openVersionedItem(context, VersionedMediaItem(item: record.item))
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
