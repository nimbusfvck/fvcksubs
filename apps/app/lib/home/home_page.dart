import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../app_scope.dart';
import '../addons/installer_controller.dart';
import '../catalog/plugin_selector.dart';
import '../search/search_page.dart';
import '../theme/tokens.dart';
import '../widgets/app_page_bar.dart';
import '../widgets/centered_content.dart';
import 'catalog_grid_section.dart';
import 'catalog_group_shelf.dart';
import 'catalog_grouping.dart';
import 'catalog_shelf.dart';
import 'category_chips.dart';
import 'continue_watching_shelf.dart';
import 'featured_controller.dart';
import 'featured_hero.dart';
import '../settings/nsfw_controller.dart';

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
    unawaited(
      _featuredController.load(
        refresh: true,
        priorityCategory: _selectedCategory,
      ),
    );
  }

  void _ensureFeaturedLoaded(AppScope scope, List<String> categories) {
    final priorityCategory = categories.contains(_selectedCategory)
        ? _selectedCategory
        : categories.first;
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
    // Force-refreshes every category's catalogs, not just the selected one —
    // the Featured hero draws live/upcoming events from all of them, so a
    // category the viewer isn't looking at (e.g. "live") would otherwise keep
    // serving a stale session cache indefinitely and never surface a newly
    // live event. The selected category's shelves are covered by the same
    // pass, so `_generation` can bump straight off this cache once it lands.
    final categories = AppScope.of(context).registry.categories;
    final priorityCategory = categories.contains(_selectedCategory)
        ? _selectedCategory
        : (categories.isEmpty ? null : categories.first);
    await _featuredController.load(
      refresh: true,
      priorityCategory: priorityCategory,
    );
    if (!mounted) return;
    setState(() => _generation++);
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

    if (categories.isEmpty) {
      return const Scaffold(
        appBar: AppPageBar(titleWidget: _HomeLogoTitle()),
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
    final groups = groupHomeCatalogs(bindings);
    return BlocBuilder<FeaturedController, FeaturedState>(
      bloc: _featuredController,
      builder: (context, featured) {
        final showFeatured = featured.items.isNotEmpty || featured.isLoading;
        final featuredHeight = !showFeatured
            ? null
            : math
                  .min(
                    480,
                    math.max(420, MediaQuery.sizeOf(context).height * 0.52),
                  )
                  .toDouble();
        return Scaffold(
          body: RefreshIndicator(
            onRefresh: _refresh,
            child: CustomScrollView(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverAppBar(
                  expandedHeight: featuredHeight,
                  pinned: true,
                  floating: false,
                  flexibleSpace: featuredHeight == null
                      ? null
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            final minHeight =
                                MediaQuery.paddingOf(context).top +
                                kToolbarHeight;
                            final range = math.max(
                              1,
                              featuredHeight - minHeight,
                            );
                            final progress =
                                ((constraints.maxHeight - minHeight) / range)
                                    .clamp(0.0, 1.0)
                                    .toDouble();
                            return CenteredContent(
                              child: IgnorePointer(
                                ignoring: progress < 0.5,
                                child: Opacity(
                                  opacity: progress,
                                  child: featured.items.isEmpty
                                      ? const FeaturedHeroPlaceholder()
                                      : FeaturedHero(items: featured.items),
                                ),
                              ),
                            );
                          },
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
                          builder: (_) => SearchPage(initialScope: selected),
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
                SliverPersistentHeader(
                  key: const Key('home-category-header'),
                  pinned: true,
                  delegate: _CategoryHeaderDelegate(
                    categories: categories,
                    selected: selected,
                    onSelected: _selectCategory,
                  ),
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
                if (bindings.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyCategory(category: selected),
                  )
                else
                  SliverPadding(
                    key: const Key('home-catalog-content'),
                    padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate((context, i) {
                        final group = groups[i];
                        final key = ValueKey(
                          '$_generation/$selected/${group.options.map((option) => '${option.binding.extensionId}/'
                              '${option.binding.extension.manifest.version}/'
                              '${option.binding.catalog.id}').join('|')}',
                        );
                        if (group.options.length > 1) {
                          return CenteredContent(
                            child: CatalogGroupShelf(
                              key: key,
                              group: group,
                              category: selected,
                              scrollController: _scrollController,
                            ),
                          );
                        }
                        final binding = group.options.single.binding;
                        if (binding.catalog.expanded) {
                          return CenteredContent(
                            child: CatalogGridSection(
                              key: key,
                              binding: binding,
                              category: selected,
                              scrollController: _scrollController,
                            ),
                          );
                        }
                        return CenteredContent(
                          child: CatalogShelf(
                            key: key,
                            binding: binding,
                            category: selected,
                          ),
                        );
                      }, childCount: groups.length),
                    ),
                  ),
              ],
            ),
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

class _CategoryHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _CategoryHeaderDelegate({
    required this.categories,
    required this.selected,
    required this.onSelected,
  });

  final List<String> categories;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  double get minExtent => 48;

  @override
  double get maxExtent => 48;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => Material(
    color: AppColors.surfaceDark,
    elevation: overlapsContent ? 2 : 0,
    child: SizedBox(
      height: 48,
      child: CenteredContent(
        child: CategoryChips(
          categories: categories,
          selected: selected,
          onSelected: onSelected,
        ),
      ),
    ),
  );

  @override
  bool shouldRebuild(covariant _CategoryHeaderDelegate oldDelegate) =>
      oldDelegate.categories != categories ||
      oldDelegate.selected != selected ||
      oldDelegate.onSelected != onSelected;
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
