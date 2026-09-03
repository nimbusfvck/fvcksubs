import 'dart:async';

import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_storage/fvcksubs_storage.dart';

import '../models/resolved_source.dart';

class SourceCache {
  SourceCache({
    SourceListStore? sourceListStore,
    Map<String, CachedSourceList> initial = const {},
    this.revalidateAfter = const Duration(minutes: 3),
    this.maxPersistedEntries = 100,
    DateTime Function() now = DateTime.now,
  }) : sourceListStore = sourceListStore ?? _NoopSourceListStore(),
       _persisted = Map.of(initial),
       _now = now;

  final SourceListStore sourceListStore;

  final Duration revalidateAfter;

  final int maxPersistedEntries;

  final DateTime Function() _now;

  final Map<MediaRef, List<ResolvedSource>> _resolved = {};
  final Map<MediaRef, DateTime> _resolvedAt = {};
  final Map<String, CachedSourceList> _persisted;
  final Map<String, Future<List<StreamSource>>> _sourceListLoads = {};

  List<ResolvedSource>? peek(MediaRef ref) => _resolved[ref];

  bool isStale(MediaRef ref) {
    final resolvedAt = _resolvedAt[ref];
    if (resolvedAt == null) return false;
    return _now().difference(resolvedAt) > revalidateAfter;
  }

  void store(MediaRef ref, List<ResolvedSource> sources) {
    _resolved[ref] = sources;
    _resolvedAt[ref] = _now();
  }

  List<StreamSource>? peekSourceList(MediaRef ref) =>
      _persisted[CachedSourceList.keyFor(ref)]?.sources;

  /// Shares an in-flight source discovery between the detail prefetch and a
  /// Play tap. Without this, a viewer who taps Play while the detail screen is
  /// warming the source list starts a second QuickJS/network fan-out.
  Future<List<StreamSource>> loadSourceList(
    MediaRef ref,
    Future<List<StreamSource>> Function() loader, {
    bool fast = false,
  }) {
    // Fast initial playback and full background refreshes must not share a
    // future: a detail-page full discovery already in flight should never
    // make the Play tap wait for the slowest provider.
    final key = '${CachedSourceList.keyFor(ref)}:${fast ? 'fast' : 'full'}';
    final existing = _sourceListLoads[key];
    if (existing != null) return existing;
    final future = loader().whenComplete(() {
      _sourceListLoads.remove(key);
    });
    _sourceListLoads[key] = future;
    return future;
  }

  void recordSourceList(MediaRef ref, List<StreamSource> sources) {
    final key = CachedSourceList.keyFor(ref);
    final existing = _persisted[key]?.sources;
    final cached = CachedSourceList(
      ref: ref,
      sources: existing == null
          ? sources
          : _retainSourceOrder(existing, sources),
      fetchedAt: _now(),
    );
    _persisted[cached.key] = cached;
    _evictOldestPersisted();
    _persist();
  }

  List<StreamSource> _retainSourceOrder(
    List<StreamSource> existing,
    List<StreamSource> refreshed,
  ) {
    final refreshedByKey = {
      for (final source in refreshed) sourceDescriptorKey(source): source,
    };
    final retained = <StreamSource>[
      for (final source in existing)
        ?refreshedByKey.remove(sourceDescriptorKey(source)),
    ];
    return [...retained, ...refreshedByKey.values];
  }

  void _evictOldestPersisted() {
    if (_persisted.length <= maxPersistedEntries) return;
    final oldestFirst = _persisted.values.toList()
      ..sort((a, b) => a.fetchedAt.compareTo(b.fetchedAt));
    for (final entry in oldestFirst.take(
      _persisted.length - maxPersistedEntries,
    )) {
      _persisted.remove(entry.key);
    }
  }

  void _persist() {
    // Persistence failure must not invalidate the in-memory session cache.
    unawaited(sourceListStore.save(Map.of(_persisted)));
  }

  void promote(MediaRef ref, String sourceId) {
    final resolved = _resolved[ref];
    if (resolved != null) {
      final index = resolved.indexWhere((s) => s.source.id == sourceId);
      if (index > 0) {
        _resolved[ref] = [
          resolved[index],
          ...resolved.take(index),
          ...resolved.skip(index + 1),
        ];
      }
    }

    final key = CachedSourceList.keyFor(ref);
    final cached = _persisted[key];
    if (cached != null) {
      final index = cached.sources.indexWhere((s) => s.id == sourceId);
      if (index > 0) {
        final sources = cached.sources;
        _persisted[key] = CachedSourceList(
          ref: ref,
          sources: [
            sources[index],
            ...sources.take(index),
            ...sources.skip(index + 1),
          ],
          fetchedAt: cached.fetchedAt,
        );
        _persist();
      }
    }
  }

  void clear() {
    _resolved.clear();
    _resolvedAt.clear();
  }
}

class _NoopSourceListStore implements SourceListStore {
  @override
  Future<Map<String, CachedSourceList>> load() async => {};

  @override
  Future<void> save(Map<String, CachedSourceList> records) async {}
}
