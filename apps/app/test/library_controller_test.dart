import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_app/library/library_controller.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_storage/fvcksubs_storage.dart';

void main() {
  VideoItemV2 item({String id = 'one', String title = 'Example'}) =>
      VideoItemV2(
        ref: MediaRef(extensionId: 'extension', providerId: 'provider', id: id),
        title: title,
      );

  test('toggleFavorite emits and persists the updated records', () async {
    final store = _MemoryLibraryStoreV2();
    final controller = LibraryController(store: store);

    controller.toggleFavorite(item());
    await Future<void>.delayed(Duration.zero);

    expect(controller.isFavorite(item().ref), isTrue);
    expect(store.records.values.single.favorite, isTrue);

    controller.toggleFavorite(item());
    expect(controller.isFavorite(item().ref), isFalse);
    expect(controller.state.records, isEmpty);
  });

  test('toggleReminder emits and persists the updated records', () async {
    final store = _MemoryLibraryStoreV2();
    final controller = LibraryController(store: store);

    controller.toggleReminder(item());
    await Future<void>.delayed(Duration.zero);

    expect(controller.isReminded(item().ref), isTrue);
    expect(store.records.values.single.reminder, isTrue);

    controller.toggleReminder(item());
    expect(controller.isReminded(item().ref), isFalse);
    expect(controller.state.records, isEmpty);
  });

  test('watching preserves progress when no new position is provided', () {
    final controller = LibraryController(
      store: _MemoryLibraryStoreV2(),
      now: () => DateTime.utc(2026, 8, 19),
    );

    controller.recordWatched(item(), progress: const Duration(minutes: 12));
    controller.recordWatched(item());

    expect(
      controller.recordFor(item().ref)?.progress,
      const Duration(minutes: 12),
    );
    expect(controller.history.single.lastWatched, DateTime.utc(2026, 8, 19));
  });

  test('watching persists the content rating for visibility filters', () {
    final controller = LibraryController(store: _MemoryLibraryStoreV2());

    controller.recordWatched(
      item(),
      contentRating: ContentRating.mature,
      progress: const Duration(minutes: 2),
    );
    controller.recordWatched(item(), progress: const Duration(minutes: 3));

    expect(
      controller.recordFor(item().ref)?.contentRating,
      ContentRating.mature,
    );
  });

  test('watching can explicitly clear progress', () {
    final controller = LibraryController(store: _MemoryLibraryStoreV2());
    controller.recordWatched(item(), progress: const Duration(minutes: 12));

    controller.recordWatched(item(), progress: null);

    expect(controller.recordFor(item().ref)?.progress, isNull);
    expect(controller.continueWatching, isEmpty);
  });

  test('continue watching excludes completed records', () {
    final controller = LibraryController(store: _MemoryLibraryStoreV2());
    controller.recordWatched(
      item(),
      progress: const Duration(minutes: 40),
      duration: const Duration(minutes: 40),
    );

    expect(controller.continueWatching, isEmpty);
    expect(controller.history, hasLength(1));
  });

  test('marking an item as watched removes it from continue watching', () {
    final controller = LibraryController(store: _MemoryLibraryStoreV2());
    controller.recordWatched(item(), progress: const Duration(minutes: 2));

    controller.markAsWatched(item());

    expect(controller.continueWatching, isEmpty);
    expect(controller.history, hasLength(1));
  });

  test('continue watching keeps only the latest episode per series', () {
    const seriesRef = MediaRef(
      extensionId: 'extension',
      providerId: 'provider',
      id: 'series',
    );
    const episode3 = EpisodeItemV2(
      ref: MediaRef(
        extensionId: 'extension',
        providerId: 'provider',
        id: 'episode-3',
      ),
      title: 'Episode 3',
      subtitle: 'Example',
      episode: EpisodeIdentity(
        parentRef: seriesRef,
        groupId: 'season-1',
        position: 3,
      ),
    );
    const episode1 = EpisodeItemV2(
      ref: MediaRef(
        extensionId: 'extension',
        providerId: 'provider',
        id: 'episode-1',
      ),
      title: 'Episode 1',
      subtitle: 'Example',
      episode: EpisodeIdentity(
        parentRef: seriesRef,
        groupId: 'season-1',
        position: 1,
      ),
    );
    var time = DateTime.utc(2026, 8, 19);
    final controller = LibraryController(
      store: _MemoryLibraryStoreV2(),
      now: () => time,
    );

    controller.recordWatched(episode3, progress: const Duration(minutes: 8));
    time = time.add(const Duration(minutes: 1));
    controller.recordWatched(episode1, progress: const Duration(minutes: 2));

    expect(controller.continueWatching, hasLength(1));
    expect(controller.continueWatching.single.item.ref, episode1.ref);
  });

  test('continue watching is capped at ten latest records', () {
    var time = DateTime.utc(2026, 8, 19);
    final controller = LibraryController(
      store: _MemoryLibraryStoreV2(),
      now: () => time,
    );

    for (var index = 0; index < 12; index++) {
      controller.recordWatched(
        item(id: 'video-$index'),
        progress: const Duration(minutes: 1),
      );
      time = time.add(const Duration(minutes: 1));
    }

    expect(controller.continueWatching, hasLength(10));
    expect(controller.continueWatching.first.ref.id, 'video-11');
    expect(controller.continueWatching.last.ref.id, 'video-2');
  });

  test('derived collections have stable ordering', () {
    var time = DateTime.utc(2026, 8, 19);
    final controller = LibraryController(
      store: _MemoryLibraryStoreV2(),
      now: () => time,
    );

    controller.toggleFavorite(item(id: 'z', title: 'Zulu'));
    controller.toggleFavorite(item(id: 'a', title: 'Alpha'));
    controller.recordWatched(item(id: 'older'));
    time = time.add(const Duration(minutes: 1));
    controller.recordWatched(item(id: 'newer'));

    expect(controller.favorites.map((record) => record.item.title), [
      'Alpha',
      'Zulu',
    ]);
    expect(controller.history.map((record) => record.ref.id), [
      'newer',
      'older',
    ]);
  });

  test('initial records are exposed as immutable state', () {
    final record = UserMediaState(item: item(), favorite: true);
    final initial = {record.key: record};
    final controller = LibraryController(
      store: _MemoryLibraryStoreV2(),
      initial: initial,
    );

    initial.clear();

    expect(controller.isFavorite(item().ref), isTrue);
    expect(() => controller.state.records.clear(), throwsUnsupportedError);
  });
}

class _MemoryLibraryStoreV2 implements LibraryStore {
  Map<String, UserMediaState> records = {};

  @override
  Future<Map<String, UserMediaState>> load() async => Map.of(records);

  @override
  Future<void> save(Map<String, UserMediaState> records) async {
    this.records = Map.of(records);
  }
}
