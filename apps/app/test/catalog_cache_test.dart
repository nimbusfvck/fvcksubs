import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_app/catalog/catalog_cache.dart';
import 'package:fvcksubs_app/catalog/catalog_page_store.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';

import 'support/harness.dart';

void main() {
  test('uses persistent page before calling the extension', () async {
    final extension = FakeExtension(categories: const ['sport']);
    final registry = ExtensionRegistry([extension]);
    final binding = registry.catalogsFor('sport').single;
    final store = _Store();
    final cache = CatalogCache(store: store);

    await cache.load(registry, binding, category: 'sport');
    final second = CatalogCache(store: store);
    await second.load(registry, binding, category: 'sport');

    expect(extension.catalogCalls, 1);
  });
}

class _Store implements CatalogPageStore {
  final values = <String, VersionedCatalogPage>{};
  @override
  Future<void> removeByPrefix(String prefix) async {}
  @override
  Future<VersionedCatalogPage?> read(String key) async => values[key];
  @override
  Future<void> write(String key, VersionedCatalogPage page) async =>
      values[key] = page;
}
