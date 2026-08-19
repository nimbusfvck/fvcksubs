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

  test('watching can explicitly clear progress', () {
    final controller = LibraryController(store: _MemoryLibraryStoreV2());
    controller.recordWatched(item(), progress: const Duration(minutes: 12));

    controller.recordWatched(item(), progress: null);

    expect(controller.recordFor(item().ref)?.progress, isNull);
    expect(controller.continueWatching, isEmpty);
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
