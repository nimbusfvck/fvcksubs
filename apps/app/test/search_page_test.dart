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

  testWidgets('results are not scoped to a category', (tester) async {
    // The reason search is its own screen: it fans out across every
    // extension, so a category chip sitting above it would misdescribe what
    // came back.
    final registry = ExtensionRegistry([
      FakeExtension(
        id: 'a',
        categories: ['live'],
        searchable: true,
        searchResults: [fakeItem(id: 'a1', title: 'From Live')],
      ),
      FakeExtension(
        id: 'b',
        categories: ['movie'],
        searchable: true,
        searchResults: [
          fakeItem(id: 'b1', extensionId: 'b', title: 'From Movies'),
        ],
      ),
    ]);

    await tester.pumpWidget(
      wrapApp(child: const SearchPage(), registry: registry),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'anything');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('From Live'), findsOneWidget);
    expect(find.text('From Movies'), findsOneWidget);
    expect(find.byType(ChoiceChip), findsNothing);
  });
}
