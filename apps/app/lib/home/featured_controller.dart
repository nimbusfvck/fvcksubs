import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';

import '../catalog/catalog_cache.dart';
import '../catalog/plugin_controller.dart';

const int maxFeaturedConcurrentLoads = 3;

enum FeaturedStatus { initial, loading, success, failure }

class FeaturedState {
  const FeaturedState({
    this.status = FeaturedStatus.initial,
    this.items = const [],
    this.error,
  });

  final FeaturedStatus status;
  final List<VersionedMediaItem> items;
  final Object? error;

  bool get isLoading => status == FeaturedStatus.loading;

  FeaturedState copyWith({
    FeaturedStatus? status,
    List<VersionedMediaItem>? items,
    Object? error,
    bool clearError = false,
  }) => FeaturedState(
    status: status ?? this.status,
    items: items ?? this.items,
    error: clearError ? null : error ?? this.error,
  );
}

class FeaturedController extends Cubit<FeaturedState> {
  FeaturedController({
    required this.registry,
    required this.catalogCache,
    required this.pluginController,
  }) : super(const FeaturedState());

  final ExtensionRegistry registry;
  final CatalogCache catalogCache;
  final PluginController pluginController;

  int _request = 0;
  Future<void>? _activeLoad;
  bool _activeIsRefresh = false;
  bool _refreshQueued = false;
  String? _queuedHomeCategory;

  Future<void> load({bool refresh = false, String? homeCategory}) {
    final activeLoad = _activeLoad;
    if (activeLoad != null) {
      if (refresh) {
        _refreshQueued = true;
        _queuedHomeCategory = homeCategory;
        if (!_activeIsRefresh) return Future<void>.value();
      }
      return activeLoad;
    }

    final future = _load(refresh: refresh, homeCategory: homeCategory);
    _activeLoad = future;
    _activeIsRefresh = refresh;
    return future.whenComplete(() {
      if (!identical(_activeLoad, future)) return;
      _activeLoad = null;
      _activeIsRefresh = false;
      if (_refreshQueued && !isClosed) {
        final queuedHomeCategory = _queuedHomeCategory;
        _refreshQueued = false;
        _queuedHomeCategory = null;
        unawaited(load(refresh: true, homeCategory: queuedHomeCategory));
      }
    });
  }

  Future<void> _load({
    required bool refresh,
    required String? homeCategory,
  }) async {
    final request = ++_request;
    if (!refresh || state.items.isEmpty) {
      emit(state.copyWith(status: FeaturedStatus.loading, clearError: true));
    }

    final category = homeCategory ?? _defaultHomeCategory();
    final requests = <_FeaturedLoadRequest>[];
    if (category != null) {
      final pluginId = pluginController.resolve([
        for (final plugin in registry.pluginsFor(category)) plugin.id,
      ]);
      if (pluginId != null) {
        for (final binding in registry.catalogsFor(category)) {
          if (binding.extensionId == pluginId) {
            requests.add(_FeaturedLoadRequest(binding, category));
          }
        }
      }
    }

    final results = List<_FeaturedLoadResult?>.filled(requests.length, null);
    final loadOrder = [
      for (var index = 0; index < requests.length; index++)
        if (requests[index].category == category) index,
      for (var index = 0; index < requests.length; index++)
        if (requests[index].category != category) index,
    ];
    var nextLoad = 0;
    var completed = 0;
    var hasPersistentCache = false;

    Future<void> worker() async {
      while (nextLoad < loadOrder.length) {
        // This increment happens before the await, so one isolate cannot hand
        // the same request to two workers.
        final resultIndex = loadOrder[nextLoad++];
        final requestSpec = requests[resultIndex];
        final result = await _loadPage(
          requestSpec.binding,
          requestSpec.category,
          refresh: refresh,
        );
        results[resultIndex] = result;
        completed++;
        hasPersistentCache = hasPersistentCache || result.fromPersistentCache;
      }
    }

    final workerCount = math.min(maxFeaturedConcurrentLoads, loadOrder.length);
    await Future.wait([for (var i = 0; i < workerCount; i++) worker()]);

    if (isClosed || request != _request) return;
    final completedResults = [for (final result in results) ?result];
    final pages = [
      for (final result in completedResults)
        if (result.page != null) result.page!,
    ];
    final failures = [
      for (final result in completedResults)
        if (result.error != null) result.error!,
    ];
    if (completed > 0 && failures.length == completed) {
      if (state.items.isNotEmpty) {
        emit(
          FeaturedState(
            status: FeaturedStatus.success,
            items: state.items,
            error: failures.first,
          ),
        );
        return;
      }
      emit(
        FeaturedState(
          status: FeaturedStatus.failure,
          items: const [],
          error: failures.first,
        ),
      );
      return;
    }
    final items = FeaturedAlgorithm.selectPages(pages);
    emit(FeaturedState(status: FeaturedStatus.success, items: items));
    if (!refresh && hasPersistentCache) {
      // Keep the persisted Home snapshot usable, but do not leave a prior
      // session's Hero feed stale until it refreshes in the background.
      unawaited(load(refresh: true, homeCategory: category));
    }
  }

