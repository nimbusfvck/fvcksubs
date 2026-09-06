import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_app/player/state/source_priority_controller.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';
import 'package:fvcksubs_storage/fvcksubs_storage.dart';

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

  test('empty Settings order preserves discovery order', () {
    final registry = ExtensionRegistry([
      FakeExtension(id: 'first', providerName: 'Atlas'),
      FakeExtension(id: 'second', providerName: 'Boreal'),
    ]);
    final controller = SourcePriorityController(
      registry: registry,
      store: FakeSourcePriorityStore(),
    );

    expect(
      controller
          .order(const [
            StreamSource(id: 'b', label: 'B', providerId: 'second.p'),
            StreamSource(id: 'a', label: 'A', providerId: 'first.p'),
          ])
          .map((source) => source.id),
      ['b', 'a'],
    );
  });

  test(
    'locale metadata prefers a matching provider when no manual order exists',
    () {
      final registry = ExtensionRegistry([
        FakeExtension(
          id: 'global',
          providerLocales: const ProviderLocales(
            countries: ['US'],
            languages: ['en'],
          ),
        ),
        FakeExtension(
          id: 'local',
          providerLocales: const ProviderLocales(
            countries: ['ID'],
            languages: ['id'],
          ),
        ),
      ]);
      final controller = SourcePriorityController(
        registry: registry,
        store: FakeSourcePriorityStore(),
        sourceLocale: SourceLocalePreference.indonesia,
      );

      expect(
        controller
            .order(const [
              StreamSource(
                id: 'global',
                label: 'Global',
                providerId: 'global.p',
              ),
              StreamSource(id: 'local', label: 'Local', providerId: 'local.p'),
            ])
            .map((source) => source.id),
        ['local', 'global'],
      );
    },
  );

  test('explicit provider order overrides locale ranking', () {
    final registry = ExtensionRegistry([
      FakeExtension(
        id: 'global',
        providerLocales: const ProviderLocales(
          countries: ['US'],
          languages: ['en'],
        ),
      ),
      FakeExtension(
        id: 'local',
        providerLocales: const ProviderLocales(
          countries: ['ID'],
          languages: ['id'],
        ),
      ),
    ]);
    final controller = SourcePriorityController(
      registry: registry,
      store: FakeSourcePriorityStore(),
      initial: const ['global.p'],
      sourceLocale: SourceLocalePreference.indonesia,
    );

    expect(
      controller
          .order(const [
            StreamSource(id: 'local', label: 'Local', providerId: 'local.p'),
            StreamSource(id: 'global', label: 'Global', providerId: 'global.p'),
          ])
          .map((source) => source.id),
      ['global', 'local'],
    );
  });
}
