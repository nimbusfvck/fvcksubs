import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_app/library/library_controller.dart';
import 'package:fvcksubs_app/library/library_page.dart';
import 'package:fvcksubs_app/player/player_page.dart';
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';
import 'package:fvcksubs_storage/fvcksubs_storage.dart';

import 'support/harness.dart';

void main() {
  LibraryController controllerWith(List<UserMediaState> records) =>
      LibraryController(
        store: FakeLibraryStore(),
        initial: {for (final r in records) r.key: r},
      );

  testWidgets('shows an honest empty state when nothing is saved', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrapApp(
        child: const LibraryPage(),
        registry: ExtensionRegistry([FakeExtension()]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Nothing here yet'), findsOneWidget);
  });

  testWidgets('renders Continue Watching, Favorites, and History sections', (
    tester,
  ) async {
    final favorited = fakeItem(id: 'fav', title: 'Favorited Match');
    final watching = fakeItem(id: 'watching', title: 'In Progress Match');

    final controller = controllerWith([
      UserMediaState(ref: favorited.ref, item: favorited, favorite: true),
      UserMediaState(
        ref: watching.ref,
        item: watching,
        progress: const Duration(minutes: 5),
        lastWatched: DateTime.now(),
      ),
    ]);

    await tester.pumpWidget(
      wrapApp(
        child: const LibraryPage(),
        registry: ExtensionRegistry([FakeExtension()]),
        libraryController: controller,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Continue Watching'), findsOneWidget);
    expect(find.text('Favorites'), findsOneWidget);
    // Every watched record also shows in History.
    expect(find.text('History'), findsOneWidget);
    expect(find.text('Favorited Match'), findsOneWidget);
    // Both progressed and watched, so it legitimately appears in both
    // Continue Watching and History.
    expect(find.text('In Progress Match'), findsNWidgets(2));
  });

  testWidgets('tapping an available record opens it (a live match: straight to the player)', (
    tester,
  ) async {
    final favorited = fakeItem(id: 'fav', title: 'Favorited Match');
    final controller = controllerWith([
      UserMediaState(ref: favorited.ref, item: favorited, favorite: true),
    ]);

    await tester.pumpWidget(
      wrapApp(
        child: const LibraryPage(),
        registry: ExtensionRegistry([
          FakeExtension(
            sourceList: const [StreamSource(id: 's', label: 'HD 1080p')],
            resolved: const PlayableStream(
              url: 'https://edge/live.m3u8',
              format: StreamFormat.hls,
            ),
          ),
        ]),
        libraryController: controller,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Favorited Match'));
    await tester.pumpAndSettle();

    expect(find.byType(PlayerPage), findsOneWidget);
  });

  testWidgets(
    'a record whose extension is no longer installed is dimmed and does not navigate',
    (tester) async {
      final orphan = fakeItem(
        id: 'gone',
        extensionId: 'uninstalled',
        title: 'Orphaned Match',
      );
      final controller = controllerWith([
        UserMediaState(ref: orphan.ref, item: orphan, favorite: true),
      ]);

      await tester.pumpWidget(
        wrapApp(
          // The registry only has "fake" installed, not "uninstalled".
          child: const LibraryPage(),
          registry: ExtensionRegistry([FakeExtension()]),
          libraryController: controller,
        ),
      );
      await tester.pumpAndSettle();

      final opacity = tester.widget<Opacity>(
        find.ancestor(
          of: find.text('Orphaned Match'),
          matching: find.byType(Opacity),
        ),
      );
      expect(opacity.opacity, lessThan(1));

      await tester.tap(find.text('Orphaned Match'));
      await tester.pumpAndSettle();

      expect(find.byType(PlayerPage), findsNothing);
      expect(find.textContaining('Install'), findsOneWidget);
    },
  );
}
