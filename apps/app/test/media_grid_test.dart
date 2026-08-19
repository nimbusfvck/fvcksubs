import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_app/catalog/media_grid.dart';

import 'support/harness.dart';

void main() {
  testWidgets('event items use a fixed row height, not a poster aspect ratio', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaGrid(
          items: [
            fakeItem(id: 'a'),
            fakeItem(id: 'b'),
          ],
          onTap: (_) {},
        ),
      ),
    );
    await tester.pump();

    final delegate =
        tester.widget<GridView>(find.byType(GridView)).gridDelegate
            as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.mainAxisExtent, isNotNull);
  });

  testWidgets('any poster in the batch switches the whole grid to portrait', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaGrid(
          items: [
            fakeItem(id: 'a'), // no poster
            fakeItem(
              id: 'b',
              poster: const ImageRef('https://cdn.example/poster.jpg'),
            ),
          ],
          onTap: (_) {},
        ),
      ),
    );
    await tester.pump();

    final delegate =
        tester.widget<GridView>(find.byType(GridView)).gridDelegate
            as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.mainAxisExtent, isNull);
    expect(delegate.childAspectRatio, 0.6);
  });

  testWidgets('columns: 1 overrides the width-derived column count', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaGrid(
          items: [fakeItem(id: 'a'), fakeItem(id: 'b')],
          onTap: (_) {},
          columns: 1,
        ),
      ),
    );
    await tester.pump();

    final delegate =
        tester.widget<GridView>(find.byType(GridView)).gridDelegate
            as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.crossAxisCount, 1);
    // Same height as a grid cell: a single-column row is the same card
    // stretched wider, so a shorter row would only squeeze its artwork.
    expect(delegate.mainAxisExtent, 172);
  });

  testWidgets('a single-column row leaves the fixture room to render', (
    tester,
  ) async {
    // The reason `list` exists: at grid width the two sides got ~60pt each
    // and read as crests with no words. The names are one title line now,
    // but the row still has to give it real width.
    await tester.pumpWidget(
      MaterialApp(
        home: MediaGrid(
          items: [
            // The full production shape — banner, title, and a competition
            // line all take vertical room, which is what the row has to fit.
            fakeItem(
              id: 'a',
              title: 'Racing Santander vs Villarreal',
              subtitle: 'LaLiga',
              participants: const [
                Participant(name: 'Racing Santander'),
                Participant(name: 'Villarreal'),
              ],
            ),
          ],
          onTap: (_) {},
          columns: 1,
        ),
      ),
    );
    await tester.pump();

    final title = tester.getSize(find.text('Racing Santander vs Villarreal'));
    expect(title.width, greaterThan(120), reason: 'the fixture needs width');
    // The row's height is a fixed extent, so content that doesn't fit
    // overflows rather than growing — caught on device as a 4px overflow the
    // first time round.
    expect(tester.takeException(), isNull);
  });

  group('group headers', () {
    test('splits into runs of consecutive equal group', () {
      final groups = MediaGrid.groupsOf([
        fakeItem(id: 'a', group: 'LaLiga'),
        fakeItem(id: 'b', group: 'LaLiga'),
        fakeItem(id: 'c', group: 'Eredivisie'),
      ]);

      expect(groups.map((g) => g.label), ['LaLiga', 'Eredivisie']);
      expect(groups.first.items.map((i) => i.ref.id), ['a', 'b']);
      expect(groups.last.items.map((i) => i.ref.id), ['c']);
    });

    test('a label recurring after another stays two runs, not merged', () {
      // The extension owns the order (see MediaItem.group); re-merging would
      // silently reorder its list.
      final groups = MediaGrid.groupsOf([
        fakeItem(id: 'a', group: 'LaLiga'),
        fakeItem(id: 'b', group: 'Eredivisie'),
        fakeItem(id: 'c', group: 'LaLiga'),
      ]);

      expect(groups.map((g) => g.label), ['LaLiga', 'Eredivisie', 'LaLiga']);
    });

    test('ungrouped items form one unlabelled run', () {
      final groups = MediaGrid.groupsOf([
        fakeItem(id: 'a'),
        fakeItem(id: 'b'),
      ]);

      expect(groups, hasLength(1));
      expect(groups.single.label, isNull);
    });

    testWidgets('headings render when showGroupHeaders is on', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaGrid(
            items: [
              fakeItem(id: 'a', group: 'LaLiga'),
              fakeItem(id: 'b', group: 'Eredivisie'),
            ],
            onTap: (_) {},
            showGroupHeaders: true,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('LaLiga'), findsOneWidget);
      expect(find.text('Eredivisie'), findsOneWidget);
    });

    testWidgets('a heading is not repeated as the card subtitle', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaGrid(
            items: [
              fakeItem(
                id: 'a',
                subtitle: 'LaLiga',
                group: 'LaLiga',
                participants: const [
                  Participant(name: 'Racing Santander'),
                  Participant(name: 'Villarreal'),
                ],
              ),
            ],
            onTap: (_) {},
            showGroupHeaders: true,
            columns: 1,
          ),
        ),
      );
      await tester.pump();

      // Once as the heading, not again on the card underneath it.
      expect(find.text('LaLiga'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an ungrouped run keeps its subtitle', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaGrid(
            items: [fakeItem(id: 'a', subtitle: 'LaLiga')],
            onTap: (_) {},
            showGroupHeaders: true,
            columns: 1,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('LaLiga'), findsOneWidget);
    });

    testWidgets('a shelf (headers off) shows no headings', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaGrid(
            items: [
              fakeItem(id: 'a', group: 'LaLiga'),
              fakeItem(id: 'b', group: 'Eredivisie'),
            ],
            onTap: (_) {},
          ),
        ),
      );
      await tester.pump();

      expect(find.text('LaLiga'), findsNothing);
      expect(find.byType(GridView), findsOneWidget);
    });
  });
}
