import 'package:flutter/material.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';

import '../app_scope.dart';
import '../catalog/media_grid.dart';
import '../detail/open_item.dart';
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
  List<MediaItem> _items = const [];
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
    ).catalogCache.peek(widget.binding, widget.category);
    if (cached != null) {
      _items = cached.items;
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
      final page = await scope.catalogCache.load(
        scope.registry,
        widget.binding,
        category: widget.category,
      );
      if (!mounted) return;
      setState(() {
        _items = page.items;
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
      final page = await AppScope.of(context).registry.loadCatalog(
        widget.binding,
        category: widget.category,
        page: _nextPage,
      );
      if (!mounted) return;
      setState(() {
        _items = [..._items, ...page.items];
        _nextPage = page.nextPage;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  void _open(MediaItem item) => openItem(context, item);

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
    if (_items.isEmpty) {
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
        MediaGrid(items: _items, onTap: _open, scrollable: false),
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
