import 'dart:async';

import 'package:flutter/material.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';

import '../app_scope.dart';
import '../catalog/catalog_cache.dart';
import '../catalog/media_card_v2.dart';
import '../detail/open_versioned_item.dart';
import '../theme/tokens.dart';
import '../widgets/clickable.dart';
import '../widgets/centered_content.dart';

const _topTenCategoryAliases = [
  ['movie', 'movies'],
  ['tv', 'shows', 'series'],
  ['anime'],
];

class TopTenShelf extends StatefulWidget {
  const TopTenShelf({
    super.key,
    required this.registry,
    required this.catalogCache,
    required this.refreshToken,
  });

  final ExtensionRegistry registry;
  final CatalogCache catalogCache;
  final int refreshToken;

  @override
  State<TopTenShelf> createState() => _TopTenShelfState();
}

class _TopTenShelfState extends State<TopTenShelf> {
  List<VersionedMediaItem> _items = const [];
  int? _loadedRefreshToken;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ensureLoaded();
  }

  @override
  void didUpdateWidget(covariant TopTenShelf oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) _ensureLoaded();
  }

  void _ensureLoaded() {
    if (_loadedRefreshToken == widget.refreshToken) return;
    _loadedRefreshToken = widget.refreshToken;
    unawaited(_load());
  }

  Future<void> _load() async {
    final grouped = <List<VersionedMediaItem>>[];
    for (final aliases in _topTenCategoryAliases) {
      final category = widget.registry.categories.cast<String?>().firstWhere(
        (value) => value != null && aliases.contains(value.toLowerCase()),
        orElse: () => null,
      );
      if (category == null) continue;

      final plugins = widget.registry.pluginsFor(category);
      final pluginId = AppScope.of(
        context,
      ).pluginController.resolve([for (final plugin in plugins) plugin.id]);
      if (pluginId == null) continue;

      final bindings = [
        for (final binding in widget.registry.catalogsFor(category))
          if (binding.extensionId == pluginId) binding,
      ];
      final sources = <_TopTenCatalogSource>[];
      for (final binding in bindings) {
        try {
          final page = await widget.catalogCache.fetchCatalog(
            widget.registry,
            binding,
            category: category,
          );
          sources.add(_TopTenCatalogSource(binding, page));
        } catch (_) {
          // A failed category contributes no items to this optional shelf.
        }
      }

      final trending = _itemsFromSections(sources, 'trending');
      final popular = _itemsFromSections(sources, 'popular');
      final source = trending.isNotEmpty ? trending : popular;
      if (source.isNotEmpty) grouped.add(source);
    }

    if (!mounted) return;
    setState(() => _items = _TopTenAlgorithm.select(grouped));
  }

  List<VersionedMediaItem> _itemsFromSections(
    Iterable<_TopTenCatalogSource> sources,
    String keyword,
  ) {
    final items = <VersionedMediaItem>[];
    for (final source in sources) {
      final page = source.page;
      for (final section in page.sections) {
        final title = section.title ?? source.binding.catalog.name;
        if (!title.toLowerCase().contains(keyword)) {
          continue;
        }
        var added = 0;
        for (final item in section.items) {
          if (item.item.kind != MediaKindV2.video &&
              item.item.kind != MediaKindV2.series) {
            continue;
          }
          items.add(item);
          added++;
          if (added == 10) break;
        }
      }
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) return const SizedBox.shrink();
    return CenteredContent(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.xs,
            ),
            child: Text(
              'Top 10',
              style: AppTypography.titleMd.copyWith(color: AppColors.onDark),
            ),
          ),
          SizedBox(
            height: mediaCardPosterHeight(140) + Clickable.ringBleed * 2,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              itemCount: _items.length,
              separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.md),
              itemBuilder: (context, index) {
                final entry = _items[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: Clickable.ringBleed,
                  ),
                  child: SizedBox(
                    width: 140,
                    child: MediaCardV2(
                      item: entry.item,
                      rank: index + 1,
                      onTap: () => openVersionedItem(context, entry),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TopTenCatalogSource {
  const _TopTenCatalogSource(this.binding, this.page);

  final CatalogBinding binding;
  final VersionedCatalogPage page;
}

abstract final class _TopTenAlgorithm {
  static List<VersionedMediaItem> select(
    List<List<VersionedMediaItem>> grouped,
  ) {
    final result = <VersionedMediaItem>[];
    final seen = <MediaRef>{};
    var offset = 0;
    while (result.length < 10 &&
        grouped.any((items) => offset < items.length)) {
      for (final items in grouped) {
        if (result.length >= 10 || offset >= items.length) continue;
        final item = items[offset];
        if (seen.add(item.item.ref)) result.add(item);
      }
      offset++;
    }
    return result;
  }
}
