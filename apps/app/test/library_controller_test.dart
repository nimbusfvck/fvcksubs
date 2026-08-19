import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_app/library/library_controller.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_storage/fvcksubs_storage.dart';

import 'support/harness.dart';

void main() {
  MediaItem item({String id = 'e1', String title = 'Home vs Away'}) =>
      MediaItem(
        ref: MediaRef(extensionId: 'fake', providerId: 'fake.p', id: id),
        kind: MediaKind.liveEvent,
        title: title,
      );

  test('toggleFavorite flips the flag, persists, and notifies', () async {
    final store = FakeLibraryStore();
    final controller = LibraryController(store: store);
    var notified = 0;
    controller.addListener(() => notified++);

    controller.toggleFavorite(item());
    expect(controller.isFavorite(item().ref), isTrue);
    expect(notified, 1);
    await Future<void>.delayed(Duration.zero);
    expect(store.saved.values.single.favorite, isTrue);

    controller.toggleFavorite(item());
    expect(controller.isFavorite(item().ref), isFalse);
    expect(notified, 2);
  });

  test('un-favoriting an item with no watch history drops the record', () async {
    final controller = LibraryController(store: FakeLibraryStore());
    controller.toggleFavorite(item());
    expect(controller.favorites, hasLength(1));

    controller.toggleFavorite(item());
    expect(controller.favorites, isEmpty);
  });

  test('favoriting keeps a watched record instead of dropping it', () {
    final controller = LibraryController(store: FakeLibraryStore());
    controller.recordWatched(item());
    controller.toggleFavorite(item());
    controller.toggleFavorite(item()); // un-favorite again
    // Still watched, so it should still show up in history.
    expect(controller.history, hasLength(1));
  });

  test('recordWatched sets lastWatched/progress and surfaces in history', () {
    final controller = LibraryController(store: FakeLibraryStore());
    controller.recordWatched(item(), progress: const Duration(minutes: 3));

    expect(controller.history, hasLength(1));
    expect(controller.history.single.progress, const Duration(minutes: 3));
    expect(controller.continueWatching, hasLength(1));
  });

  test('continueWatching excludes records with no progress', () {
    final controller = LibraryController(store: FakeLibraryStore());
    controller.recordWatched(item()); // no progress passed
    expect(controller.continueWatching, isEmpty);
    expect(controller.history, hasLength(1));
  });

  test(
    'recordWatched with no progress preserves a previously saved position',
    () {
      // The bug this guards: opening the player calls recordWatched(item)
      // with no progress — the resume point of a previous watch used to
      // get wiped to null right then, before playback ever had a chance
      // to report a fresh one, so resuming never actually worked.
      final controller = LibraryController(store: FakeLibraryStore());
      controller.recordWatched(item(), progress: const Duration(minutes: 12));

      controller.recordWatched(item()); // player re-opening, no progress yet

      expect(controller.recordFor(item().ref)?.progress, const Duration(minutes: 12));
    },
  );

  test('recordWatched still sets lastWatched when progress is omitted', () {
    final controller = LibraryController(store: FakeLibraryStore());
    controller.recordWatched(item());
    expect(controller.recordFor(item().ref)?.lastWatched, isNotNull);
  });

  test('recordWatched can still explicitly clear progress', () {
    final controller = LibraryController(store: FakeLibraryStore());
    controller.recordWatched(item(), progress: const Duration(minutes: 12));

    controller.recordWatched(item(), progress: null);

    expect(controller.recordFor(item().ref)?.progress, isNull);
    expect(controller.continueWatching, isEmpty);
  });

  test('history is sorted most-recently-watched first', () {
    final controller = LibraryController(store: FakeLibraryStore());
    controller.recordWatched(item(id: 'older'));
    controller.recordWatched(item(id: 'newer'));

    expect(
      controller.history.map((s) => s.ref.id).toList(),
      ['newer', 'older'],
    );
  });

  test('favorites are sorted alphabetically by title', () {
    final controller = LibraryController(store: FakeLibraryStore());
    controller.toggleFavorite(item(id: 'b', title: 'Zebra'));
    controller.toggleFavorite(item(id: 'a', title: 'Apple'));

    expect(
      controller.favorites.map((s) => s.item.title).toList(),
      ['Apple', 'Zebra'],
    );
  });

  test('starts seeded from initial records', () {
    final seed = UserMediaState(ref: item().ref, item: item(), favorite: true);
    final controller = LibraryController(
      store: FakeLibraryStore(),
      initial: {seed.key: seed},
    );
    expect(controller.isFavorite(item().ref), isTrue);
  });
}
