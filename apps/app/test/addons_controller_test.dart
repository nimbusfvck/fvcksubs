import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_app/addons/addons_controller.dart';
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';

import 'support/harness.dart';

void main() {
  test(
    'setExtensionEnabled mutates the registry, persists, and emits',
    () async {
      final registry = ExtensionRegistry([
        FakeExtension(id: 'a', categories: ['sport']),
      ]);
      final store = FakeAddonSettingsStore();
      final controller = AddonsController(registry: registry, store: store);

      final emitted = controller.stream.first;

      controller.setExtensionEnabled('a', false);

      expect(registry.isExtensionEnabled('a'), isFalse);
      expect((await emitted).revision, 1);
      // Persistence is fire-and-forget — give the microtask queue a turn.
      await Future<void>.delayed(Duration.zero);
      expect(store.saved?.disabledExtensionIds, {'a'});
    },
  );

  test(
    'setProviderEnabled mutates the registry, persists, and emits',
    () async {
      final registry = ExtensionRegistry([
        FakeExtension(id: 'a', categories: ['sport']),
      ]);
      final store = FakeAddonSettingsStore();
      final controller = AddonsController(registry: registry, store: store);

      final emitted = controller.stream.first;

      controller.setProviderEnabled('a.p', false);

      expect(registry.isProviderEnabled('a.p'), isFalse);
      expect((await emitted).revision, 1);
      await Future<void>.delayed(Duration.zero);
      expect(store.saved?.disabledProviderIds, {'a.p'});
    },
  );
}