  String? _defaultHomeCategory() {
    for (final category in registry.categories) {
      if (category.toLowerCase() == 'all') return category;
    }
    return registry.categories.isEmpty ? null : registry.categories.first;
  }

  Future<_FeaturedLoadResult> _loadPage(
    CatalogBinding binding,
    String category, {
    required bool refresh,
  }) async {
    try {
      if (!refresh && catalogCache.peekVersioned(binding, category) == null) {
        final persisted = await catalogCache.readPersistedVersioned(
          binding,
          category,
        );
        if (persisted != null) {
          registry.rememberCatalogPage(binding, persisted);
          return _FeaturedLoadResult.page(persisted, fromPersistentCache: true);
        }
      }
      return _FeaturedLoadResult.page(
        await catalogCache.fetchCatalog(
          registry,
          binding,
          category: category,
          refresh: refresh,
        ),
      );
    } catch (error) {
      return _FeaturedLoadResult.error(error);
    }
  }
}

class _FeaturedLoadRequest {
  const _FeaturedLoadRequest(this.binding, this.category);

  final CatalogBinding binding;
  final String category;
}

class _FeaturedLoadResult {
  const _FeaturedLoadResult.page(this.page, {this.fromPersistentCache = false})
    : error = null;

  const _FeaturedLoadResult.error(this.error)
    : page = null,
      fromPersistentCache = false;

  final VersionedCatalogPage? page;
  final Object? error;
  final bool fromPersistentCache;
}

/// Selects a varied hero feed using only provider-agnostic protocol fields.
///
/// Catalog order is treated as the extension's editorial ranking. Schedule,
/// release year, rating, and artwork refine that order without replacing it.
abstract final class FeaturedAlgorithm {
  // These limits apply while diversity is possible. They are relaxed during
  // the final fill so a single-kind catalog can still populate the carousel.
  static const _maximumPerKind = <MediaKindV2, int>{
    MediaKindV2.event: 1,
    MediaKindV2.video: 2,
    MediaKindV2.series: 2,
    MediaKindV2.channel: 1,
    MediaKindV2.episode: 1,
  };

  // Time windows group events and releases by user relevance.
  static const _upcomingWindow = Duration(hours: 24);
  static const _imminentWindow = Duration(hours: 6);
  static const _nearFutureWindow = Duration(days: 3);

  // Editorial weights favor the beginning of each page and section while
  // allowing strong freshness and quality signals to affect later slots.
  static const _editorialPositionWeight = 36.0;
  static const _sectionWeight = 8.0;
  static const _sectionPenalty = 2.0;
  static const _pageWeight = 3.0;
  static const _pagePenalty = 1.0;

  // Freshness scores keep imminent content ahead of distant events.
  static const _imminentFreshnessScore = 24.0;
  static const _upcomingFreshnessScore = 16.0;
  static const _nearFutureFreshnessScore = 8.0;
  static const _futureFreshnessScore = 2.0;
  static const _currentReleaseScore = 20.0;
  static const _previousReleaseScore = 12.0;
  static const _olderRecentReleaseScore = 5.0;
  static const _previousReleaseAge = 1;
  static const _olderRecentReleaseAge = 2;

