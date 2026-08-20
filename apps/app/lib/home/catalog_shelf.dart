import 'package:flutter/material.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';

import '../app_scope.dart';
import '../catalog/catalog_screen.dart';
import '../catalog/media_card_v2.dart';
import '../catalog/media_grid_v2.dart';
import '../detail/open_versioned_item.dart';
import '../theme/tokens.dart';
import '../widgets/empty_state.dart';

class CatalogShelf extends StatefulWidget {
  const CatalogShelf({
    super.key,
    required this.binding,
    required this.category,
  });

  final CatalogBinding binding;

  final String category;

  static const int previewLimit = 6;

  static const int rowPreviewLimit = 10;

  static const int listPreviewLimit = 3;

  static int previewLimitFor(CatalogDisplay display) => switch (display) {
    CatalogDisplay.list => listPreviewLimit,
    CatalogDisplay.row => rowPreviewLimit,
    CatalogDisplay.grid => previewLimit,
  };

  @override
  State<CatalogShelf> createState() => _CatalogShelfState();
}

class _CatalogShelfState extends State<CatalogShelf> {
  Future<VersionedCatalogPage>? _future;

  VersionedCatalogPage? _cached;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_future != null) return;
    final scope = AppScope.of(context);
    _cached = scope.catalogCache.peekVersioned(widget.binding, widget.category);
    _future = _load();
  }

  Future<VersionedCatalogPage> _load() {
    final scope = AppScope.of(context);
    return scope.catalogCache.fetchCatalog(
      scope.registry,
      widget.binding,
      category: widget.category,
    );
  }

  void _reload() {
    final scope = AppScope.of(context);
    setState(() {
      _cached = null;
      _future = scope.catalogCache.fetchCatalog(
        scope.registry,
        widget.binding,
        category: widget.category,
        refresh: true,
      );
    });
  }

  void _open(VersionedMediaItem item) => openVersionedItem(context, item);

  void _openCatalog({String? subCategory, String? title}) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => CatalogScreen(
            binding: widget.binding,
            category: widget.category,
            subCategory: subCategory,
            title: title,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => FutureBuilder<VersionedCatalogPage>(
    future: _future,
    initialData: _cached,
    builder: (context, snapshot) {
      if (!snapshot.hasData &&
          snapshot.connectionState == ConnectionState.waiting) {
        return const _ShelfMessage(child: CircularProgressIndicator());
      }
      if (snapshot.hasError) {
        return _ShelfMessage(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "Couldn't load ${widget.binding.catalog.name}.",
                style: AppTypography.bodySm.copyWith(color: AppColors.error),
              ),
              TextButton(onPressed: _reload, child: const Text('Retry')),
            ],
          ),
        );
      }

      final page = snapshot.data;
      final items = page?.items ?? const <VersionedMediaItem>[];
      if (items.isEmpty) {
        final title = widget.category.toLowerCase() == 'all'
            ? _allSectionTitle(widget.binding)
            : widget.binding.catalog.name;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Header(title: title),
            const EmptyState(
              title: 'Nothing here right now.',
              icon: Icons.movie_filter_outlined,
            ),
          ],
        );
      }

      final idsByName = {
        for (final subCategory in page!.subCategories)
          subCategory.name: subCategory.id,
      };

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final section in page.sections)
            if (section.items.isNotEmpty)
              _Section(
                section: section,
                display: widget.binding.catalog.display,
                fallbackTitle: widget.binding.catalog.name,
                subCategoryId: section.title == null
                    ? null
                    : idsByName[section.title],
                onTap: _open,
                onSeeMore: (subCategory) => _openCatalog(
                  subCategory: subCategory,
                  title: section.title,
                ),
              ),
        ],
      );
    },
  );

  String _allSectionTitle(CatalogBinding binding) {
    final category = binding.catalog.categories.firstWhere(
      (value) => value.toLowerCase() != 'all',
      orElse: () => binding.catalog.name,
    );
    return category.isEmpty
        ? binding.catalog.name
        : '${category[0].toUpperCase()}${category.substring(1)}';
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.section,
    required this.display,
    required this.fallbackTitle,
    required this.subCategoryId,
    required this.onTap,
    required this.onSeeMore,
  });

  final CatalogSectionV2 section;
  final CatalogDisplay display;

  final String fallbackTitle;

  final String? subCategoryId;
  final ValueChanged<VersionedMediaItem> onTap;
  final ValueChanged<String?> onSeeMore;

  @override
  Widget build(BuildContext context) {
    final limit = CatalogShelf.previewLimitFor(display);
    final hasMore = section.items.length > limit;
    final preview = hasMore
        ? section.items.take(limit).toList()
        : section.items;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Header(
          title: section.title ?? fallbackTitle,
          onSeeMore: hasMore ? () => onSeeMore(subCategoryId) : null,
        ),
        switch (display) {
          CatalogDisplay.row => _Carousel(items: preview, onTap: onTap),
          CatalogDisplay.grid => MediaGridV2(
            sections: [CatalogSectionV2(id: section.id, items: preview)],
            onTap: onTap,
            scrollable: false,
          ),
          CatalogDisplay.list => MediaGridV2(
            sections: [CatalogSectionV2(id: section.id, items: preview)],
            onTap: onTap,
            scrollable: false,
            columns: 1,
          ),
        },
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title, this.onSeeMore});

  final String title;

  final VoidCallback? onSeeMore;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.md,
      AppSpacing.md,
      AppSpacing.xs,
      AppSpacing.xs,
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: AppTypography.titleMd.copyWith(color: AppColors.onDark),
          ),
        ),
        if (onSeeMore != null)
          TextButton(
            onPressed: onSeeMore,
            child: Text(
              'See more',
              style: AppTypography.titleSm.copyWith(
                color: AppColors.brandAccent,
              ),
            ),
          ),
      ],
    ),
  );
}

class _Carousel extends StatelessWidget {
  const _Carousel({required this.items, required this.onTap});

  final List<VersionedMediaItem> items;
  final ValueChanged<VersionedMediaItem> onTap;

  @override
  Widget build(BuildContext context) {
    final posterMode = items.any(
      (entry) => entry.item.artwork?.portrait != null,
    );
    final itemWidth = posterMode ? 140.0 : 300.0;
    final height = posterMode ? 260.0 : 172.0;

    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.md),
        itemBuilder: (context, i) => SizedBox(
          width: itemWidth,
          child: MediaCardV2(item: items[i].item, onTap: () => onTap(items[i])),
        ),
      ),
    );
  }
}

class _ShelfMessage extends StatelessWidget {
  const _ShelfMessage({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      SizedBox(height: 120, child: Center(child: child));
}
