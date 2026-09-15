import 'dart:async';

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';

import '../app_scope.dart';
import '../addons/installer_controller.dart';
import '../catalog/category_page.dart';
import '../catalog/live_timeline_page.dart';
import '../catalog/plugin_selector.dart';
import '../search/search_page.dart';
import '../theme/breakpoints.dart';
import '../theme/tokens.dart';
import '../widgets/app_page_bar.dart';
import '../widgets/centered_content.dart';
import '../widgets/media_hero_layout.dart';
import '../widgets/media_hero_flexible_space.dart';
import 'catalog_grid_section.dart';
import 'catalog_group_shelf.dart';
import 'catalog_grouping.dart';
import 'catalog_shelf.dart';
import 'category_chips.dart';
import 'continue_watching_shelf.dart';
import 'featured_controller.dart';
import 'featured_hero.dart';
import 'live_now_shelf.dart';
import 'recommended_shelf.dart';
import 'surprise_me_banner.dart';
import 'top_ten_shelf.dart';
import '../settings/nsfw_controller.dart';

const _categoryHeaderAnimationDuration = Duration(milliseconds: 260);

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _showCategoryHeader = true;

  int _generation = 0;

  final ScrollController _scrollController = ScrollController();

  late final FeaturedController _featuredController;
  bool _featuredReady = false;
  String? _featuredSignature;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    if (_featuredReady) unawaited(_featuredController.close());
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_featuredReady) return;
    final scope = AppScope.of(context);
    _featuredController = FeaturedController(
      registry: scope.registry,
      catalogCache: scope.catalogCache,
      pluginController: scope.pluginController,
    );
    _featuredReady = true;
  }

  String _homeCategory(List<String> categories) {
    // Keep older extensions usable until they declare the Home category.
    return categories.contains('all') ? 'all' : categories.first;
  }

  void _openCategory(String category) {
    if (category.toLowerCase() == 'all') return;
    final scope = AppScope.of(context);
    final opensTimeline = scope.registry
        .catalogsFor(category)
        .any((binding) => binding.catalog.display == CatalogDisplay.timeline);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => opensTimeline
            ? CatalogTimelinePage(category: category)
            : CategoryPage(category: category),
      ),
    );
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    var showHeader = _showCategoryHeader;
    if (position.pixels <= position.minScrollExtent ||
        position.userScrollDirection == ScrollDirection.forward) {
      showHeader = true;
    } else if (position.userScrollDirection == ScrollDirection.reverse) {
      showHeader = false;
    }
    if (showHeader == _showCategoryHeader || !mounted) return;
    setState(() => _showCategoryHeader = showHeader);
  }

  void _selectPlugin(AppScope scope, String id) {
    scope.pluginController.select(id);
    _featuredSignature = null;
    unawaited(
      _featuredController.load(
        refresh: true,
        priorityCategory: _homeCategory(scope.registry.categories),
      ),
    );
  }

  void _ensureFeaturedLoaded(AppScope scope, List<String> categories) {
    final priorityCategory = _homeCategory(categories);
    final signature = [
      'priority:$priorityCategory',
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
    unawaited(_featuredController.load(priorityCategory: priorityCategory));
  }

  Future<void> _refresh() async {
    // Force-refreshes every category's catalogs, not just Home's one —
    // the Featured hero draws live/upcoming events from all of them, so a
    // category the viewer isn't looking at (e.g. "live") would otherwise keep
    // serving a stale session cache indefinitely and never surface a newly
    // live event. Home's shelves are covered by the same pass, so `_generation`
    // can bump straight off this cache once it lands.
    final categories = AppScope.of(context).registry.categories;
    final priorityCategory = categories.isEmpty
        ? null
        : _homeCategory(categories);
    await _featuredController.load(
      refresh: true,
      priorityCategory: priorityCategory,
    );
    if (!mounted) return;
    setState(() => _generation++);
  }

  Widget _catalogGroupSliver(HomeCatalogGroup group, String selected) {
    final key = ValueKey(
      '$_generation/$selected/${group.options.map((option) => '${option.binding.extensionId}/'
          '${option.binding.extension.manifest.version}/'
          '${option.binding.catalog.id}').join('|')}',
    );
    if (group.options.length > 1) {
      return CatalogGroupShelf(
        key: key,
        group: group,
        category: selected,
        scrollController: _scrollController,
        sliver: true,
      );
    }

    final binding = group.options.single.binding;
    if (binding.catalog.expanded) {
      return CatalogGridSection(
        key: key,
        binding: binding,
        category: selected,
        scrollController: _scrollController,
        sliver: true,
      );
    }
    return SliverToBoxAdapter(
      child: CenteredContent(
        child: CatalogShelf(key: key, binding: binding, category: selected),
      ),
    );
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
    final registry = scope.registry;
    final categories = registry.categories;
    final useRail =
        scope.deviceClass.isTv || AppBreakpoints.usesNavigationRail(context);

    if (categories.isEmpty) {
      return const Scaffold(
        appBar: AppPageBar(titleWidget: _HomeLogoTitle()),
        body: _NoExtensions(),
      );
    }

    _ensureFeaturedLoaded(scope, categories);

    final selected = _homeCategory(categories);
    final hasAllCategory = categories.any(
      (category) => category.toLowerCase() == 'all',
    );
    final categoryChoices = [
      for (final category in categories)
        if (category.toLowerCase() != 'all') category,
    ];

    final plugins = registry.pluginsFor(selected);
    final pluginId = scope.pluginController.resolve([
      for (final plugin in plugins) plugin.id,
    ]);
    final bindings = [
      for (final binding in registry.catalogsFor(selected))
        if (binding.extensionId == pluginId) binding,
    ];
    final groups = groupHomeCatalogs(bindings);
    return BlocBuilder<FeaturedController, FeaturedState>(
      bloc: _featuredController,
      builder: (context, featured) {
        final showFeatured = featured.items.isNotEmpty || featured.isLoading;
        final viewport = MediaQuery.sizeOf(context);
        final featuredHeight = !showFeatured
            ? null
            : MediaHeroLayout.heightForViewport(viewport) -
                  MediaQuery.paddingOf(context).top;
        return Scaffold(
          body: Stack(
            fit: StackFit.expand,
            children: [
              RefreshIndicator(
                onRefresh: _refresh,
                child: CustomScrollView(
                  key: bindings.isEmpty
                      ? null
                      : const Key('home-catalog-content'),
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
                                  kToolbarHeight +
                                  MediaQuery.paddingOf(context).top,
                              child: CenteredContent(
                                child: featured.items.isEmpty
                                    ? const FeaturedHeroPlaceholder()
                                    : FeaturedHero(items: featured.items),
                              ),
                            ),
                      backgroundColor: AppColors.surfaceDark,
                      foregroundColor: AppColors.onDark,
                      surfaceTintColor: Colors.transparent,
                      elevation: 0,
                      scrolledUnderElevation: 0,
                      centerTitle: false,
                      titleSpacing: AppSpacing.md,
                      title: const _HomeLogoTitle(),
                      actions: [
                        if (defaultTargetPlatform == TargetPlatform.macOS)
                          IconButton(
                            tooltip: 'Refresh',
                            icon: const Icon(Icons.refresh),
                            onPressed: _refresh,
                          ),
                        IconButton(
                          tooltip: 'Search',
                          icon: const Icon(Icons.search),
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              // Searching from the anime chip means searching
                              // anime: carry the browsing scope across.
                              builder: (_) =>
                                  SearchPage(initialScope: selected),
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
                    ),
                    if (selected.toLowerCase() == 'all')
                      SliverToBoxAdapter(
                        child: CenteredContent(
                          child: ContinueWatchingShelf(
                            controller: scope.libraryController,
                            registry: registry,
                          ),
                        ),
                      ),
                    if (selected.toLowerCase() == 'all')
                      SliverToBoxAdapter(
                        child: RecommendedShelf(
                          controller: scope.libraryController,
                          registry: registry,
                          catalogCache: scope.catalogCache,
                          refreshToken: _generation,
                        ),
                      ),
                    if (selected.toLowerCase() == 'all')
                      SliverToBoxAdapter(
                        child: TopTenShelf(
                          registry: registry,
                          catalogCache: scope.catalogCache,
                          refreshToken: _generation,
                        ),
                      ),
                    if (selected.toLowerCase() == 'all')
                      SliverToBoxAdapter(
                        child: SurpriseMeBanner(
                          registry: registry,
                          catalogCache: scope.catalogCache,
                          refreshToken: _generation,
                        ),
                      ),
                    if (selected.toLowerCase() == 'all')
                      SliverToBoxAdapter(
                        child: CenteredContent(
                          child: LiveNowShelf(
                            catalogCache: scope.catalogCache,
                            registry: registry,
                            refreshToken: _generation,
                          ),
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
                        sliver: SliverMainAxisGroup(
                          slivers: [
                            for (final group in groups)
                              _catalogGroupSliver(group, selected),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              if (categoryChoices.isNotEmpty && !useRail)
                Positioned(
                  top: MediaQuery.paddingOf(context).top + kToolbarHeight,
                  left: 0,
                  right: 0,
                  child: ClipRect(
                    child: AnimatedSlide(
                      key: const Key('home-category-header-animation'),
                      offset: _showCategoryHeader
                          ? Offset.zero
                          : const Offset(0, -1),
                      duration: _categoryHeaderAnimationDuration,
                      curve: Curves.easeInOutCubic,
                      child: AnimatedOpacity(
                        opacity: _showCategoryHeader ? 1 : 0,
                        duration: _categoryHeaderAnimationDuration,
                        curve: Curves.easeInOutCubic,
                        child: IgnorePointer(
                          ignoring: !_showCategoryHeader,
                          child: Material(
                            key: const Key('home-category-header'),
                            color: Colors.transparent,
                            child: SizedBox(
                              height: 48,
                              child: CenteredContent(
                                child: CategoryChips(
                                  categories: categoryChoices,
                                  // Home is the implicit `all` destination, so
                                  // no visible category chip is selected.
                                  selected: hasAllCategory ? '' : selected,
                                  onSelected: _openCategory,
                                  backgroundColor: AppColors.surfaceDarkElevated
                                      .withValues(alpha: 0.62),
                                  selectedColor: AppColors.onDark,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _HomeLogoTitle extends StatelessWidget {
  const _HomeLogoTitle();

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'fvcksubs',
    image: true,
    child: Image.asset(
      key: const Key('home-logo-title'),
      'assets/logo/logo_text.png',
      width: 96,
      height: 32,
      fit: BoxFit.contain,
      alignment: Alignment.centerLeft,
    ),
  );
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
