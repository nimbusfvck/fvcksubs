import 'package:flutter/material.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';

import '../app_scope.dart';
import '../catalog/catalog_screen.dart';
import '../catalog/media_card.dart';
import '../catalog/media_grid.dart';
import '../detail/open_item.dart';
import '../theme/tokens.dart';

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
  Future<CatalogPage>? _future;

  CatalogPage? _cached;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_future != null) return;
    final scope = AppScope.of(context);
    _cached = scope.catalogCache.peek(widget.binding, widget.category);
    _future = _load();
  }

  Future<CatalogPage> _load() {
    final scope = AppScope.of(context);
    return scope.catalogCache.load(
      scope.registry,
      widget.binding,
      category: widget.category,
    );
  }

  void _reload() {
    final scope = AppScope.of(context);
    setState(() {
      _cached = null;
      _future = scope.catalogCache.reload(
        scope.registry,
        widget.binding,
        category: widget.category,
      );
    });
  }

  void _open(MediaItem item) => openItem(context, item);

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
  Widget build(BuildContext context) => FutureBuilder<CatalogPage>(
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
      final items = page?.items ?? const <MediaItem>[];
      if (items.isEmpty) {
        return _ShelfMessage(
          child: Text(
            'Nothing here right now.',
            style: AppTypography.bodySm.copyWith(color: AppColors.onDarkSoft),
          ),
        );
      }

      final idsByName = {
        for (final subCategory in page!.subCategories)
          subCategory.name: subCategory.id,
      };

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final group in MediaGrid.groupsOf(items))
            _Section(
              group: group,
              display: widget.binding.catalog.display,
              fallbackTitle: widget.binding.catalog.name,
              subCategoryId: group.label == null
                  ? null
                  : idsByName[group.label],
              onTap: _open,
              onSeeMore: (subCategory) =>
                  _openCatalog(subCategory: subCategory, title: group.label),
            ),
        ],
      );
    },
  );
}

class _Section extends StatelessWidget {
  const _Section({
    required this.group,
    required this.display,
    required this.fallbackTitle,
    required this.subCategoryId,
    required this.onTap,
    required this.onSeeMore,
  });

  final MediaGroup group;
  final CatalogDisplay display;

  final String fallbackTitle;

  final String? subCategoryId;
  final ValueChanged<MediaItem> onTap;
  final ValueChanged<String?> onSeeMore;

  @override
  Widget build(BuildContext context) {
    final limit = CatalogShelf.previewLimitFor(display);
    final hasMore = group.items.length > limit;
    final preview = hasMore ? group.items.take(limit).toList() : group.items;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Header(
          title: group.label ?? fallbackTitle,
          onSeeMore: hasMore ? () => onSeeMore(subCategoryId) : null,
        ),
        switch (display) {
          CatalogDisplay.row => _Carousel(items: preview, onTap: onTap),
          CatalogDisplay.grid => MediaGrid(
            items: preview,
            onTap: onTap,
            scrollable: false,
          ),
          CatalogDisplay.list => MediaGrid(
            items: preview,
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

  final List<MediaItem> items;
  final ValueChanged<MediaItem> onTap;

  @override
  Widget build(BuildContext context) {
    final posterMode = items.any((item) => item.poster != null);
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
          child: MediaCard(item: items[i], onTap: () => onTap(items[i])),
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
