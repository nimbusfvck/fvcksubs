import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';

import '../app_scope.dart';
import '../addons/installer_controller.dart';
import '../catalog/plugin_selector.dart';
import '../search/search_page.dart';
import '../theme/tokens.dart';
import '../widgets/app_page_bar.dart';
import 'catalog_grid_section.dart';
import 'catalog_shelf.dart';
import 'category_chips.dart';
import 'continue_watching_shelf.dart';
import 'featured_controller.dart';
import 'featured_hero.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String? _selectedCategory;

  bool _restored = false;

  int _generation = 0;

  final ScrollController _scrollController = ScrollController();

  late final FeaturedController _featuredController;
  bool _featuredReady = false;
  String? _featuredSignature;

  @override
  void dispose() {
    _scrollController.dispose();
    if (_featuredReady) unawaited(_featuredController.close());
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_featuredReady) {
      final scope = AppScope.of(context);
      _featuredController = FeaturedController(
        registry: scope.registry,
        catalogCache: scope.catalogCache,
        pluginController: scope.pluginController,
      );
      _featuredReady = true;
    }
    if (_restored) return;
    _restored = true;
    _restore();
  }

  Future<void> _restore() async {
    final category = await AppScope.of(context).homeCategoryStore.load();
    if (!mounted) return;
    setState(() => _selectedCategory = category);
  }

  void _selectCategory(String category) {
    setState(() => _selectedCategory = category);
    unawaited(AppScope.of(context).homeCategoryStore.save(category));
  }

  void _selectPlugin(AppScope scope, String id) {
    scope.pluginController.select(id);
    _featuredSignature = null;
    unawaited(_featuredController.load(refresh: true));
  }

  void _ensureFeaturedLoaded(AppScope scope, List<String> categories) {
    final signature = [
      for (final category in categories) ...[
        category,
        for (final binding in scope.registry.catalogsFor(category))
          '${binding.extensionId}:${binding.extension.manifest.version}:'
              '${binding.catalog.id}',
        'selected:${scope.pluginController.resolve([for (final plugin in scope.registry.pluginsFor(category)) plugin.id])}',
      ],
    ].join('|');
    if (signature == _featuredSignature) return;
    _featuredSignature = signature;
    unawaited(_featuredController.load());
  }

  Future<void> _refresh(List<CatalogBinding> bindings, String category) async {
    final scope = AppScope.of(context);
    await Future.wait([
      for (final binding in bindings)
        scope.catalogCache
            .fetchCatalog(
              scope.registry,
              binding,
              category: category,
              refresh: true,
            )
            .then<void>((_) {}, onError: (_, _) {}),
    ]);
    // The selected category was refreshed above. Loading the feature feed from
    // cache keeps that result while avoiding a second request for the same
    // catalog.
    await _featuredController.load();
    if (!mounted) return;
    setState(() => _generation++);
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return BlocBuilder<InstallerController, InstallerState>(
      bloc: scope.installerController,
      builder: (context, _) => ListenableBuilder(
        listenable: scope.pluginController,
        builder: (context, _) => _body(context, scope),
      ),
    );
  }

  Widget _body(BuildContext context, AppScope scope) {
    final registry = scope.registry;
    final categories = registry.categories;

    if (categories.isEmpty) {
      return const Scaffold(
        appBar: AppPageBar(title: 'fvcksubs'),
        body: _NoExtensions(),
      );
    }

    _ensureFeaturedLoaded(scope, categories);

    final selected = categories.contains(_selectedCategory)
        ? _selectedCategory!
        : categories.first;

    final plugins = registry.pluginsFor(selected);
    final pluginId = scope.pluginController.resolve([
      for (final plugin in plugins) plugin.id,
    ]);
    final bindings = [
      for (final binding in registry.catalogsFor(selected))
        if (binding.extensionId == pluginId) binding,
    ];

    return BlocBuilder<FeaturedController, FeaturedState>(
      bloc: _featuredController,
      builder: (context, featured) => Scaffold(
        body: RefreshIndicator(
          onRefresh: () => _refresh(bindings, selected),
          child: CustomScrollView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverAppBar(
                expandedHeight: featured.items.isEmpty
                    ? null
                    : math.min(
                        560,
                        math.max(420, MediaQuery.sizeOf(context).height * 0.62),
                      ),
                pinned: true,
                floating: false,
                flexibleSpace: featured.items.isEmpty
                    ? null
                    : FeaturedHero(items: featured.items),
                backgroundColor: AppColors.surfaceDark,
                foregroundColor: AppColors.onDark,
                surfaceTintColor: Colors.transparent,
                elevation: 0,
                scrolledUnderElevation: 0,
                titleSpacing: AppSpacing.md,
                title: Text(
                  'fvcksubs',
                  style: AppTypography.titleLg.copyWith(
                    color: AppColors.onDark,
                  ),
                ),
                actions: [
                  IconButton(
                    tooltip: 'Search',
                    icon: const Icon(Icons.search),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const SearchPage(),
                      ),
                    ),
                  ),
                  if (plugins.length > 1 && pluginId != null)
                    PluginSelector(
                      plugins: plugins,
                      selectedId: pluginId,
                      onSelected: (id) => _selectPlugin(scope, id),
                    ),
                ],
                bottom: PreferredSize(
                  preferredSize: const Size.fromHeight(48),
                  child: SizedBox(
                    height: 48,
                    child: CategoryChips(
                      categories: categories,
                      selected: selected,
                      onSelected: _selectCategory,
                    ),
                  ),
                ),
              ),
              if (selected.toLowerCase() == 'all')
                SliverToBoxAdapter(
                  child: ContinueWatchingShelf(
                    controller: scope.libraryController,
                    registry: registry,
                  ),
                ),
              if (bindings.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptyCategory(category: selected),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate((context, i) {
                      final key = ValueKey(
                        '$_generation/$selected/${bindings[i].extensionId}/'
                        '${bindings[i].extension.manifest.version}/'
                        '${bindings[i].catalog.id}',
                      );
                      if (bindings[i].catalog.expanded) {
                        return CatalogGridSection(
                          key: key,
                          binding: bindings[i],
                          category: selected,
                          scrollController: _scrollController,
                        );
                      }
                      return CatalogShelf(
                        key: key,
                        binding: bindings[i],
                        category: selected,
                      );
                    }, childCount: bindings.length),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoExtensions extends StatelessWidget {
  const _NoExtensions();

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.extension_outlined,
            size: 48,
            color: AppColors.onDarkSoft,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'No extensions installed',
            style: AppTypography.titleMd.copyWith(color: AppColors.onDark),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Install an extension to see content here.',
            textAlign: TextAlign.center,
            style: AppTypography.bodySm.copyWith(color: AppColors.onDarkSoft),
          ),
        ],
      ),
    ),
  );
}

class _EmptyCategory extends StatelessWidget {
  const _EmptyCategory({required this.category});

  final String category;

  @override
  Widget build(BuildContext context) => Center(
    child: Text(
      'No catalogs in $category.',
      style: AppTypography.bodyMd.copyWith(color: AppColors.onDarkSoft),
    ),
  );
}
