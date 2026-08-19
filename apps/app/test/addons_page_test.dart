import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_app/addons/addons_controller.dart';
import 'package:fvcksubs_app/addons/addons_page.dart';
import 'package:fvcksubs_app/addons/installer_controller.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';

import 'support/harness.dart';

void main() {
  testWidgets('lists an installed extension with its name and categories', (
    tester,
  ) async {
    final registry = ExtensionRegistry([
      FakeExtension(id: 'fake', categories: ['live', 'sport']),
    ]);

    await tester.pumpWidget(
      wrapApp(child: const AddonsPage(), registry: registry),
    );
    await tester.pumpAndSettle();

    expect(find.text('fake'), findsOneWidget);
    expect(find.text('live, sport'), findsOneWidget);
  });

  testWidgets('the extension switch reflects and toggles enabled state', (
    tester,
  ) async {
    final registry = ExtensionRegistry([
      FakeExtension(id: 'fake', categories: ['sport']),
    ]);
    final store = FakeAddonSettingsStore();
    final controller = AddonsController(registry: registry, store: store);

    await tester.pumpWidget(
      wrapApp(
        child: const AddonsPage(),
        registry: registry,
        addonsController: controller,
      ),
    );
    await tester.pumpAndSettle();

    final extensionSwitch = find.byType(SwitchListTile).first;
    expect(tester.widget<SwitchListTile>(extensionSwitch).value, isTrue);

    await tester.tap(extensionSwitch);
    await tester.pumpAndSettle();

    expect(registry.isExtensionEnabled('fake'), isFalse);
    expect(tester.widget<SwitchListTile>(extensionSwitch).value, isFalse);
  });

  testWidgets(
    'a stream provider gets its own switch, independent of the extension',
    (tester) async {
      final registry = ExtensionRegistry([
        FakeExtension(id: 'fake', categories: ['sport']),
      ]);
      final controller = AddonsController(
        registry: registry,
        store: FakeAddonSettingsStore(),
      );

      await tester.pumpWidget(
        wrapApp(
          child: const AddonsPage(),
          registry: registry,
          addonsController: controller,
        ),
      );
      await tester.pumpAndSettle();

      final switches = find.byType(SwitchListTile);
      expect(switches, findsNWidgets(2));
      final providerSwitch = switches.at(1);

      await tester.tap(providerSwitch);
      await tester.pumpAndSettle();

      // The provider is off, but the extension itself is untouched.
      expect(registry.isProviderEnabled('fake.p'), isFalse);
      expect(registry.isExtensionEnabled('fake'), isTrue);
    },
  );

  testWidgets('turning the extension off disables its provider switch too', (
    tester,
  ) async {
    final registry = ExtensionRegistry([
      FakeExtension(id: 'fake', categories: ['sport']),
    ]);
    final controller = AddonsController(
      registry: registry,
      store: FakeAddonSettingsStore(),
    );

    await tester.pumpWidget(
      wrapApp(
        child: const AddonsPage(),
        registry: registry,
        addonsController: controller,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(SwitchListTile).first);
    await tester.pumpAndSettle();

    final providerSwitch = tester.widget<SwitchListTile>(
      find.byType(SwitchListTile).at(1),
    );
    expect(providerSwitch.value, isFalse);
    expect(providerSwitch.onChanged, isNull);
  });

  testWidgets('no extensions installed shows an honest empty state', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrapApp(child: const AddonsPage(), registry: ExtensionRegistry([])),
    );
    await tester.pumpAndSettle();

    expect(find.text('No extensions installed.'), findsOneWidget);
  });

  group('the repo / installer section', () {
    /// A controller whose repo has already been "checked", without any
    /// network: the UI's job here is rendering what the controller holds,
    /// and installer_controller_test.dart covers the fetching itself.
    InstallerController controllerWith({
      required ExtensionRegistry registry,
      String? installedVersion,
    }) {
      final store = FakeInstalledExtensionStore();
      if (installedVersion != null) {
        store.saved['remote_ext'] = InstalledExtension(
          id: 'remote_ext',
          version: installedVersion,
          manifestJson: '{}',
          bundleJs: '',
        );
      }
      return InstallerController(
        registry: registry,
        installer: ExtensionInstaller(),
        installedStore: store,
        repoStore: FakeRepoStore(),
        repoUrl: 'https://example.invalid/repo.json',
      );
    }

    testWidgets('shows the saved repo URL in the field', (tester) async {
      final registry = ExtensionRegistry([FakeExtension(id: 'fake')]);
      await tester.pumpWidget(
        wrapApp(
          child: const AddonsPage(),
          registry: registry,
          installerController: controllerWith(registry: registry),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Extension repo'), findsOneWidget);
      expect(find.text('https://example.invalid/repo.json'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Check'), findsOneWidget);
    });

    testWidgets('an unreachable repo surfaces its error in the UI', (
      tester,
    ) async {
      final registry = ExtensionRegistry([FakeExtension(id: 'fake')]);
      final controller = controllerWith(registry: registry);

      await tester.pumpWidget(
        wrapApp(
          child: const AddonsPage(),
          registry: registry,
          installerController: controller,
        ),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Check'));
      await tester.pumpAndSettle();

      // Honest failure, not a silent no-op: the user needs to know the repo
      // did not answer.
      expect(find.textContaining('Could not read the repo'), findsOneWidget);
    });

    testWidgets('installed extensions still list below the repo section', (
      tester,
    ) async {
      final registry = ExtensionRegistry([
        FakeExtension(id: 'fake', categories: ['live']),
      ]);
      await tester.pumpWidget(
        wrapApp(
          child: const AddonsPage(),
          registry: registry,
          installerController: controllerWith(registry: registry),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Extension repo'), findsOneWidget);
      expect(find.text('fake'), findsOneWidget);
    });
  });

  testWidgets('an extension tile shows its description and author', (
    tester,
  ) async {
    final registry = ExtensionRegistry([
      FakeExtension(
        id: 'fake',
        categories: ['live'],
        description: 'Football fixtures and streams.',
        author: 'Someone',
      ),
    ]);

    await tester.pumpWidget(
      wrapApp(child: const AddonsPage(), registry: registry),
    );
    await tester.pumpAndSettle();

    expect(find.text('Football fixtures and streams.'), findsOneWidget);
    expect(find.textContaining('by Someone'), findsOneWidget);
  });

  testWidgets('an extension without a description still lists cleanly', (
    tester,
  ) async {
    final registry = ExtensionRegistry([
      FakeExtension(id: 'fake', categories: ['live']),
    ]);

    await tester.pumpWidget(
      wrapApp(child: const AddonsPage(), registry: registry),
    );
    await tester.pumpAndSettle();

    expect(find.text('fake'), findsOneWidget);
    expect(find.text('live'), findsOneWidget);
  });

  testWidgets('a long description can expand without breaking narrow reflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final description = List.filled(
      18,
      'A detailed explanation of the extension capabilities.',
    ).join(' ');
    final registry = ExtensionRegistry([
      FakeExtension(
        id: 'verbose',
        categories: ['live'],
        description: description,
      ),
    ]);

    await tester.pumpWidget(
      wrapApp(child: const AddonsPage(), registry: registry),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Show more'), findsOneWidget);

    await tester.ensureVisible(find.text('Show more'));
    await tester.tap(find.text('Show more'));
    await tester.pumpAndSettle();

    expect(find.text('Show less'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
