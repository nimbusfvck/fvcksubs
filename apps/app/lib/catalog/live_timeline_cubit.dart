import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';

import 'catalog_cache.dart';

enum CatalogTimelineStatus { initial, loading, success }

class CatalogTimelineState {
  const CatalogTimelineState({
    this.status = CatalogTimelineStatus.initial,
    this.events = const [],
  });

  final CatalogTimelineStatus status;
  final List<EventItemV2> events;

  bool get isLoading => status == CatalogTimelineStatus.loading;

  CatalogTimelineState copyWith({
    CatalogTimelineStatus? status,
    List<EventItemV2>? events,
  }) => CatalogTimelineState(
    status: status ?? this.status,
    events: events ?? this.events,
  );
}

/// Loads the live category for the app-owned timeline.
class CatalogTimelineCubit extends Cubit<CatalogTimelineState> {
  CatalogTimelineCubit({required this.catalogCache, required this.registry})
    : super(const CatalogTimelineState());

  final CatalogCache catalogCache;
  final ExtensionRegistry registry;
  int _loadGeneration = 0;

  Future<void> load(
    List<CatalogBinding> bindings, {
    required String category,
    bool refresh = false,
    bool Function(CatalogBinding binding)? shouldRefreshBinding,
  }) async {
    if (isClosed) return;
    final generation = ++_loadGeneration;
    emit(state.copyWith(status: CatalogTimelineStatus.loading));

    final pages = await Future.wait([
      for (final binding in bindings)
        _loadBinding(
          binding,
          category: category,
          refresh: shouldRefreshBinding?.call(binding) ?? refresh,
        ),
    ]);
    if (isClosed || generation != _loadGeneration) return;

    final unique = <MediaRef, EventItemV2>{};
    for (final page in pages) {
      for (final section in page.sections) {
        for (final versioned in section.items) {
          final item = versioned.item;
          if (item is EventItemV2) unique[item.ref] = item;
        }
      }
    }
    final events = unique.values.toList()
      ..sort((a, b) => a.schedule.startsAt.compareTo(b.schedule.startsAt));
    emit(
      CatalogTimelineState(
        status: CatalogTimelineStatus.success,
        events: events,
      ),
    );
  }

  Future<VersionedCatalogPage> _loadBinding(
    CatalogBinding binding, {
    required String category,
    required bool refresh,
  }) async {
    try {
      return await catalogCache.fetchCatalog(
        registry,
        binding,
        category: category,
        refresh: refresh,
      );
    } catch (_) {
      // A broken sports feed must not hide the other feeds in the timeline.
      return const VersionedCatalogPage(sections: []);
    }
  }
}
