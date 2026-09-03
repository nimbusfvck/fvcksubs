import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_app/player/player_page.dart';
import 'package:fvcksubs_app/player/models/playback_media.dart';
import 'package:fvcksubs_app/player/state/source_cache.dart';
import 'package:fvcksubs_app/player/workflow/play_item.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_storage/fvcksubs_storage.dart';

class FakeSourceListStore implements SourceListStore {
  Map<String, CachedSourceList> saved = {};

  @override
  Future<Map<String, CachedSourceList>> load() async => saved;

  @override
  Future<void> save(Map<String, CachedSourceList> records) async =>
      saved = records;
}

void main() {
  const ref = MediaRef(extensionId: 'fvck', providerId: 'fvck.p', id: 'e1');

  ResolvedSource resolved(String id) => ResolvedSource(
    source: StreamSource(id: id, label: id),
    stream: PlayableStream(
      url: 'https://edge/$id.m3u8',
      format: StreamFormat.hls,
    ),
  );

  StreamSource source(String id) => StreamSource(id: id, label: id);

  group('resolved sources: peek/store/isStale', () {
    test('live playback bypasses resolved and persisted source caches', () {
      final live = PlaybackMedia(
        EventItemV2(
          ref: ref,
          title: 'Home vs Away',
          schedule: Schedule(
            startsAt: DateTime.utc(2026, 1, 1),
            state: ScheduleState.live,
          ),
          participants: const [],
        ),
      );
      const vod = PlaybackMedia(VideoItemV2(ref: ref, title: 'A movie'));

      expect(canUseCachedPlaybackSources(live), isFalse);
      expect(canUseCachedPlaybackSources(vod), isTrue);
    });

    test('peek is null before anything is stored', () {
      expect(SourceCache().peek(ref), isNull);
    });

    test('store then peek round-trips the list', () {
      final cache = SourceCache();
      final sources = [resolved('a'), resolved('b')];
      cache.store(ref, sources);
      expect(cache.peek(ref), sources);
    });

    test('rejects a relative URL from a stale resolved cache entry', () {
      const source = ResolvedSource(
        source: StreamSource(id: 'stale', label: 'stale'),
        stream: PlayableStream(
          url: '/stream/stale/master.m3u8',
          format: StreamFormat.hls,
        ),
      );

      expect(source.hasAbsoluteHttpUrl, isFalse);
    });

    test('a fresh entry is not stale', () {
      final now = DateTime(2026);
      final cache = SourceCache(now: () => now);
      cache.store(ref, [resolved('a')]);
      expect(cache.isStale(ref), isFalse);
    });

    test('an entry past revalidateAfter is stale', () {
      var now = DateTime(2026);
      final cache = SourceCache(
        now: () => now,
        revalidateAfter: const Duration(minutes: 3),
      );
      cache.store(ref, [resolved('a')]);
      now = now.add(const Duration(minutes: 4));
      expect(cache.isStale(ref), isTrue);
    });

    test('an entry from hours ago is still servable, never expires', () {
      var now = DateTime(2026);
      final cache = SourceCache(now: () => now);
      final sources = [resolved('a')];
      cache.store(ref, sources);
      now = now.add(const Duration(hours: 6));
      expect(cache.peek(ref), sources);
    });

    test('isStale is false when nothing is cached — nothing to revalidate', () {
      expect(SourceCache().isStale(ref), isFalse);
    });

    test('clear forgets resolved entries', () {
      final cache = SourceCache();
      cache.store(ref, [resolved('a')]);
      cache.clear();
      expect(cache.peek(ref), isNull);
    });

    test('clear leaves the persisted source list alone', () {
      final cache = SourceCache();
      cache.store(ref, [resolved('a')]);
      cache.recordSourceList(ref, [source('a')]);
      cache.clear();
      expect(cache.peekSourceList(ref), isNotNull);
    });
  });

  group('persisted source list: peekSourceList/recordSourceList', () {
    test('peekSourceList is null before anything is recorded', () {
      expect(SourceCache().peekSourceList(ref), isNull);
    });

    test('shares an in-flight source discovery', () async {
      final cache = SourceCache();
      final gate = Completer<List<StreamSource>>();
      var calls = 0;
      Future<List<StreamSource>> load() {
        calls++;
        return gate.future;
      }

      final first = cache.loadSourceList(ref, load);
      final second = cache.loadSourceList(ref, load);
      expect(calls, 1);

      final result = [source('a')];
      gate.complete(result);
      expect(await first, result);
      expect(await second, result);
    });

    test('does not let full discovery block fast discovery', () async {
      final cache = SourceCache();
      final fullGate = Completer<List<StreamSource>>();
      final fastResult = [source('fast')];

      final full = cache.loadSourceList(ref, () => fullGate.future);
      final fast = cache.loadSourceList(
        ref,
        () async => fastResult,
        fast: true,
      );

      expect(await fast, fastResult);
      fullGate.complete(const []);
      expect(await full, isEmpty);
    });

    test('recordSourceList then peekSourceList round-trips the list', () {
      final cache = SourceCache();
      final sources = [source('a'), source('b')];
      cache.recordSourceList(ref, sources);
      expect(cache.peekSourceList(ref), sources);
    });

    test('retains the selected source order when discovery refreshes', () {
      final cache = SourceCache();
      cache.recordSourceList(ref, [source('a'), source('b')]);
      cache.promote(ref, 'b');

      cache.recordSourceList(ref, [source('a'), source('b'), source('c')]);

      expect(cache.peekSourceList(ref)!.map((source) => source.id), [
        'b',
        'a',
        'c',
      ]);
    });

    test('refresh dedupes descriptors whose tokenized ids changed', () {
      final cache = SourceCache();
      cache.recordSourceList(ref, [
        const StreamSource(
          id: 'c1',
          label: 'Server 4',
          providerId: 'nimora.cricfy',
        ),
      ]);
      cache.recordSourceList(ref, [
        const StreamSource(
          id: 'c2',
          label: 'Server 4',
          providerId: 'nimora.cricfy',
        ),
      ]);

      expect(cache.peekSourceList(ref), hasLength(1));
      expect(cache.peekSourceList(ref)!.single.id, 'c2');
    });

    test('recordSourceList persists through sourceListStore', () async {
      final store = FakeSourceListStore();
      final cache = SourceCache(sourceListStore: store);
      cache.recordSourceList(ref, [source('a')]);
      // Fire-and-forget — give the microtask a turn to run.
      await Future<void>.delayed(Duration.zero);
      expect(store.saved, hasLength(1));
      expect(store.saved.values.single.sources.single.id, 'a');
    });

    test('is seeded from initial without needing a record first', () {
      final seeded = CachedSourceList(
        ref: ref,
        sources: [source('a')],
        fetchedAt: DateTime(2026),
      );
      final cache = SourceCache(initial: {seeded.key: seeded});
      expect(cache.peekSourceList(ref)!.single.id, 'a');
    });

    test('evicts the oldest persisted entry once past maxPersistedEntries', () {
      const refA = MediaRef(extensionId: 'fvck', providerId: 'fvck.p', id: 'a');
      const refB = MediaRef(extensionId: 'fvck', providerId: 'fvck.p', id: 'b');
      const refC = MediaRef(extensionId: 'fvck', providerId: 'fvck.p', id: 'c');
      var now = DateTime(2026);
      final cache = SourceCache(maxPersistedEntries: 2, now: () => now);
      cache.recordSourceList(refA, [source('x')]);
      now = now.add(const Duration(minutes: 1));
      cache.recordSourceList(refB, [source('x')]);
      now = now.add(const Duration(minutes: 1));
      cache.recordSourceList(refC, [source('x')]);

      expect(cache.peekSourceList(refA), isNull); // evicted — oldest
      expect(cache.peekSourceList(refB), isNotNull);
      expect(cache.peekSourceList(refC), isNotNull);
    });
  });

  group('promote', () {
    test('moves the named source to the front of the resolved list', () {
      final cache = SourceCache();
      cache.store(ref, [resolved('a'), resolved('b'), resolved('c')]);
      cache.promote(ref, 'b');
      expect(cache.peek(ref)!.map((s) => s.source.id), ['b', 'a', 'c']);
    });

    test('also moves it to the front of the persisted source list', () {
      final cache = SourceCache();
      cache.recordSourceList(ref, [source('a'), source('b'), source('c')]);
      cache.promote(ref, 'b');
      expect(cache.peekSourceList(ref)!.map((s) => s.id), ['b', 'a', 'c']);
    });

    test('promotes both halves in one call when both are populated', () {
      final cache = SourceCache();
      cache.store(ref, [resolved('a'), resolved('b')]);
      cache.recordSourceList(ref, [source('a'), source('b')]);
      cache.promote(ref, 'b');
      expect(cache.peek(ref)!.map((s) => s.source.id), ['b', 'a']);
      expect(cache.peekSourceList(ref)!.map((s) => s.id), ['b', 'a']);
    });

    test('promoting the source already in front is a no-op', () {
      final cache = SourceCache();
      final sources = [resolved('a'), resolved('b')];
      cache.store(ref, sources);
      cache.promote(ref, 'a');
      expect(cache.peek(ref)!.map((s) => s.source.id), ['a', 'b']);
    });

    test('promoting an id not in either list does nothing', () {
      final cache = SourceCache();
      cache.store(ref, [resolved('a'), resolved('b')]);
      cache.promote(ref, 'z');
      expect(cache.peek(ref)!.map((s) => s.source.id), ['a', 'b']);
    });

    test('promoting against an uncached ref does nothing, does not throw', () {
      final cache = SourceCache();
      expect(() => cache.promote(ref, 'a'), returnsNormally);
      expect(cache.peek(ref), isNull);
      expect(cache.peekSourceList(ref), isNull);
    });

    test(
      'persists the reordered persisted list through sourceListStore',
      () async {
        final store = FakeSourceListStore();
        final cache = SourceCache(sourceListStore: store);
        cache.recordSourceList(ref, [source('a'), source('b')]);
        cache.promote(ref, 'b');
        await Future<void>.delayed(Duration.zero);
        expect(store.saved.values.single.sources.map((s) => s.id), ['b', 'a']);
      },
    );
  });
}
