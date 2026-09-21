import 'dart:async';

import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_storage/fvcksubs_storage.dart';

import '../models/resolved_source.dart';
import 'resolved_playback_cache_store.dart';

class SourceCache {
  SourceCache({
    SourceListStore? sourceListStore,
    ResolvedPlaybackCacheStore? resolvedPlaybackStore,
    Map<String, CachedSourceList> initial = const {},
    this.maxPersistedEntries = 100,
    DateTime Function() now = DateTime.now,
  }) : sourceListStore = sourceListStore ?? _NoopSourceListStore(),
       resolvedPlaybackStore =
           resolvedPlaybackStore ?? const NoopResolvedPlaybackCacheStore(),
       _persisted = Map.of(initial),
       _now = now;

  final SourceListStore sourceListStore;
  final ResolvedPlaybackCacheStore resolvedPlaybackStore;

  final int maxPersistedEntries;

  final DateTime Function() _now;

  final Map<String, CachedSourceList> _persisted;
  final Map<String, Future<List<StreamSource>>> _sourceListLoads = {};
  Future<void> _resolvedSaveQueue = Future<void>.value();

  Future<ResolvedPlaybackCacheRecord?> loadLastResolved(MediaRef ref) async {
    await _resolvedSaveQueue;
    try {
      final record = await resolvedPlaybackStore.load();
      return record?.ref == ref ? record : null;
    } on Object {
      // Secure-cache failure must not block playback or source discovery.
      return null;
    }
  }

  void saveLastResolved(MediaRef ref, ResolvedSource resolved) {
    if (!resolved.hasAbsoluteHttpUrl) return;
    final record = ResolvedPlaybackCacheRecord(ref: ref, resolved: resolved);
    _queueResolvedWrite(() => resolvedPlaybackStore.save(record));
  }

  void removeLastResolved(MediaRef ref, String sourceId) {
    _queueResolvedWrite(() async {
      final record = await resolvedPlaybackStore.load();
      if (record?.ref == ref && record?.resolved.source.id == sourceId) {
        await resolvedPlaybackStore.save(null);
      }
    });
  }

  void clearLastResolved() {
    _queueResolvedWrite(() => resolvedPlaybackStore.save(null));
  }

  void _queueResolvedWrite(Future<void> Function() write) {
    _resolvedSaveQueue = _resolvedSaveQueue.then((_) async {
      try {
        await write();
      } on Object {
        // Secure-cache failure must not block playback or source discovery.
      }
    });
    unawaited(_resolvedSaveQueue);
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
    final refreshedByProvider = <String, List<StreamSource>>{};
    for (final source in refreshed) {
      refreshedByProvider
          .putIfAbsent(sourceProviderKey(source), () => [])
          .add(source);
    }
    final refreshedProviders = refreshedByProvider.keys.toSet();
    final providerHasMatchingKey = <String, bool>{};
    for (final source in existing) {
      final provider = sourceProviderKey(source);
      if (!refreshedProviders.contains(provider)) continue;
      providerHasMatchingKey[provider] =
          providerHasMatchingKey[provider] == true ||
          refreshedByKey.containsKey(sourceDescriptorKey(source));
    }
    final replacedProviders = <String>{};
    final retained = <StreamSource>[];
    for (final source in existing) {
      final provider = sourceProviderKey(source);
      if (!refreshedProviders.contains(provider)) {
        retained.add(source);
        continue;
      }
      if (providerHasMatchingKey[provider] == true) {
        final replacement = refreshedByKey.remove(sourceDescriptorKey(source));
        if (replacement != null) retained.add(replacement);
      } else if (replacedProviders.add(provider)) {
        for (final replacement in refreshedByProvider[provider]!) {
          retained.add(replacement);
          refreshedByKey.remove(sourceDescriptorKey(replacement));
        }
      }
    }
    for (final source in refreshed) {
      final key = sourceDescriptorKey(source);
      if (refreshedByKey.remove(key) != null) retained.add(source);
    }
    return retained;
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

  void clearAll() {
    _persisted.clear();
    _persist();
    clearLastResolved();
  }
}

class _NoopSourceListStore implements SourceListStore {
  @override
  Future<Map<String, CachedSourceList>> load() async => {};

  @override
  Future<void> save(Map<String, CachedSourceList> records) async {}
}