  // Quality and artwork are secondary signals, not substitutes for catalog
  // order. Episodes are deprioritized because their parent series is clearer
  // in a mixed-content hero.
  static const _maximumRating = 10.0;
  static const _ratingWeight = 2.0;
  static const _landscapeScore = 5.0;
  static const _portraitScore = 3.0;
  static const _eventScore = 0.0;
  static const _channelScore = 3.0;
  static const _episodeScore = -8.0;

  // Duplicate refs keep the snapshot with the most useful display metadata.
  static const _metadataLandscapeScore = 4.0;
  static const _metadataPortraitScore = 2.0;
  static const _metadataPresenceScore = 1.0;

  // FNV-1a provides a deterministic tie-break without relying on hashCode,
  // whose result is not a persistence contract.
  static const _fnvOffsetBasis = 2166136261;
  static const _fnvPrime = 16777619;
  static const _positiveHashMask = 0x7fffffff;

  /// Selects featured items from one flat editorial sequence.
  ///
  /// Prefer [selectPages] when section boundaries are available.
  static List<VersionedMediaItem> select(
    Iterable<VersionedMediaItem> input, {
    int maxItems = 8,
    DateTime? now,
    bool allowMultipleEvents = false,
  }) {
    final candidates = <_FeaturedCandidate>[];
    var itemIndex = 0;
    for (final item in input) {
      candidates.add(
        _FeaturedCandidate(
          entry: item,
          pageIndex: 0,
          sectionIndex: 0,
          itemIndex: itemIndex,
          ordinal: itemIndex,
        ),
      );
      itemIndex++;
    }
    return _selectCandidates(
      candidates,
      maxItems: maxItems,
      now: now ?? DateTime.now(),
      allowMultipleEvents: allowMultipleEvents,
    );
  }

  /// Selects featured items while preserving page, section, and item order.
  static List<VersionedMediaItem> selectPages(
    Iterable<VersionedCatalogPage> input, {
    int maxItems = 8,
    DateTime? now,
    bool allowMultipleEvents = false,
  }) {
    final candidates = <_FeaturedCandidate>[];
    var pageIndex = 0;
    var ordinal = 0;
    for (final page in input) {
      for (
        var sectionIndex = 0;
        sectionIndex < page.sections.length;
        sectionIndex++
      ) {
        final section = page.sections[sectionIndex];
        for (var itemIndex = 0; itemIndex < section.items.length; itemIndex++) {
          candidates.add(
            _FeaturedCandidate(
              entry: section.items[itemIndex],
              pageIndex: pageIndex,
              sectionIndex: sectionIndex,
              itemIndex: itemIndex,
              ordinal: ordinal,
            ),
          );
          ordinal++;
        }
      }
      pageIndex++;
    }
    return _selectCandidates(
      candidates,
      maxItems: maxItems,
      now: now ?? DateTime.now(),
      allowMultipleEvents: allowMultipleEvents,
    );
  }

