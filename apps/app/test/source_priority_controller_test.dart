import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_app/player/source_priority_controller.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';

import 'support/harness.dart';

void main() {
  test('reorder persists provider ids and orders discovered sources', () async {
    final registry = ExtensionRegistry([
      FakeExtension(id: 'first', providerName: 'Atlas'),
      FakeExtension(id: 'second', providerName: 'Boreal'),
    ]);
    final store = FakeSourcePriorityStore();
    final controller = SourcePriorityController(
      registry: registry,
      store: store,
    );

    controller.reorder(1, 0);
    await Future<void>.delayed(Duration.zero);

    expect(controller.state.orderedProviderIds, ['second.p', 'first.p']);
    expect(store.saved, ['second.p', 'first.p']);
    expect(
      controller
          .order(const [
            StreamSource(id: 'a', label: 'A', providerId: 'first.p'),
            StreamSource(id: 'b', label: 'B', providerId: 'second.p'),
          ])
          .map((source) => source.id),
      ['b', 'a'],
    );
  });

  test('unknown providers retain discovery order after preferred ones', () {
    final registry = ExtensionRegistry([FakeExtension(id: 'first')]);
    final controller = SourcePriorityController(
      registry: registry,
      store: FakeSourcePriorityStore(),
      initial: const ['first.p'],
    );

    expect(
      controller
          .order(const [
            StreamSource(id: 'x', label: 'X'),
            StreamSource(id: 'a', label: 'A', providerId: 'first.p'),
            StreamSource(id: 'y', label: 'Y'),
          ])
          .map((source) => source.id),
      ['a', 'x', 'y'],
    );
  });
}
