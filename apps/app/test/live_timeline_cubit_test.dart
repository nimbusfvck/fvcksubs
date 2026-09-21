import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_app/catalog/catalog_cache.dart';
import 'package:fvcksubs_app/catalog/live_timeline_cubit.dart';
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';

import 'support/harness.dart';

void main() {
  test(
    'reuses the selected sport refresh and refreshes other providers',
    () async {
      final selected = FakeExtension(id: 'selected');
      final other = FakeExtension(id: 'other');
      final registry = ExtensionRegistry([selected, other]);
      final cache = CatalogCache();
      final cubit = CatalogTimelineCubit(
        catalogCache: cache,
        registry: registry,
      );
      addTearDown(cubit.close);

      final bindings = registry.catalogsFor('sport');
      await cubit.load(bindings, category: 'sport');
      expect(selected.catalogCalls, 1);
      expect(other.catalogCalls, 1);

      final selectedBinding = bindings.singleWhere(
        (binding) => binding.extensionId == selected.id,
      );
      await cache.fetchCatalog(
        registry,
        selectedBinding,
        category: 'sport',
        refresh: true,
      );

      await cubit.load(
        bindings,
        category: 'sport',
        refresh: true,
        shouldRefreshBinding: (binding) => binding.extensionId != selected.id,
      );

      expect(selected.catalogCalls, 2);
      expect(other.catalogCalls, 2);
    },
  );
}
