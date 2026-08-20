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

    final extensionSwitch = find.byType(Switch).first;
    expect(tester.widget<Switch>(extensionSwitch).value, isTrue);

    await tester.tap(extensionSwitch);
    await tester.pumpAndSettle();

    expect(registry.isExtensionEnabled('fake'), isFalse);
    expect(tester.widget<Switch>(extensionSwitch).value, isFalse);
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

      await tester.tap(find.text('fake'));
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

  testWidgets('uses the provider display name without exposing its id', (
    tester,
  ) async {
    final registry = ExtensionRegistry([
      FakeExtension(id: 'fake', providerName: 'Atlas'),
    ]);

    await tester.pumpWidget(
      wrapApp(child: const AddonsPage(), registry: registry),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('fake'));
    await tester.pumpAndSettle();

    expect(find.text('Atlas'), findsOneWidget);
    expect(find.text('P'), findsNothing);
  });

  testWidgets('installed detail exposes a manual update check', (tester) async {
    final registry = ExtensionRegistry([FakeExtension(id: 'fake')]);
    final installerController = InstallerController(
      registry: registry,
      installer: ExtensionInstaller(),
      installedStore: FakeInstalledExtensionStore(),
      repoStore: FakeRepoStore(),
      repoUrl: 'https://example.invalid/repo.json',
    );

    await tester.pumpWidget(
      wrapApp(
        child: const AddonsPage(),
        registry: registry,
        installerController: installerController,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('fake'));
    await tester.pumpAndSettle();

    final checkButton = find.widgetWithText(
      OutlinedButton,
      'Check for updates',
    );
    expect(checkButton, findsOneWidget);
    expect(tester.widget<OutlinedButton>(checkButton).onPressed, isNotNull);
  });

  testWidgets('remove asks for confirmation and uninstalls the extension', (
    tester,
  ) async {
    final registry = ExtensionRegistry([FakeExtension(id: 'fake')]);
    final store = FakeInstalledExtensionStore();
    await store.save(
      const InstalledExtension(
        id: 'fake',
        version: '1.0.0',
        manifestJson: '{}',
        bundleJs: '',
      ),
    );
    final installerController = InstallerController(
      registry: registry,
      installer: ExtensionInstaller(),
      installedStore: store,
      repoStore: FakeRepoStore(),
    );

    await tester.pumpWidget(
      wrapApp(
        child: const AddonsPage(),
        registry: registry,
        installerController: installerController,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('fake'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Remove extension'));
    await tester.pumpAndSettle();
    expect(find.text('Remove fake?'), findsOneWidget);
    expect(registry.installed, isNotEmpty);

    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pumpAndSettle();

    expect(registry.installed, isEmpty);
    expect(store.saved, isEmpty);
    expect(find.text('No extensions installed.'), findsOneWidget);
  });

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

    await tester.tap(find.text('fake'));
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
    expect(
      find.text('Tap Add to load a repository and install an extension.'),
      findsOneWidget,
    );
    expect(find.text('Installed'), findsNothing);
  });

  group('the add-extension dialog', () {
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

    testWidgets('Add opens the saved repo URL in the install dialog', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final registry = ExtensionRegistry([FakeExtension(id: 'fake')]);
      await tester.pumpWidget(
        wrapApp(
          child: const AddonsPage(),
          registry: registry,
          installerController: controllerWith(registry: registry),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      expect(find.text('Add extension'), findsOneWidget);
      expect(find.text('https://example.invalid/repo.json'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Check'), findsOneWidget);
      expect(tester.takeException(), isNull);
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
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Check'));
      await tester.pumpAndSettle();

      // Honest failure, not a silent no-op: the user needs to know the repo
      // did not answer.
      expect(find.textContaining('Check the URL'), findsOneWidget);
    });

    testWidgets('installed extensions stay on the Addons page', (tester) async {
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

      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(find.text('Extension repo'), findsNothing);
      expect(find.text('fake'), findsOneWidget);
    });
  });

  testWidgets('an extension tile keeps details out of the compact card', (
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

    expect(find.text('Football fixtures and streams.'), findsNothing);
    expect(find.textContaining('by Someone'), findsOneWidget);

    await tester.tap(find.text('fake'));
    await tester.pumpAndSettle();
    expect(find.text('Football fixtures and streams.'), findsOneWidget);
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

  testWidgets('a long description is hidden on the card and full in detail', (
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
    expect(find.text('Show more'), findsNothing);
    expect(find.text(description), findsNothing);

    await tester.tap(find.text('verbose'));
    await tester.pumpAndSettle();

    expect(tester.widget<Text>(find.text(description)).maxLines, isNull);
    expect(tester.takeException(), isNull);
  });
}
