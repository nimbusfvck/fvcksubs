import 'dart:async';

import 'package:flutter/material.dart';

import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';

import '../app_scope.dart';
import '../catalog/plugin_selector.dart';
import '../search/search_page.dart';
import '../theme/tokens.dart';
import 'catalog_grid_section.dart';
import 'catalog_shelf.dart';
import 'category_chips.dart';

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

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
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

  Future<void> _refresh(List<CatalogBinding> bindings, String category) async {
    final scope = AppScope.of(context);
    await Future.wait([
      for (final binding in bindings)
        scope.catalogCache
            .reload(scope.registry, binding, category: category)
            .then<void>((_) {}, onError: (_, _) {}),
    ]);
    if (!mounted) return;
    setState(() => _generation++);
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return ListenableBuilder(
      listenable: scope.pluginController,
      builder: (context, _) => _body(context, scope),
    );
  }

  Widget _body(BuildContext context, AppScope scope) {
    final registry = scope.registry;
    final categories = registry.categories;

    if (categories.isEmpty) return const _NoExtensions();

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

    return RefreshIndicator(
      onRefresh: () => _refresh(bindings, selected),
      child: CustomScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.xs,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'fvcksubs',
                        style: AppTypography.displaySm.copyWith(
                          color: AppColors.onDark,
                        ),
                      ),
                      if (plugins.length > 1 && pluginId != null)
                        PluginSelector(
                          plugins: plugins,
                          selectedId: pluginId,
                          onSelected: scope.pluginController.select,
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  SearchField(
                    enabled: false,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const SearchPage(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: CategoryChips(
              categories: categories,
              selected: selected,
              onSelected: _selectCategory,
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
