import 'dart:async';
import 'dart:math' as math;

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
  String? _loadedLibrarySignature;
  int _loadGeneration = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ensureLoaded();
  }

  @override
  void didUpdateWidget(covariant RecommendedShelf oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken ||
        oldWidget.controller != widget.controller) {
      _ensureLoaded();
    }
  }

  void _ensureLoaded() {
    final librarySignature = _librarySignature(widget.controller.state);
    if (_loadedRefreshToken == widget.refreshToken &&
        _loadedLibrarySignature == librarySignature) {
      return;
    }
    _loadedRefreshToken = widget.refreshToken;
    _loadedLibrarySignature = librarySignature;
    final generation = ++_loadGeneration;
    unawaited(_load(generation));
  }

  Future<void> _load(int generation) async {
    final history = widget.controller.history;
    final favorites = widget.controller.favorites;
    final profile = _RecommendationProfile();
    for (final record in history) {
      profile.add(record.item, weight: _historyWeight(record.lastWatched));
    }
    for (final record in favorites) {
      profile.add(record.item, weight: 3.5);
    }
    final excludedRefs = <MediaRef>{};
    for (final record in widget.controller.state.records.values) {
      if (!record.favorite && record.lastWatched == null) continue;
      excludedRefs.addAll(_relatedRefs(record.item));
    }

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
          final occurrences = <MediaRef, int>{};
          for (final entry in section.items) {
            occurrences[entry.item.ref] =
                (occurrences[entry.item.ref] ?? 0) + 1;
          }
          for (final item in section.items) {
            if (excludedRefs.contains(item.item.ref)) continue;
            if (item.item.kind != MediaKindV2.video &&
                item.item.kind != MediaKindV2.series) {
              continue;
            }
            if (item.item.isUpcoming) continue;
            final score = _recommendationScore(
              item.item,
              profile,
              occurrence: occurrences[item.item.ref] ?? 1,
            );
            candidates.add(
              _RecommendedItem(item, binding.contentRating, score),
            );
          }
        }
      } catch (_) {
        // One catalog failing should not hide recommendations from others.
      }
    }

    if (!mounted || generation != _loadGeneration) return;
    final unique = <MediaRef, _RecommendedItem>{};
    for (final candidate in candidates) {
      final existing = unique[candidate.item.item.ref];
      if (existing == null || candidate.score > existing.score) {
        unique[candidate.item.item.ref] = candidate;
      }
    }
    final items = _diversifyRecommendations(unique.values, limit: 100);
    setState(() => _items = items);
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<LibraryController, LibraryState>(
      bloc: widget.controller,
      listener: (_, _) => _ensureLoaded(),
      child: BlocBuilder<LibraryController, LibraryState>(
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
      ),
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

String _librarySignature(LibraryState state) {
  final entries = [
    for (final record in state.records.values)
      if (record.favorite || record.lastWatched != null)
        '${record.key}:${record.favorite}:${record.lastWatched?.microsecondsSinceEpoch}',
  ]..sort();
  return entries.join('|');
}

double _historyWeight(DateTime? lastWatched) {
  if (lastWatched == null) return 1;
  final ageInDays = math.max(
    0,
    DateTime.now().toUtc().difference(lastWatched.toUtc()).inDays,
  );
  return 1.5 + 2.5 * math.exp(-ageInDays / 45);
}

Set<MediaRef> _relatedRefs(MediaItemV2 item) => switch (item) {
  EpisodeItemV2(:final episode) => {item.ref, episode.parentRef},
  _ => {item.ref},
};

double _recommendationScore(
  MediaItemV2 item,
  _RecommendationProfile profile, {
  required int occurrence,
}) {
  var score = 0.0;
  score += _weightedMatch(item.genres, profile.genres) * 2.8;
  score += _weightedMatch(item.tags, profile.tags) * 1.7;
  score +=
      _weightedMatch(
        item.originalLanguage == null ? const [] : [item.originalLanguage!],
        profile.languages,
      ) *
      1.4;
  score += _weightedMatch(item.countries, profile.countries) * 0.8;

  final kind = _tasteKind(item);
  score += math.min(profile.kinds[kind] ?? 0, 6) * 0.8;

  if (item.rating case final rating?) {
    score += rating.clamp(0, 10) / 10 * 4;
    final votes = item.ratingVotes;
    if (votes != null && votes > 0) {
      score += math.min(math.log(votes + 1) / math.log(100001), 1) * 1.5;
    }
  }
  if (item.ratings.isNotEmpty) {
    final externalAverage =
        item.ratings.fold<double>(
          0,
          (total, rating) => total + (rating.score / rating.scale).clamp(0, 1),
        ) /
        item.ratings.length;
    score += externalAverage * 1.5;
  }

  if (item.releaseYear case final year?) {
    final preferredYear = profile.preferredReleaseYear;
    if (preferredYear != null) {
      final distance = (year - preferredYear).abs();
      score += 1.5 * math.exp(-distance / 8);
    } else if (year >= DateTime.now().year - 2) {
      score += 0.5;
    }
  }

  if (item.overview?.trim().isNotEmpty ?? false) score += 0.25;
  if (item.artwork != null) score += 0.25;
  score += math.min(occurrence, 3) * 0.35;

  // With no history, quality and catalog freshness still produce a useful
  // shelf instead of hiding Recommended For You entirely.
  if (profile.interactions == 0) score += 0.5;
  return score;
}

double _weightedMatch(Iterable<String> values, Map<String, double> weights) {
  final seen = <String>{};
  var score = 0.0;
  for (final value in values) {
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty || !seen.add(normalized)) continue;
    score += math.min(weights[normalized] ?? 0, 6);
  }
  return score;
}

