import 'dart:async';

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
import 'catalog_shimmer.dart';
import 'catalog_grouping.dart';
import 'grouped_header.dart';

class CatalogShelf extends StatefulWidget {
  const CatalogShelf({
    super.key,
    required this.binding,
    required this.category,
    this.showCatalogHeader = true,
  });

  final CatalogBinding binding;

  final String category;

  /// Hides the fallback catalog title when a parent renders a group header.
  /// Explicit response section titles remain visible.
  final bool showCatalogHeader;

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
    if (_cached != null) {
      scope.registry.rememberCatalogPage(widget.binding, _cached!);
    }
    _future = _load();
  }

  Future<VersionedCatalogPage> _load() {
    final scope = AppScope.of(context);
    final cached = _cached;
    if (cached != null) return Future<VersionedCatalogPage>.value(cached);
    return _loadPersistedOrFresh(scope);
  }

  Future<VersionedCatalogPage> _loadPersistedOrFresh(AppScope scope) async {
    final persisted = await scope.catalogCache.readPersistedVersioned(
      widget.binding,
      widget.category,
    );
    if (persisted != null) {
      scope.registry.rememberCatalogPage(widget.binding, persisted);
      unawaited(_refreshPersisted(scope));
      return persisted;
    }
    return scope.catalogCache.fetchCatalog(
      scope.registry,
      widget.binding,
      category: widget.category,
    );
  }

  Future<void> _refreshPersisted(AppScope scope) async {
    try {
      final fresh = await scope.catalogCache.reload(
        scope.registry,
        widget.binding,
        category: widget.category,
      );
      if (!mounted) return;
      setState(() {
        _cached = fresh;
        _future = Future<VersionedCatalogPage>.value(fresh);
      });
    } catch (_) {
      // Keep the persisted catalog visible when a background refresh fails.
    }
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

  void _open(VersionedMediaItem item) => openVersionedItem(
    context,
    item,
    contentRating: widget.binding.contentRating,
  );

  void _openWithHero(VersionedMediaItem item, Object heroTag) =>
      openVersionedItem(
        context,
        item,
        heroTag: heroTag,
        contentRating: widget.binding.contentRating,
      );

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
        return CatalogShimmer(display: widget.binding.catalog.display);
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
        if (widget.category.toLowerCase() != 'all') {
          return const EmptyState(
            title: 'Nothing here right now.',
            icon: Icons.movie_filter_outlined,
          );
        }
        final title = _allSectionTitle(widget.binding);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.showCatalogHeader) _Header(title: title),
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
      final sections = [
        for (final section in page.sections)
          if (section.items.isNotEmpty) section,
      ];
      final groups = groupHomeSections(sections);

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final group in groups)
            if (group.options.length > 1)
              _SectionGroup(
                key: ValueKey(
                  'section-group:${group.options.map((option) => option.section.id).join('|')}',
                ),
                group: group,
                display: widget.binding.catalog.display,
                idsByName: idsByName,
                onTap: _open,
                onTapWithHero: _openWithHero,
                onSeeMore: (section) => _openCatalog(
                  subCategory: section.title == null
                      ? null
                      : idsByName[section.title],
                  title: section.title,
                ),
              )
            else
              _Section(
                section: group.options.single.section,
                display: widget.binding.catalog.display,
                fallbackTitle: widget.binding.catalog.name,
                showCatalogHeader: widget.showCatalogHeader,
                subCategoryId: group.options.single.section.title == null
                    ? null
                    : idsByName[group.options.single.section.title],
                onTap: _open,
                onTapWithHero: _openWithHero,
                onSeeMore: (subCategory) => _openCatalog(
                  subCategory: subCategory,
                  title: group.options.single.section.title,
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
    required this.showCatalogHeader,
    this.showHeader = true,
    required this.subCategoryId,
    required this.onTap,
    required this.onTapWithHero,
    required this.onSeeMore,
  });

  final CatalogSectionV2 section;
  final CatalogDisplay display;

  final String fallbackTitle;
  final bool showCatalogHeader;
  final bool showHeader;

  final String? subCategoryId;
  final ValueChanged<VersionedMediaItem> onTap;
  final void Function(VersionedMediaItem, Object) onTapWithHero;
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
        if (showHeader && (section.title != null || showCatalogHeader))
          _Header(
            title: section.title ?? fallbackTitle,
            onSeeMore: hasMore ? () => onSeeMore(subCategoryId) : null,
          ),
        switch (display) {
          CatalogDisplay.row => _Carousel(
            items: preview,
            onTap: onTap,
            onTapWithHero: onTapWithHero,
          ),
          CatalogDisplay.grid => MediaGridV2(
            sections: [CatalogSectionV2(id: section.id, items: preview)],
            onTap: onTap,
            onTapWithHero: onTapWithHero,
            scrollable: false,
          ),
          CatalogDisplay.list => MediaGridV2(
            sections: [CatalogSectionV2(id: section.id, items: preview)],
            onTap: onTap,
            onTapWithHero: onTapWithHero,
            scrollable: false,
            columns: 1,
          ),
        },
      ],
    );
  }
}

class _SectionGroup extends StatefulWidget {
  const _SectionGroup({
    super.key,
    required this.group,
    required this.display,
    required this.idsByName,
    required this.onTap,
    required this.onTapWithHero,
    required this.onSeeMore,
  });

  final HomeSectionGroup group;
  final CatalogDisplay display;
  final Map<String, String> idsByName;
  final ValueChanged<VersionedMediaItem> onTap;
  final void Function(VersionedMediaItem, Object) onTapWithHero;
  final ValueChanged<CatalogSectionV2> onSeeMore;

  @override
  State<_SectionGroup> createState() => _SectionGroupState();
}

class _SectionGroupState extends State<_SectionGroup> {
  int _selectedIndex = 0;

  HomeSectionOption get _selected => widget.group.options[_selectedIndex];

  @override
  Widget build(BuildContext context) {
    final section = _selected.section;
    final limit = CatalogShelf.previewLimitFor(widget.display);
    final hasMore = section.items.length > limit;
    final preview = hasMore
        ? section.items.take(limit).toList()
        : section.items;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GroupedHeader(
          title: widget.group.title,
          options: [for (final option in widget.group.options) option.label],
          selectedIndex: _selectedIndex,
          onSelected: (index) => setState(() => _selectedIndex = index),
          onSeeMore: hasMore ? () => widget.onSeeMore(section) : null,
        ),
        _Section(
          section: CatalogSectionV2(id: section.id, items: preview),
          display: widget.display,
          fallbackTitle: widget.group.title,
          showCatalogHeader: false,
          showHeader: false,
          subCategoryId: section.title == null
              ? null
              : widget.idsByName[section.title],
          onTap: widget.onTap,
          onTapWithHero: widget.onTapWithHero,
          onSeeMore: (_) => widget.onSeeMore(section),
        ),
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
  const _Carousel({
    required this.items,
    required this.onTap,
    required this.onTapWithHero,
  });

  final List<VersionedMediaItem> items;
  final ValueChanged<VersionedMediaItem> onTap;
  final void Function(VersionedMediaItem, Object) onTapWithHero;

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
        itemBuilder: (context, i) {
          final item = items[i];
          final heroTag = Object();
          return SizedBox(
            width: itemWidth,
            child: MediaCardV2(
              item: item.item,
              heroTag: heroTag,
              onTap: () => onTapWithHero(item, heroTag),
            ),
          );
        },
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
