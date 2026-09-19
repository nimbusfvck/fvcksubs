import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
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

  StreamSource source(String id) => StreamSource(id: id, label: id);

  group('resolved stream policy', () {
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

    test('a provider refresh replaces its old descriptors only', () {
      final cache = SourceCache();
      cache.recordSourceList(ref, [
        const StreamSource(
          id: 'febbox-auto-old',
          label: 'Febbox Auto',
          providerId: 'nimora.showbox',
        ),
        const StreamSource(
          id: 'febbox-1080-old',
          label: 'Febbox 1080p',
          providerId: 'nimora.showbox',
        ),
        const StreamSource(
          id: 'other',
          label: 'Other source',
          providerId: 'nimora.other',
        ),
      ]);

      cache.recordSourceList(ref, [
        const StreamSource(
          id: 'febbox-auto-new',
          label: 'Febbox Auto',
          providerId: 'nimora.showbox',
        ),
      ]);

      expect(cache.peekSourceList(ref)!.map((entry) => entry.id), [
        'febbox-auto-new',
        'other',
      ]);
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
    test('also moves it to the front of the persisted source list', () {
      final cache = SourceCache();
      cache.recordSourceList(ref, [source('a'), source('b'), source('c')]);
      cache.promote(ref, 'b');
      expect(cache.peekSourceList(ref)!.map((s) => s.id), ['b', 'a', 'c']);
    });

    test('promoting against an uncached ref does nothing, does not throw', () {
      final cache = SourceCache();
      expect(() => cache.promote(ref, 'a'), returnsNormally);
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
