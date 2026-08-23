import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_app/addons/addons_controller.dart';
import 'package:fvcksubs_app/platform/device_class.dart';
import 'package:fvcksubs_app/shell/home_shell.dart';
import 'package:fvcksubs_app/widgets/app_page_bar.dart';
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';

import 'support/harness.dart';

void main() {
  testWidgets('nav is fixed and does not depend on installed extensions', (
    tester,
  ) async {
    // Same four destinations whether one extension is installed or none —
    // that's the point of moving nav out of the registry.
    for (final registry in [
      ExtensionRegistry([
        FakeExtension(categories: ['sport']),
      ]),
      ExtensionRegistry([]),
    ]) {
      await tester.pumpWidget(
        wrapApp(child: const HomeShell(), registry: registry),
      );
      await tester.pump();

      expect(find.widgetWithText(NavigationBar, 'Home'), findsOneWidget);
      expect(find.widgetWithText(NavigationBar, 'Library'), findsOneWidget);
      expect(find.widgetWithText(NavigationBar, 'Addons'), findsOneWidget);
      expect(find.widgetWithText(NavigationBar, 'Settings'), findsOneWidget);
      // Search is not a destination — it opens from Home as its own screen.
      expect(find.widgetWithText(NavigationBar, 'Search'), findsNothing);
    }
  });

  testWidgets('switching destination swaps the body', (tester) async {
    await tester.pumpWidget(
      wrapApp(
        child: const HomeShell(),
        registry: ExtensionRegistry([FakeExtension()]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('home-logo-title')), findsOneWidget);

    await tester.tap(find.text('Library'));
    await tester.pumpAndSettle();

    // A real LibraryPage now — empty because nothing's been favorited or
    // watched in this fresh session, not because it isn't built.
    expect(find.text('No favorites yet'), findsOneWidget);
    expect(find.widgetWithText(AppPageBar, 'Library'), findsOneWidget);

    await tester.tap(find.text('Addons'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppPageBar, 'Addons'), findsOneWidget);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppPageBar, 'Settings'), findsOneWidget);
  });

  testWidgets('settings is a real destination', (tester) async {
    await tester.pumpWidget(
      wrapApp(child: const HomeShell(), registry: ExtensionRegistry([])),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Preferred subtitles'), findsOneWidget);
    expect(find.text('Indonesia'), findsOneWidget);
  });

  testWidgets(
    'toggling an extension off in Addons hides it on Home immediately',
    (tester) async {
      final registry = ExtensionRegistry([
        FakeExtension(
          id: 'fake',
          categories: ['sport'],
          items: [fakeItem(title: 'Some Match')],
        ),
      ]);
      final controller = AddonsController(
        registry: registry,
        store: FakeAddonSettingsStore(),
      );

      await tester.pumpWidget(
        wrapApp(
          child: const HomeShell(),
          registry: registry,
          addonsController: controller,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const Key('home-catalog-content')),
          matching: find.text('Some Match'),
        ),
        findsOneWidget,
      );

      // Not find.widgetWithText(NavigationBar, ...): that resolves to the
      // whole bar and taps its bounding-box center, which only happens to
      // land on the right destination for items near the middle.
      await tester.tap(find.text('Addons'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();

      // The registry's own state changed in place — HomePage only reflects
      // it because HomeShell listens to the same AddonsController and
      // rebuilds whichever tab is showing.
      expect(
        find.descendant(
          of: find.byKey(const Key('home-catalog-content')),
          matching: find.text('Some Match'),
        ),
        findsNothing,
      );
    },
  );

  testWidgets('TV gets a rail instead of a bottom bar', (tester) async {
    await tester.pumpWidget(
      wrapApp(
        child: const HomeShell(),
        registry: ExtensionRegistry([FakeExtension()]),
        deviceClass: DeviceClass.tv,
      ),
    );
    await tester.pump();

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('expanded sectioned catalogs keep their section heading', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrapApp(
        child: const HomeShell(),
        registry: ExtensionRegistry([
          FakeExtension(
            categories: ['nsfw'],
            expanded: true,
            sectionTitle: 'Section title',
            items: [fakeItem(title: 'Catalog item')],
          ),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Section title'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('home-catalog-content')),
        matching: find.text('Catalog item'),
      ),
      findsOneWidget,
    );
  });
}
