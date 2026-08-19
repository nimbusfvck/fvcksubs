import 'package:flutter/material.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';

import '../app_scope.dart';
import '../catalog/catalog_cache.dart';
import '../catalog/media_grid_v2.dart';
import '../detail/open_versioned_item.dart';
import '../theme/tokens.dart';

class CatalogGridSection extends StatefulWidget {
  const CatalogGridSection({
    super.key,
    required this.binding,
    required this.category,
    required this.scrollController,
  });

  final CatalogBinding binding;

  final String category;

  final ScrollController scrollController;

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
    final cached = AppScope.of(
      context,
    ).catalogCache.peekVersioned(widget.binding, widget.category);
    if (cached != null) {
      _page = cached;
      _nextPage = cached.nextPage;
      _loading = false;
    }
    _load();
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_onScroll);
    super.dispose();
  }

  Future<void> _load() async {
    final scope = AppScope.of(context);
    try {
      final page = await scope.catalogCache.loadVersioned(
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
      final page = await AppScope.of(context).registry.loadCatalogVersioned(
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

  void _open(VersionedMediaItem item) => openVersionedItem(context, item);

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
        child: Center(child: CircularProgressIndicator()),
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
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
        child: Center(
          child: Text(
            'Nothing here right now.',
            style: AppTypography.bodySm.copyWith(color: AppColors.onDarkSoft),
          ),
        ),
      );
    }
    return Column(
      children: [
        MediaGridV2(sections: page.sections, onTap: _open, scrollable: false),
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