  static List<VersionedMediaItem> _selectCandidates(
    Iterable<_FeaturedCandidate> input, {
    required int maxItems,
    required DateTime now,
    required bool allowMultipleEvents,
  }) {
    if (maxItems <= 0) return const [];

    // A ref can be repeated across sections. Keep one candidate before slot
    // selection so the same title never occupies multiple hero pages.
    final unique = <MediaRef, _FeaturedCandidate>{};
    for (final candidate in input) {
      if (!_isEligible(candidate.entry.item, now)) continue;
      final existing = unique[candidate.entry.item.ref];
      if (existing == null || _isRicher(candidate, existing)) {
        unique[candidate.entry.item.ref] = candidate;
      }
    }
    if (unique.isEmpty) return const [];

    final candidates = unique.values.toList(growable: false);
    final selected = <_FeaturedCandidate>[];
    final selectedRefs = <MediaRef>{};
    final kindCounts = <MediaKindV2, int>{};
    final eventLimit = allowMultipleEvents ? maxItems : 1;

    void pick(
      bool Function(_FeaturedCandidate candidate) accepts,
      int Function(_FeaturedCandidate first, _FeaturedCandidate second) compare,
    ) {
      if (selected.length >= maxItems) return;
      _FeaturedCandidate? chosen;
      for (final candidate in candidates) {
        if (selectedRefs.contains(candidate.entry.item.ref) ||
            !accepts(candidate) ||
            !_underKindLimit(candidate, kindCounts, eventLimit: eventLimit)) {
          continue;
        }
        if (chosen == null || compare(candidate, chosen) < 0) {
          chosen = candidate;
        }
      }
      if (chosen == null) return;
      selected.add(chosen);
      selectedRefs.add(chosen.entry.item.ref);
      final kind = chosen.entry.item.kind;
      kindCounts[kind] = (kindCounts[kind] ?? 0) + 1;
    }

    final composite = _compositeComparator(now);

    // Keep editorial video and series items at the front. By default a single
    // highly rated event from the viewer's local day may follow them;
    // category surfaces can opt into multiple events.
    pick(
      (candidate) => candidate.entry.item.kind == MediaKindV2.video,
      _editorialComparator(now),
    );
    pick(
      (candidate) => candidate.entry.item.kind == MediaKindV2.series,
      _editorialComparator(now),
    );
    pick((candidate) => _isTodayEvent(candidate, now), _eventComparator(now));
    pick((candidate) => _isNewVod(candidate, now), _freshnessComparator(now));
    pick(_isRatedVod, _ratingComparator(now));

    final remaining = [
      for (final candidate in candidates)
        if (!selectedRefs.contains(candidate.entry.item.ref)) candidate,
    ]..sort(composite);

    // Prefer a balanced feed, then relax the limits rather than returning a
    // partially empty carousel when only one media kind is available.
    _fill(
      selected,
      remaining,
      selectedRefs,
      kindCounts,
      maxItems: maxItems,
      enforceKindLimits: true,
      eventLimit: eventLimit,
    );
    _fill(
      selected,
      remaining,
      selectedRefs,
      kindCounts,
      maxItems: maxItems,
      enforceKindLimits: false,
      eventLimit: eventLimit,
    );

    return [for (final candidate in selected) candidate.entry];
  }

  static void _fill(
    List<_FeaturedCandidate> selected,
    List<_FeaturedCandidate> candidates,
    Set<MediaRef> selectedRefs,
    Map<MediaKindV2, int> kindCounts, {
    required int maxItems,
    required bool enforceKindLimits,
    required int eventLimit,
  }) {
    while (selected.length < maxItems) {
      final available = [
        for (final candidate in candidates)
          if (!selectedRefs.contains(candidate.entry.item.ref) &&
              (candidate.entry.item.kind == MediaKindV2.event
                  ? _underKindLimit(
                      candidate,
                      kindCounts,
                      eventLimit: eventLimit,
                    )
                  : !enforceKindLimits ||
                        _underKindLimit(candidate, kindCounts)))
            candidate,
      ];
      if (available.isEmpty) return;

      final lastKind = selected.isEmpty ? null : selected.last.entry.item.kind;
      // Avoid adjacent items of the same kind when another ranked candidate
      // is available. The source ranking remains the fallback.
      final chosen = available.firstWhere(
        (candidate) => candidate.entry.item.kind != lastKind,
        orElse: () => available.first,
      );
      selected.add(chosen);
      selectedRefs.add(chosen.entry.item.ref);
      final kind = chosen.entry.item.kind;
      kindCounts[kind] = (kindCounts[kind] ?? 0) + 1;
    }
  }

  static bool _isEligible(MediaItemV2 item, DateTime now) {
    // Channels remain available in catalogs, but the hero is reserved for
    // editorial content and events from the viewer's local day.
    if (item is ChannelItemV2) return false;
    if (item case EventItemV2(schedule: final schedule)) {
      if (schedule.state == ScheduleState.ended ||
          !_isSameLocalDay(schedule.startsAt, now)) {
        return false;
      }
    }
    final artwork = item.artwork;
    if (artwork?.landscape != null || artwork?.portrait != null) return true;

    // Events have a deterministic generated fallback. Other kinds stay
    // excluded because a generic placeholder is not strong enough for a hero.
    return item is EventItemV2 || item is ChannelItemV2;
  }

