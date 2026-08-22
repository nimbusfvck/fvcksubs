import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';

import 'catalog_page_store.dart';

class CatalogCache {
  CatalogCache({this.store});

  final CatalogPageStore? store;
  final Map<String, Future<VersionedCatalogPage>> _versionedEntries = {};
  final Map<String, VersionedCatalogPage> _versionedCompleted = {};
  final Map<String, Future<VersionedCatalogPage>> _versionedRefreshes = {};

  static String _keyOf(CatalogBinding binding, String category) =>
      '${binding.extensionId}@${binding.extension.manifest.version}/'
      '${binding.catalog.id}/$category';

  VersionedCatalogPage? peekVersioned(
    CatalogBinding binding,
    String category,
  ) => _versionedCompleted[_keyOf(binding, category)];

  /// Reads a prior app session's catalog without treating it as fresh session
  /// data. Home renders this snapshot, then refreshes it in the background.
  Future<VersionedCatalogPage?> readPersistedVersioned(
    CatalogBinding binding,
    String category,
  ) =>
      store?.read(_keyOf(binding, category)) ??
      Future<VersionedCatalogPage?>.value(null);

  Future<VersionedCatalogPage> load(
    ExtensionRegistry registry,
    CatalogBinding binding, {
    required String category,
  }) {
    final key = _keyOf(binding, category);
    final existing = _versionedEntries[key];
    if (existing != null) return existing;

    final future = _loadPersistedOrFetch(registry, binding, category: category)
        .then((page) {
          _versionedCompleted[key] = page;
          return page;
        })
        .onError<Object>((error, stack) {
          _versionedEntries.remove(key);
          throw error;
        });
    _versionedEntries[key] = future;
    return future;
  }

  Future<VersionedCatalogPage> _loadPersistedOrFetch(
    ExtensionRegistry registry,
    CatalogBinding binding, {
    required String category,
  }) async {
    final key = _keyOf(binding, category);
    final cached = await store?.read(key);
    if (cached != null) return cached;
    final page = await registry.loadCatalog(binding, category: category);
    await store?.write(key, page);
    return page;
  }

  Future<VersionedCatalogPage> reload(
    ExtensionRegistry registry,
    CatalogBinding binding, {
    required String category,
  }) {
    final key = _keyOf(binding, category);
    final refreshing = _versionedRefreshes[key];
    if (refreshing != null) return refreshing;

    final future = registry
        .loadCatalog(binding, category: category)
        .then((page) async {
          _versionedCompleted[key] = page;
          await store?.write(key, page);
          return page;
        })
        .onError<Object>((error, stack) {
          _versionedEntries.remove(key);
          throw error;
        });
    _versionedEntries[key] = future;
    _versionedRefreshes[key] = future;
    future.then<void>(
      (_) => _versionedRefreshes.remove(key),
      onError: (Object _, StackTrace _) => _versionedRefreshes.remove(key),
    );
    return future;
  }

  /// Uses the session cache unless an explicit refresh is requested.
  Future<VersionedCatalogPage> fetchCatalog(
    ExtensionRegistry registry,
    CatalogBinding binding, {
    required String category,
    bool refresh = false,
  }) => refresh
      ? reload(registry, binding, category: category)
      : load(registry, binding, category: category);

  void clear() {
    _versionedEntries.clear();
    _versionedCompleted.clear();
    _versionedRefreshes.clear();
  }
}

VersionedCatalogPage mergeVersionedCatalogPages(
  VersionedCatalogPage current,
  VersionedCatalogPage next,
) {
  final sections = [...current.sections];
  for (final incoming in next.sections) {
    final index = sections.indexWhere((section) => section.id == incoming.id);
    if (index < 0) {
      sections.add(incoming);
      continue;
    }
    final existing = sections[index];
    sections[index] = CatalogSectionV2(
      id: existing.id,
      title: existing.title ?? incoming.title,
      items: [...existing.items, ...incoming.items],
    );
  }
  return VersionedCatalogPage(
    sections: sections,
    nextPage: next.nextPage,
    subCategories: next.subCategories.isEmpty
        ? current.subCategories
        : next.subCategories,
  );
}
