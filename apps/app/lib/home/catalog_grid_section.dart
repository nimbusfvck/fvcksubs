import 'dart:async';

import 'package:flutter/material.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';

import '../app_scope.dart';
import '../catalog/catalog_cache.dart';
import '../catalog/media_grid_v2.dart';
import '../detail/open_versioned_item.dart';
import '../theme/tokens.dart';
import '../widgets/empty_state.dart';
import 'catalog_shimmer.dart';

class CatalogGridSection extends StatefulWidget {
  const CatalogGridSection({
    super.key,
    required this.binding,
    required this.category,
    required this.scrollController,
    this.showCatalogTitle = true,
  });

  final CatalogBinding binding;

  final String category;

  final ScrollController scrollController;

  final bool showCatalogTitle;

  @override
  State<CatalogGridSection> createState() => _CatalogGridSectionState();
}

class _CatalogGridSectionState extends State<CatalogGridSection> {
  VersionedCatalogPage? _page;
  String? _nextPage;
  bool _loading = true;
  bool _loadingMore = false;
  Object? _error;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    widget.scrollController.addListener(_onScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final scope = AppScope.of(context);
    final cached = scope.catalogCache.peekVersioned(
      widget.binding,
      widget.category,
    );
    if (cached != null) {
      scope.registry.rememberCatalogPage(widget.binding, cached);
      _page = cached;
      _nextPage = cached.nextPage;
      _loading = false;
      return;
    }
    unawaited(_loadPersistedOrFresh());
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_onScroll);
    super.dispose();
  }

  Future<void> _load() async {
    final scope = AppScope.of(context);
    try {
      final page = await scope.catalogCache.fetchCatalog(
        scope.registry,
        widget.binding,
        category: widget.category,
      );
      if (!mounted) return;
      setState(() {
        _page = page;
        _nextPage = page.nextPage;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _loadPersistedOrFresh() async {
    final scope = AppScope.of(context);
    final persisted = await scope.catalogCache.readPersistedVersioned(
      widget.binding,
      widget.category,
    );
    if (persisted == null) {
      await _load();
      return;
    }
    scope.registry.rememberCatalogPage(widget.binding, persisted);
    if (!mounted) return;
    setState(() {
      _page = persisted;
      _nextPage = persisted.nextPage;
      _loading = false;
      _error = null;
    });
    unawaited(_refreshPersisted(scope));
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
        _page = fresh;
        _nextPage = fresh.nextPage;
        _error = null;
      });
    } catch (_) {
      // Keep the persisted grid visible when a background refresh fails.
    }
  }

  void _onScroll() {
    if (_loadingMore ||
        _nextPage == null ||
        !widget.scrollController.hasClients) {
      return;
    }
    final position = widget.scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 400) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    setState(() => _loadingMore = true);
    try {
      final page = await AppScope.of(context).registry.loadCatalog(
        widget.binding,
        category: widget.category,
        page: _nextPage,
      );
      if (!mounted) return;
      setState(() {
        _page = _page == null ? page : mergeVersionedCatalogPages(_page!, page);
        _nextPage = page.nextPage;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return CatalogShimmer(
        display: widget.binding.catalog.display,
        sections: 1,
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "Couldn't load ${widget.binding.catalog.name}.",
                style: AppTypography.bodySm.copyWith(color: AppColors.error),
              ),
              TextButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    final page = _page;
    if (page == null || page.items.isEmpty) {
      if (widget.category.toLowerCase() != 'all') {
        return const EmptyState(
          title: 'Nothing here right now.',
          icon: Icons.movie_filter_outlined,
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.showCatalogTitle)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.xs,
              ),
              child: Text(
                widget.binding.catalog.name,
                style: AppTypography.titleMd.copyWith(color: AppColors.onDark),
              ),
            ),
          const EmptyState(
            title: 'Nothing here right now.',
            icon: Icons.movie_filter_outlined,
          ),
        ],
      );
    }
    return Column(
      children: [
        MediaGridV2(
          sections: page.sections,
          onTap: _open,
          onTapWithHero: _openWithHero,
          scrollable: false,
          // Preserve section labels for catalogs that split a large feed into
          // named groups, while keeping flat catalogs as a plain grid.
          showSectionHeaders: page.sections.any(
            (section) => section.title != null,
          ),
        ),
        if (_loadingMore)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
      ],
    );
  }
}
