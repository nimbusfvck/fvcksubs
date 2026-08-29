import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';
import 'package:fvcksubs_storage/fvcksubs_storage.dart';

import '../app_scope.dart';
import '../catalog/media_card_v2.dart';
import '../detail/open_versioned_item.dart';
import '../theme/tokens.dart';
import '../widgets/app_page_bar.dart';
import 'library_controller.dart';

class LibraryPage extends StatelessWidget {
  const LibraryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return Scaffold(
      appBar: const AppPageBar(title: 'Library'),
      body: BlocBuilder<LibraryController, LibraryState>(
        bloc: scope.libraryController,
        builder: (context, state) =>
            _LibraryContent(state: state, registry: scope.registry),
      ),
    );
  }
}

class _LibraryContent extends StatelessWidget {
  const _LibraryContent({required this.state, required this.registry});

  final LibraryState state;
  final ExtensionRegistry registry;

  @override
  Widget build(BuildContext context) {
    if (state.favorites.isEmpty) return const _EmptyLibrary();

    return ListView(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      children: [
        if (state.favorites.isNotEmpty)
          _Section(
            title: 'Favorites',
            records: state.favorites,
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
            Icons.favorite_border,
            size: 48,
            color: AppColors.onDarkSoft,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'No favorites yet',
            style: AppTypography.titleMd.copyWith(color: AppColors.onDark),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Save a title to find it here later.',
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
    final posterMode = records.any(
      (record) =>
          record.item.artwork?.portrait != null ||
          isMatchBannerItem(record.item),
    );
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
