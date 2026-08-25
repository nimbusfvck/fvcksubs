import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_app/home/home_page.dart';
import 'package:fvcksubs_app/search/search_page.dart';
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';

import 'support/harness.dart';

/// Search: reached from Home, answered on a screen of its own.
void main() {
  ExtensionRegistry searchable() => ExtensionRegistry([
    FakeExtension(
      categories: ['sport'],
      items: [fakeItem(title: 'Browse Item')],
      searchable: true,
      searchResults: [fakeItem(id: 's1', title: 'Search Hit')],
    ),
  ]);

  testWidgets('Home shows a search action that opens the search screen', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrapApp(child: const HomePage(), registry: searchable()),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SearchPage), findsNothing);
    expect(find.byIcon(Icons.search), findsOneWidget);

    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();

    expect(find.byType(SearchPage), findsOneWidget);
  });

  testWidgets('typing runs a search once the keystrokes stop', (tester) async {
    await tester.pumpWidget(
      wrapApp(child: const SearchPage(), registry: searchable()),
    );
    await tester.pumpAndSettle();

    // Nothing is searched until something is typed.
    expect(
      find.text('Search across every installed extension.'),
      findsOneWidget,
    );

    await tester.enterText(find.byType(TextField), 'anything');
    // Past the debounce window — every keystroke would otherwise fan out to
    // every installed extension.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('Search Hit'), findsOneWidget);
  });

  testWidgets('clearing the box returns to the empty prompt', (tester) async {
    await tester.pumpWidget(
      wrapApp(child: const SearchPage(), registry: searchable()),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'anything');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('Search Hit'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(find.text('Search Hit'), findsNothing);
    expect(
      find.text('Search across every installed extension.'),
      findsOneWidget,
    );
  });

  testWidgets('a query with no hits says so', (tester) async {
    final registry = ExtensionRegistry([
      FakeExtension(categories: ['sport'], searchable: true),
    ]);

    await tester.pumpWidget(
      wrapApp(child: const SearchPage(), registry: registry),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'nothing matches this');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('No results.'), findsOneWidget);
  });

  group('scopes', () {
    late FakeExtension live;
    late FakeExtension movies;

    ExtensionRegistry twoCategories() {
      live = FakeExtension(
        id: 'a',
        categories: ['live'],
        searchable: true,
        searchResults: [fakeItem(id: 'a1', title: 'From Live')],
      );
      movies = FakeExtension(
        id: 'b',
        categories: ['movie'],
        searchable: true,
        searchResults: [
          fakeItem(id: 'b1', extensionId: 'b', title: 'From Movies'),
        ],
      );
      return ExtensionRegistry([live, movies]);
    }

    Future<void> type(WidgetTester tester) async {
      await tester.enterText(find.byType(TextField), 'anything');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
    }

    testWidgets('an unscoped search still fans out across categories', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrapApp(child: const SearchPage(), registry: twoCategories()),
      );
      await tester.pumpAndSettle();
      await type(tester);

      expect(find.text('From Live'), findsOneWidget);
      expect(find.text('From Movies'), findsOneWidget);
      // Unscoped is the default, and it reaches an extension as a null scope
      // — the same call an older host made before scopes existed.
      expect(live.searchCategories, [null]);
      expect(movies.searchCategories, [null]);
    });

    testWidgets('the scope row offers every searchable category', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrapApp(child: const SearchPage(), registry: twoCategories()),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('search-scope-chips')), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'All'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Live'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Movie'), findsOneWidget);
    });

    testWidgets('picking a scope asks only what declares it', (tester) async {
      await tester.pumpWidget(
        wrapApp(child: const SearchPage(), registry: twoCategories()),
      );
      await tester.pumpAndSettle();
      await type(tester);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Movie'));
      await tester.pumpAndSettle();

      expect(find.text('From Movies'), findsOneWidget);
      expect(find.text('From Live'), findsNothing);
      // Not merely filtered out of the results: the live extension is never
      // asked, so a scoped search costs nothing on providers that cannot
      // answer it.
      expect(movies.searchCategories, [null, 'movie']);
      expect(live.searchCategories, [null]);
    });

    testWidgets('a chip runs the search without waiting out the debounce', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrapApp(child: const SearchPage(), registry: twoCategories()),
      );
      await tester.pumpAndSettle();
      await type(tester);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Movie'));
      // No debounce window: tapping a chip is a decision, not a keystroke.
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('From Movies'), findsOneWidget);
    });

    testWidgets('no scope row when nothing declares a searchable category', (
      tester,
    ) async {
      // `all` is Home's "everything" chip, not a scope — an extension that
      // declares only that adds nothing for the row to offer.
      final registry = ExtensionRegistry([
        FakeExtension(
          categories: ['all'],
          searchable: true,
          searchResults: [fakeItem(id: 's1', title: 'Search Hit')],
        ),
      ]);

      await tester.pumpWidget(
        wrapApp(child: const SearchPage(), registry: registry),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('search-scope-chips')), findsNothing);
      expect(find.byType(ChoiceChip), findsNothing);
    });
  });
}
