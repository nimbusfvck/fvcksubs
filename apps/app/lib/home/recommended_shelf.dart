import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';

import '../app_scope.dart';
import '../catalog/catalog_cache.dart';
import '../catalog/media_card_v2.dart';
import '../detail/open_versioned_item.dart';
import '../library/library_controller.dart';
import '../theme/tokens.dart';
import '../widgets/centered_content.dart';
import '../widgets/clickable.dart';

class RecommendedShelf extends StatefulWidget {
  const RecommendedShelf({
    super.key,
    required this.controller,
    required this.registry,
    required this.catalogCache,
    this.refreshToken = 0,
  });

  final LibraryController controller;
  final ExtensionRegistry registry;
  final CatalogCache catalogCache;
  final int refreshToken;

  @override
  State<RecommendedShelf> createState() => _RecommendedShelfState();
}

class _RecommendedShelfState extends State<RecommendedShelf> {
  List<_RecommendedItem> _items = const [];
  int? _loadedRefreshToken;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ensureLoaded();
  }

  @override
  void didUpdateWidget(covariant RecommendedShelf oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) _ensureLoaded();
  }

  void _ensureLoaded() {
    if (_loadedRefreshToken == widget.refreshToken) return;
    _loadedRefreshToken = widget.refreshToken;
    unawaited(_load());
  }

  Future<void> _load() async {
    final history = widget.controller.history;
    final watchedRefs = {for (final record in history) record.item.ref};
    final tagWeights = <String, int>{};
    for (final record in history) {
      for (final tag in record.item.tags) {
        final normalized = tag.trim().toLowerCase();
        if (normalized.isEmpty) continue;
        tagWeights[normalized] = (tagWeights[normalized] ?? 0) + 1;
      }
    }
    if (tagWeights.isEmpty) return;

    final category = widget.registry.categories.cast<String?>().firstWhere(
      (value) => value?.toLowerCase() == 'all',
      orElse: () => null,
    );
    if (category == null) return;

    final pluginController = AppScope.of(context).pluginController;
    final plugins = widget.registry.pluginsFor(category);
    final pluginId = pluginController.resolve([
      for (final plugin in plugins) plugin.id,
    ]);
    if (pluginId == null) return;

    final candidates = <_RecommendedItem>[];
    final bindings = [
      for (final binding in widget.registry.catalogsFor(category))
        if (binding.extensionId == pluginId) binding,
    ];
    for (final binding in bindings) {
      try {
        final page = await widget.catalogCache.fetchCatalog(
          widget.registry,
          binding,
          category: category,
        );
        for (final section in page.sections) {
          for (final item in section.items) {
            if (watchedRefs.contains(item.item.ref)) continue;
            if (item.item.kind != MediaKindV2.video &&
                item.item.kind != MediaKindV2.series) {
              continue;
            }
            if (item.item.isUpcoming) continue;
            final score = item.item.tags.fold<int>(
              0,
              (total, tag) =>
                  total + (tagWeights[tag.trim().toLowerCase()] ?? 0),
            );
            if (score > 0) {
              candidates.add(
                _RecommendedItem(item, binding.contentRating, score),
              );
            }
          }
        }
      } catch (_) {
        // One catalog failing should not hide recommendations from others.
      }
    }

    if (!mounted) return;
    final unique = <MediaRef, _RecommendedItem>{};
    for (final candidate in candidates) {
      final existing = unique[candidate.item.item.ref];
      if (existing == null || candidate.score > existing.score) {
        unique[candidate.item.item.ref] = candidate;
      }
    }
    final items = unique.values.toList()
      ..sort((first, second) => second.score.compareTo(first.score));
    setState(() => _items = items.take(100).toList());
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LibraryController, LibraryState>(
      bloc: widget.controller,
      builder: (context, _) {
        if (_items.isEmpty) return const SizedBox.shrink();
        return CenteredContent(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.md,
                  AppSpacing.xs,
                  AppSpacing.xs,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Recommended For You',
                        style: AppTypography.titleMd.copyWith(
                          color: AppColors.onDark,
                        ),
                      ),
                    ),
                    if (_items.length > 10)
                      TextButton(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => _RecommendedPage(items: _items),
                          ),
                        ),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.brandAccent,
                        ),
                        child: const Text('See more'),
                      ),
                  ],
                ),
              ),
              SizedBox(
                height: mediaCardPosterHeight(140) + Clickable.ringBleed * 2,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: Clickable.ringBleed,
                  ),
                  itemCount: _items.length > 10 ? 10 : _items.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(width: AppSpacing.md),
                  itemBuilder: (context, index) {
                    final entry = _items[index];
                    return SizedBox(
                      width: 140,
                      child: MediaCardV2(
                        item: entry.item.item,
                        onTap: () => openVersionedItem(
                          context,
                          entry.item,
                          contentRating: entry.contentRating,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _RecommendedPage extends StatefulWidget {
  const _RecommendedPage({required this.items});

  final List<_RecommendedItem> items;

  @override
  State<_RecommendedPage> createState() => _RecommendedPageState();
}

class _RecommendedPageState extends State<_RecommendedPage> {
  Timer? _loadingTimer;
  bool _showGrid = false;

  @override
  void initState() {
    super.initState();
    _loadingTimer = Timer(const Duration(milliseconds: 260), () {
      if (mounted) setState(() => _showGrid = true);
    });
  }

  @override
  void dispose() {
    _loadingTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Recommended For You')),
      body: _showGrid
          ? _RecommendedGrid(items: widget.items)
          : const Center(child: CircularProgressIndicator()),
    );
  }
}

class _RecommendedGrid extends StatelessWidget {
  const _RecommendedGrid({required this.items});

  final List<_RecommendedItem> items;

  @override
  Widget build(BuildContext context) {
    final columns = MediaQuery.sizeOf(context).width >= 700 ? 5 : 2;
    return GridView.builder(
      padding: const EdgeInsets.all(AppSpacing.md),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: AppSpacing.md,
        mainAxisSpacing: AppSpacing.md,
        childAspectRatio: 140 / mediaCardPosterHeight(140),
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final entry = items[index];
        return MediaCardV2(
          item: entry.item.item,
          enableHero: false,
          onTap: () => openVersionedItem(
            context,
            entry.item,
            contentRating: entry.contentRating,
          ),
        );
      },
    );
  }
}

class _RecommendedItem {
  const _RecommendedItem(this.item, this.contentRating, this.score);

  final VersionedMediaItem item;
  final ContentRating contentRating;
  final int score;
}
