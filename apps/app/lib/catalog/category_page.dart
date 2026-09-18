import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';

import '../addons/installer_controller.dart';
import '../app_scope.dart';
import '../home/catalog_grid_section.dart';
import '../home/catalog_group_shelf.dart';
import '../home/catalog_grouping.dart';
import '../home/catalog_shelf.dart';
import '../home/featured_controller.dart';
import '../home/featured_hero.dart';
import '../settings/nsfw_controller.dart';
import '../theme/tokens.dart';
import '../widgets/centered_content.dart';
import '../widgets/media_hero_flexible_space.dart';
import '../widgets/media_hero_layout.dart';
import 'plugin_selector.dart';

/// Full-screen browsing for one of Home's non-[all] categories.
class CategoryPage extends StatefulWidget {
  const CategoryPage({super.key, required this.category});

  final String category;

  @override
  State<CategoryPage> createState() => _CategoryPageState();
}

class _CategoryPageState extends State<CategoryPage> {
  final ScrollController _scrollController = ScrollController();
  int _generation = 0;
  String? _featuredSignature;
  List<VersionedMediaItem> _featuredItems = const [];

  Future<void> _refresh() async {
    final scope = AppScope.of(context);
    final plugins = scope.registry.pluginsFor(widget.category);
    final pluginId = scope.pluginController.resolve([
      for (final plugin in plugins) plugin.id,
    ]);
    final bindings = [
      for (final binding in scope.registry.catalogsFor(widget.category))
        if (binding.extensionId == pluginId) binding,
    ];
    await Future.wait([
      for (final binding in bindings) _refreshBinding(scope, binding),
    ]);
    if (!mounted) return;
    setState(() => _generation++);
  }

  Future<void> _refreshBinding(AppScope scope, CatalogBinding binding) async {
    try {
      await scope.catalogCache.reload(
        scope.registry,
        binding,
        category: widget.category,
      );
    } catch (_) {
      // Keep the current catalog visible when one refresh fails.
    }
  }

  void _selectPlugin(AppScope scope, String id) {
    scope.pluginController.select(id);
    setState(() {
      _generation++;
      _featuredSignature = null;
      _featuredItems = const [];
    });
  }

  void _ensureFeaturedLoaded(AppScope scope, List<CatalogBinding> bindings) {
    final signature =
        '$_generation/${widget.category}/${bindings.map((binding) => '${binding.extensionId}/'
            '${binding.extension.manifest.version}/'
            '${binding.catalog.id}').join('|')}';
    if (signature == _featuredSignature) return;
    _featuredSignature = signature;
    unawaited(_loadFeatured(scope, bindings, signature));
  }

  Future<void> _loadFeatured(
    AppScope scope,
    List<CatalogBinding> bindings,
    String signature,
  ) async {
    final pages = <VersionedCatalogPage>[];
    for (final binding in bindings) {
      try {
        pages.add(
          await scope.catalogCache.fetchCatalog(
            scope.registry,
            binding,
            category: widget.category,
          ),
        );
      } catch (_) {
        // The category content remains usable when one catalog fails.
      }
    }
    if (!mounted || signature != _featuredSignature) return;
    setState(() {
      _featuredItems = FeaturedAlgorithm.selectPages(pages);
    });
  }

  Widget _catalogGroupSliver(HomeCatalogGroup group, String pluginId) {
    final key = ValueKey(
      '$_generation/${widget.category}/$pluginId/${group.options.map((option) => '${option.binding.extensionId}/'
          '${option.binding.extension.manifest.version}/'
          '${option.binding.catalog.id}').join('|')}',
    );
    if (group.options.length > 1) {
      return CatalogGroupShelf(
        key: key,
        group: group,
        category: widget.category,
        scrollController: _scrollController,
        sliver: true,
      );
    }

    final binding = group.options.single.binding;
    if (binding.catalog.expanded) {
      return CatalogGridSection(
        key: key,
        binding: binding,
        category: widget.category,
        scrollController: _scrollController,
        sliver: true,
        eagerLoad: true,
      );
    }
    return SliverToBoxAdapter(
      child: CenteredContent(
        child: CatalogShelf(
          key: key,
          binding: binding,
          category: widget.category,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return BlocBuilder<InstallerController, InstallerState>(
      bloc: scope.installerController,
      builder: (context, _) => BlocBuilder<NsfwController, NsfwState>(
        bloc: scope.nsfwController,
        builder: (context, _) => ListenableBuilder(
          listenable: scope.pluginController,
          builder: (context, _) => _body(context, scope),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, AppScope scope) {
    final plugins = scope.registry.pluginsFor(widget.category);
    final pluginId = scope.pluginController.resolve([
      for (final plugin in plugins) plugin.id,
    ]);
    final bindings = [
      for (final binding in scope.registry.catalogsFor(widget.category))
        if (binding.extensionId == pluginId) binding,
    ];
    final groups = groupHomeCatalogs(bindings);
    _ensureFeaturedLoaded(scope, bindings);
    final featuredHeight = _featuredItems.isEmpty
        ? null
        : MediaHeroLayout.snapToDevicePixel(
            context,
            MediaHeroLayout.heightForViewport(MediaQuery.sizeOf(context)) -
                MediaQuery.paddingOf(context).top,
          );

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: CustomScrollView(
          key: const Key('category-page-content'),
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverAppBar(
              expandedHeight: featuredHeight,
              pinned: true,
              floating: false,
              flexibleSpace: featuredHeight == null
                  ? null
                  : MediaHeroFlexibleSpace(
                      expandedHeight: featuredHeight,
                      collapsedHeight:
                          kToolbarHeight + MediaQuery.paddingOf(context).top,
                      child: CenteredContent(
                        child: FeaturedHero(items: _featuredItems),
                      ),
                    ),
              backgroundColor: AppColors.surfaceDark,
              foregroundColor: AppColors.onDark,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              scrolledUnderElevation: 0,
              centerTitle: false,
              titleSpacing: AppSpacing.md,
              title: Text(
                _categoryLabel(widget.category),
                style: AppTypography.titleLg.copyWith(color: AppColors.onDark),
              ),
              actions: [
                if (plugins.length > 1 && pluginId != null)
                  PluginSelector(
                    plugins: plugins,
                    selectedId: pluginId,
                    onSelected: (id) => _selectPlugin(scope, id),
                  ),
              ],
            ),
            if (bindings.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _EmptyCategory(category: widget.category),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                sliver: SliverMainAxisGroup(
                  slivers: [
                    for (final group in groups)
                      _catalogGroupSliver(group, pluginId ?? ''),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _EmptyCategory extends StatelessWidget {
  const _EmptyCategory({required this.category});

  final String category;

  @override
  Widget build(BuildContext context) => Center(
    child: Text(
      'No catalogs in ${_categoryLabel(category)}.',
      style: AppTypography.bodyMd.copyWith(color: AppColors.onDarkSoft),
    ),
  );
}

String _categoryLabel(String category) {
  if (category.toLowerCase() == 'tv') return 'Shows';
  if (category.toLowerCase() == 'movie') return 'Movies';
  return category.isEmpty
      ? category
      : category[0].toUpperCase() + category.substring(1);
}
