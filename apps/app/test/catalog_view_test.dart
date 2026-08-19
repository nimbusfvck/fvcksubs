import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_app/catalog/catalog_view.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';

import 'support/harness.dart';

void main() {
  String today() {
    final now = DateTime.now();
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    return '${now.year}-$month-$day';
  }

  group('filters', () {
    testWidgets('no filter bar when the catalog declares none', (
      tester,
    ) async {
      final fake = FakeExtension(
        categories: ['sport'],
        items: [fakeItem(title: 'Item')],
      );
      final registry = ExtensionRegistry([fake]);
      final binding = registry.catalogsFor('sport').single;

      await tester.pumpWidget(
        wrapApp(child: CatalogView(binding: binding), registry: registry),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ActionChip), findsNothing);
    });

    testWidgets('a date filter defaults to today and is sent with the query', (
      tester,
    ) async {
      final fake = FakeExtension(
        categories: ['sport'],
        filterKeys: ['date'],
        items: [fakeItem(title: 'Item')],
      );
      final registry = ExtensionRegistry([fake]);
      final binding = registry.catalogsFor('sport').single;

      await tester.pumpWidget(
        wrapApp(child: CatalogView(binding: binding), registry: registry),
      );
      await tester.pumpAndSettle();

      expect(find.text('Today'), findsOneWidget);
      expect(fake.lastFilters, {'date': today()});
    });
  });

  group('pagination', () {
    testWidgets('scrolling near the bottom loads and appends the next page', (
      tester,
    ) async {
      List<MediaItem> page(int start, int count) => [
        for (var i = start; i < start + count; i++)
          fakeItem(id: 'm$i', title: 'Match $i'),
      ];

      final fake = FakeExtension(
        categories: ['sport'],
        pages: {
          null: CatalogPage(items: page(0, 10), nextPage: 'p2'),
          'p2': CatalogPage(items: page(10, 2)),
        },
      );
      final registry = ExtensionRegistry([fake]);
      final binding = registry.catalogsFor('sport').single;

      await tester.pumpWidget(
        wrapApp(child: CatalogView(binding: binding), registry: registry),
      );
      await tester.pumpAndSettle();

      expect(find.text('Match 0'), findsOneWidget);
      expect(find.text('Match 10'), findsNothing);

      await tester.fling(find.byType(GridView), const Offset(0, -600), 3000);
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.text('Match 10'), 200);
      expect(find.text('Match 10'), findsOneWidget);
    });

    testWidgets('a provider with no next page never tries to load more', (
      tester,
    ) async {
      final fake = FakeExtension(
        categories: ['sport'],
        items: [fakeItem(title: 'Only Item')],
      );
      final registry = ExtensionRegistry([fake]);
      final binding = registry.catalogsFor('sport').single;

      await tester.pumpWidget(
        wrapApp(child: CatalogView(binding: binding), registry: registry),
      );
      await tester.pumpAndSettle();

      await tester.fling(find.byType(GridView), const Offset(0, -600), 3000);
      await tester.pumpAndSettle();

      expect(find.text('Only Item'), findsOneWidget);
    });
  });

  group('states', () {
    testWidgets('an empty catalog shows an honest message', (tester) async {
      final registry = ExtensionRegistry([
        FakeExtension(categories: ['sport']),
      ]);
      final binding = registry.catalogsFor('sport').single;

      await tester.pumpWidget(
        wrapApp(child: CatalogView(binding: binding), registry: registry),
      );
      await tester.pumpAndSettle();

      expect(find.text('Nothing here right now.'), findsOneWidget);
    });
  });
}