  static bool _isRicher(
    _FeaturedCandidate candidate,
    _FeaturedCandidate existing,
  ) {
    final quality = _metadataQuality(
      candidate.entry.item,
    ).compareTo(_metadataQuality(existing.entry.item));
    if (quality != 0) return quality > 0;
    return candidate.ordinal < existing.ordinal;
  }

  static double _metadataQuality(MediaItemV2 item) {
    double score = (item.rating ?? 0).clamp(0, _maximumRating).toDouble();
    if (item.artwork?.landscape != null) score += _metadataLandscapeScore;
    if (item.artwork?.portrait != null) score += _metadataPortraitScore;
    if (item.artwork?.logo != null) score += _metadataPresenceScore;
    if (item.releaseYear != null) score += _metadataPresenceScore;
    if (item.subtitle?.trim().isNotEmpty ?? false) {
      score += _metadataPresenceScore;
    }
    return score;
  }

  static bool _underKindLimit(
    _FeaturedCandidate candidate,
    Map<MediaKindV2, int> counts, {
    int eventLimit = 1,
  }) {
    final kind = candidate.entry.item.kind;
    final limit = kind == MediaKindV2.event
        ? eventLimit
        : (_maximumPerKind[kind] ?? 1);
    return (counts[kind] ?? 0) < limit;
  }

  static bool _isTodayEvent(_FeaturedCandidate candidate, DateTime now) {
    final item = candidate.entry.item;
    return item is EventItemV2 && _isSameLocalDay(item.schedule.startsAt, now);
  }

  static bool _isSameLocalDay(DateTime first, DateTime second) {
    final firstLocal = first.toLocal();
    final secondLocal = second.toLocal();
    return firstLocal.year == secondLocal.year &&
        firstLocal.month == secondLocal.month &&
        firstLocal.day == secondLocal.day;
  }

  static bool _isNewVod(_FeaturedCandidate candidate, DateTime now) {
    final item = candidate.entry.item;
    if (item.kind != MediaKindV2.video && item.kind != MediaKindV2.series) {
      return false;
    }
    final year = item.releaseYear;
    return year != null && year >= now.year - _previousReleaseAge;
  }

  static bool _isRatedVod(_FeaturedCandidate candidate) {
    final item = candidate.entry.item;
    return (item.kind == MediaKindV2.video ||
            item.kind == MediaKindV2.series) &&
        item.rating != null;
  }

  static int Function(_FeaturedCandidate, _FeaturedCandidate)
  _compositeComparator(DateTime now) =>
      (first, second) => _compareScores(
        first,
        second,
        _compositeScore(first, now),
        _compositeScore(second, now),
        now,
      );

  static int Function(_FeaturedCandidate, _FeaturedCandidate)
  _editorialComparator(DateTime now) =>
      (first, second) => _compareScores(
        first,
        second,
        _editorialScore(first),
        _editorialScore(second),
        now,
      );

  static int Function(_FeaturedCandidate, _FeaturedCandidate)
  _freshnessComparator(DateTime now) =>
      (first, second) => _compareScores(
        first,
        second,
        _freshnessScore(first, now),
        _freshnessScore(second, now),
        now,
      );

  static int Function(_FeaturedCandidate, _FeaturedCandidate) _ratingComparator(
    DateTime now,
  ) =>
      (first, second) => _compareScores(
        first,
        second,
        first.entry.item.rating ?? 0,
        second.entry.item.rating ?? 0,
        now,
      );

  /// Gives an extension's event rating priority over catalog position and
  /// kickoff time. Extensions use this generic editorial signal for facts the
  /// shell cannot know, such as a football provider's top-club ranking.
  static int Function(_FeaturedCandidate, _FeaturedCandidate) _eventComparator(
    DateTime now,
  ) => (first, second) {
    final rating = _eventRatingCompare(first, second);
    if (rating != 0) return rating;
    return _compareScores(
      first,
      second,
      _compositeScore(first, now),
      _compositeScore(second, now),
      now,
    );
  };