MediaKindV2 _tasteKind(MediaItemV2 item) => switch (item) {
  EpisodeItemV2() => MediaKindV2.series,
  _ => item.kind,
};

List<_RecommendedItem> _diversifyRecommendations(
  Iterable<_RecommendedItem> input, {
  required int limit,
}) {
  final remaining = input.toList();
  final selected = <_RecommendedItem>[];
  final selectedGenres = <String>{};
  final kindCounts = <MediaKindV2, int>{};

  while (remaining.isNotEmpty && selected.length < limit) {
    var bestIndex = 0;
    var bestScore = double.negativeInfinity;
    for (var index = 0; index < remaining.length; index++) {
      final candidate = remaining[index];
      final genres = {
        for (final genre in candidate.item.item.genres)
          genre.trim().toLowerCase(),
      }..removeWhere((genre) => genre.isEmpty);
      final overlap = genres.intersection(selectedGenres).length;
      final kind = candidate.item.item.kind;
      final kindPenalty = math.max(0, (kindCounts[kind] ?? 0) - 5) * 0.35;
      final diversifiedScore = candidate.score - overlap * 1.25 - kindPenalty;
      if (diversifiedScore > bestScore) {
        bestIndex = index;
        bestScore = diversifiedScore;
      }
    }

    final best = remaining.removeAt(bestIndex);
    selected.add(best);
    selectedGenres.addAll(
      {for (final genre in best.item.item.genres) genre.trim().toLowerCase()}
        ..removeWhere((genre) => genre.isEmpty),
    );
    final kind = best.item.item.kind;
    kindCounts[kind] = (kindCounts[kind] ?? 0) + 1;
  }
  return selected;
}

class _RecommendationProfile {
  final genres = <String, double>{};
  final tags = <String, double>{};
  final languages = <String, double>{};
  final countries = <String, double>{};
  final kinds = <MediaKindV2, double>{};
  double _releaseYearTotal = 0;
  double _releaseYearWeight = 0;
  int interactions = 0;

  double? get preferredReleaseYear =>
      _releaseYearWeight == 0 ? null : _releaseYearTotal / _releaseYearWeight;

  void add(MediaItemV2 item, {required double weight}) {
    interactions++;
    _addValues(genres, item.genres, weight);
    _addValues(tags, item.tags, weight);
    if (item.originalLanguage case final language?) {
      _addValues(languages, [language], weight);
    }
    _addValues(countries, item.countries, weight);
    final kind = _tasteKind(item);
    kinds[kind] = (kinds[kind] ?? 0) + weight;
    if (item.releaseYear case final year?) {
      _releaseYearTotal += year * weight;
      _releaseYearWeight += weight;
    }
  }

  void _addValues(
    Map<String, double> target,
    Iterable<String> values,
    double weight,
  ) {
    final seen = <String>{};
    for (final value in values) {
      final normalized = value.trim().toLowerCase();
      if (normalized.isEmpty || !seen.add(normalized)) continue;
      target[normalized] = (target[normalized] ?? 0) + weight;
    }
  }
}

class _RecommendedItem {
  const _RecommendedItem(this.item, this.contentRating, this.score);

  final VersionedMediaItem item;
  final ContentRating contentRating;
  final double score;
}
