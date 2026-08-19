import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_app/catalog/catalog_view.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';

import 'support/harness.dart';

/// Subcategory chips in [CatalogView] — the drill-down screen, where the
/// filter bar already lives.
///
/// These are not declared: they arrive with
/// the catalog response, so the tests drive them by what the fake extension
/// returns rather than by anything in its manifest.
void main() {
  MediaItem item(String id, String title) => MediaItem(
    ref: MediaRef(extensionId: 'fake', providerId: 'fake.p', id: id),
    kind: MediaKind.liveEvent,
    title: title,
    startsAt: DateTime.utc(2026, 8, 19),
  );

  FakeExtension extensionWith({List<SubCategory> subCategories = const []}) =>
      FakeExtension(
        id: 'fake',
        categories: ['live'],
        items: [item('1', 'Everything A'), item('2', 'Everything B')],
        subCategories: subCategories,
        itemsBySubCategory: {
          'epl': [item('3', 'Only EPL')],
        },
      );

  Future<void> pump(WidgetTester tester, FakeExtension extension) async {
    final registry = ExtensionRegistry([extension]);
    await tester.pumpWidget(
      wrapApp(
        registry: registry,
        child: CatalogView(binding: registry.catalogsFor('live').single),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('no subcategories returned means no chip row at all', (
    tester,
  ) async {
    await pump(tester, extensionWith());

    expect(find.text('All'), findsNothing);
    expect(find.text('Everything A'), findsOneWidget);
  });

  testWidgets('chips render from the response, with a leading All', (
    tester,
  ) async {
    await pump(
      tester,
      extensionWith(
        subCategories: const [
          SubCategory(id: 'epl', name: 'Premier League'),
          SubCategory(id: 'liga1', name: 'Liga 1'),
        ],
      ),
    );

    expect(find.text('All'), findsOneWidget);
    expect(find.text('Premier League'), findsOneWidget);
    expect(find.text('Liga 1'), findsOneWidget);
  });

  testWidgets('picking one refetches narrowed and keeps the chips', (
    tester,
  ) async {
    final extension = extensionWith(
      subCategories: const [SubCategory(id: 'epl', name: 'Premier League')],
    );
    await pump(tester, extension);

    expect(find.text('Everything A'), findsOneWidget);

    await tester.tap(find.text('Premier League'));
    await tester.pumpAndSettle();

    expect(extension.lastSubCategory, 'epl');
    expect(find.text('Only EPL'), findsOneWidget);
    expect(find.text('Everything A'), findsNothing);
    // The chips must survive being used — otherwise there is no way back.
    expect(find.text('Premier League'), findsOneWidget);
    expect(find.text('All'), findsOneWidget);
  });

  testWidgets('All clears the narrowing', (tester) async {
    final extension = extensionWith(
      subCategories: const [SubCategory(id: 'epl', name: 'Premier League')],
    );
    await pump(tester, extension);

    await tester.tap(find.text('Premier League'));
    await tester.pumpAndSettle();
    expect(extension.lastSubCategory, 'epl');

    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();

    expect(extension.lastSubCategory, isNull);
    expect(find.text('Everything A'), findsOneWidget);
  });
}