  static int _eventRatingCompare(
    _FeaturedCandidate first,
    _FeaturedCandidate second,
  ) {
    final firstRating = first.entry.item.rating;
    final secondRating = second.entry.item.rating;
    if (firstRating == null && secondRating == null) return 0;
    return (secondRating ?? -1).compareTo(firstRating ?? -1);
  }

  static int _compareScores(
    _FeaturedCandidate first,
    _FeaturedCandidate second,
    double firstScore,
    double secondScore,
    DateTime now,
  ) {
    final score = secondScore.compareTo(firstScore);
    if (score != 0) return score;
    final tie = _dailyTieBreak(
      first,
      now,
    ).compareTo(_dailyTieBreak(second, now));
    if (tie != 0) return tie;
    return first.ordinal.compareTo(second.ordinal);
  }

  static double _compositeScore(_FeaturedCandidate candidate, DateTime now) =>
      _editorialScore(candidate) +
      _freshnessScore(candidate, now) +
      _qualityScore(candidate.entry.item) +
      _artworkScore(candidate.entry.item) +
      _kindAdjustment(candidate.entry.item.kind);

  static double _editorialScore(_FeaturedCandidate candidate) =>
      _editorialPositionWeight / math.sqrt(candidate.itemIndex + 1) +
      math.max(0.0, _sectionWeight - candidate.sectionIndex * _sectionPenalty) +
      math.max(0.0, _pageWeight - candidate.pageIndex * _pagePenalty);

  static double _freshnessScore(_FeaturedCandidate candidate, DateTime now) {
    final item = candidate.entry.item;
    switch (item) {
      case EventItemV2(schedule: final schedule):
        final untilStart = schedule.startsAt.toUtc().difference(now.toUtc());
        if (untilStart.isNegative) return 0.0;
        return switch (untilStart) {
          <= _imminentWindow => _imminentFreshnessScore,
          <= _upcomingWindow => _upcomingFreshnessScore,
          <= _nearFutureWindow => _nearFutureFreshnessScore,
          _ => _futureFreshnessScore,
        };
      default:
        final year = item.releaseYear;
        if (year == null) return 0;
        final age = now.year - year;
        return switch (age) {
          <= 0 => _currentReleaseScore,
          _previousReleaseAge => _previousReleaseScore,
          _olderRecentReleaseAge => _olderRecentReleaseScore,
          _ => 0.0,
        };
    }
  }

  static double _qualityScore(MediaItemV2 item) =>
      (item.rating ?? 0).clamp(0, _maximumRating).toDouble() * _ratingWeight;

  static double _artworkScore(MediaItemV2 item) {
    if (item.artwork?.landscape != null) return _landscapeScore;
    return item.artwork?.portrait != null ? _portraitScore : 0.0;
  }

  static double _kindAdjustment(MediaKindV2 kind) => switch (kind) {
    MediaKindV2.event => _eventScore,
    MediaKindV2.channel => _channelScore,
    MediaKindV2.video || MediaKindV2.series => 0.0,
    MediaKindV2.episode => _episodeScore,
  };

  static int _dailyTieBreak(_FeaturedCandidate candidate, DateTime now) {
    // Include the UTC day so equally ranked items can rotate between days but
    // remain stable across refreshes during the same day.
    final utc = now.toUtc();
    final day = utc.difference(DateTime.utc(utc.year)).inDays;
    final ref = candidate.entry.item.ref;
    final value =
        '${utc.year}-$day|${ref.extensionId}|'
        '${ref.providerId}|${ref.id}';
    var hash = _fnvOffsetBasis;
    for (final unit in value.codeUnits) {
      hash = ((hash ^ unit) * _fnvPrime) & _positiveHashMask;
    }
    return hash;
  }
}

/// A catalog item paired with its original editorial position.
class _FeaturedCandidate {
  const _FeaturedCandidate({
    required this.entry,
    required this.pageIndex,
    required this.sectionIndex,
    required this.itemIndex,
    required this.ordinal,
  });

  final VersionedMediaItem entry;
  final int pageIndex;
  final int sectionIndex;
  final int itemIndex;
  final int ordinal;
}
