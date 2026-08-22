import 'package:flutter/material.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';

import '../app_scope.dart';
import '../detail/open_versioned_item.dart';
import '../theme/tokens.dart';
import 'catalog_filter_bar.dart';
import 'catalog_cache.dart';
import 'media_grid_v2.dart';
import 'sub_category_chips.dart';

class CatalogView extends StatefulWidget {
  const CatalogView({
    super.key,
    required this.binding,
    this.category,
    this.initialSubCategory,
  });

  final CatalogBinding binding;

  final String? category;

  final String? initialSubCategory;

  @override
  State<CatalogView> createState() => _CatalogViewState();
}

class _CatalogViewState extends State<CatalogView> {
  final ScrollController _scrollController = ScrollController();

  late Map<String, String> _filters = _defaultFilters();
  VersionedCatalogPage? _page;
  List<SubCategory> _subCategories = const [];
  late String? _subCategory = widget.initialSubCategory;
  String? _nextPage;
  bool _loading = true;
  bool _loadingMore = false;
  bool _started = false;
  Object? _error;

  Map<String, String> _defaultFilters() {
    if (!widget.binding.catalog.filters.contains('date')) return const {};
    return {'date': _today()};
  }

  static String _today() {
    final now = DateTime.now();
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    return '${now.year}-$month-$day';
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _load();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_loadingMore || _nextPage == null || !_scrollController.hasClients) {
      return;
    }
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 400) {
      _loadMore();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await AppScope.of(context).registry.loadCatalog(
        widget.binding,
        category: widget.category,
        filters: _filters,
        subCategory: _subCategory,
      );
      if (!mounted) return;
      setState(() {
        _page = page;
        _nextPage = page.nextPage;
        _subCategories = page.subCategories;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    setState(() => _loadingMore = true);
    try {
      final page = await AppScope.of(context).registry.loadCatalog(
        widget.binding,
        category: widget.category,
        page: _nextPage,
        filters: _filters,
        subCategory: _subCategory,
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

  void _onFilterChanged(String key, String value) {
    setState(() {
      _filters = {..._filters, key: value};
      _page = null;
      _nextPage = null;
    });
    _load();
  }

  void _onSubCategorySelected(String? id) {
    if (id == _subCategory) return;
    setState(() {
      _subCategory = id;
      _page = null;
      _nextPage = null;
    });
    _load();
  }

  void _open(VersionedMediaItem item) => openVersionedItem(context, item);

  void _openWithHero(VersionedMediaItem item, Object heroTag) =>
      openVersionedItem(context, item, heroTag: heroTag);

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (widget.binding.catalog.filters.isNotEmpty)
        CatalogFilterBar(
          filterKeys: widget.binding.catalog.filters,
          values: _filters,
          onChanged: _onFilterChanged,
        ),
      if (_subCategories.isNotEmpty && widget.initialSubCategory == null)
        SubCategoryChips(
          subCategories: _subCategories,
          selected: _subCategory,
          onSelected: _onSubCategorySelected,
        ),
      Expanded(child: _body()),
    ],
  );

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "Couldn't load ${widget.binding.catalog.name}.",
              style: AppTypography.bodyMd.copyWith(color: AppColors.error),
            ),
            TextButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }
    final page = _page;
    if (page == null || page.items.isEmpty) {
      return Center(
        child: Text(
          'Nothing here right now.',
          style: AppTypography.bodyMd.copyWith(color: AppColors.onDarkSoft),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Column(
        children: [
          Expanded(
            child: MediaGridV2(
              sections: page.sections,
              onTap: _open,
              onTapWithHero: _openWithHero,
              controller: _scrollController,
              showSectionHeaders: true,
              columns: widget.binding.catalog.display == CatalogDisplay.list
                  ? 1
                  : null,
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
      ),
    );
  }
}
