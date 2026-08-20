import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';

import '../catalog/catalog_cache.dart';
import '../catalog/plugin_controller.dart';

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

  Future<void> load({bool refresh = false}) async {
    final request = ++_request;
    emit(state.copyWith(status: FeaturedStatus.loading, clearError: true));

    final categories = registry.categories;
    final futures = <Future<_FeaturedLoadResult>>[];
    for (final category in categories) {
      final pluginId = pluginController.resolve([
        for (final plugin in registry.pluginsFor(category)) plugin.id,
      ]);
      if (pluginId == null) continue;
      for (final binding in registry.catalogsFor(category)) {
        if (binding.extensionId != pluginId) continue;
        futures.add(_loadPage(binding, category, refresh: refresh));
      }
    }
    final results = await Future.wait(futures);

    if (isClosed || request != _request) return;
    final pages = [
      for (final result in results)
        if (result.page != null) result.page!,
    ];
    final failures = [
      for (final result in results)
        if (result.error != null) result.error!,
    ];
    if (results.isNotEmpty && failures.length == results.length) {
      emit(
        FeaturedState(
          status: FeaturedStatus.failure,
          items: const [],
          error: failures.first,
        ),
      );
      return;
    }
    final items = FeaturedAlgorithm.select([
      for (final page in pages) ...page.items,
    ]);
    emit(FeaturedState(status: FeaturedStatus.success, items: items));
  }

  Future<_FeaturedLoadResult> _loadPage(
    CatalogBinding binding,
    String category, {
    required bool refresh,
  }) async {
    try {
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

class _FeaturedLoadResult {
  const _FeaturedLoadResult.page(this.page) : error = null;

  const _FeaturedLoadResult.error(this.error) : page = null;

  final VersionedCatalogPage? page;
  final Object? error;
}

abstract final class FeaturedAlgorithm {
  static const _kindPriority = [
    MediaKindV2.event,
    MediaKindV2.channel,
    MediaKindV2.video,
    MediaKindV2.series,
    MediaKindV2.episode,
  ];

  static List<VersionedMediaItem> select(
    Iterable<VersionedMediaItem> input, {
    int maxItems = 8,
  }) {
    final unique = <MediaRef, VersionedMediaItem>{};
    for (final item in input) {
      if (item.item.artwork == null) continue;
      unique[item.item.ref] = item;
    }
    if (unique.isEmpty || maxItems <= 0) return const [];

    final groups = <MediaKindV2, List<VersionedMediaItem>>{};
    for (final item in unique.values) {
      groups.putIfAbsent(item.item.kind, () => []).add(item);
    }
    for (final group in groups.values) {
      group.sort(_compare);
    }

    final selected = <VersionedMediaItem>[];
    for (final kind in _kindPriority) {
      final group = groups[kind];
      if (group != null && group.isNotEmpty) selected.add(group.first);
    }
    final selectedRefs = selected.map((item) => item.item.ref).toSet();
    final remaining =
        unique.values
            .where((item) => !selectedRefs.contains(item.item.ref))
            .toList()
          ..sort(_compare);
    // Keep one representative of each kind in the feed before filling the
    // remaining slots. This prevents a popular movie from crowding out every
    // live or series entry when the feed is capped.
    selected.addAll(remaining);
    return selected.take(maxItems).toList(growable: false);
  }

  static int _compare(VersionedMediaItem first, VersionedMediaItem second) {
    final score = _score(second).compareTo(_score(first));
    if (score != 0) return score;
    final title = first.item.title.compareTo(second.item.title);
    return title != 0 ? title : first.item.ref.id.compareTo(second.item.ref.id);
  }

  static double _score(VersionedMediaItem entry) {
    final item = entry.item;
    double score = (item.rating ?? 0).clamp(0, 10).toDouble() * 10;
    if (item.artwork?.landscape != null) score += 4;
    if (item.artwork?.portrait != null) score += 2;
    switch (item) {
      case EventItemV2(schedule: final schedule):
        score += switch (schedule.state) {
          ScheduleState.live => 100,
          ScheduleState.scheduled => 30,
          ScheduleState.unknown => 10,
          ScheduleState.ended => -20,
        };
      case ChannelItemV2():
        score += 20;
      default:
        break;
    }
    return score;
  }
}
