import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';

class CatalogCache {
  final Map<String, Future<CatalogPage>> _entries = {};
  final Map<String, CatalogPage> _completed = {};
  final Map<String, Future<VersionedCatalogPage>> _versionedEntries = {};
  final Map<String, VersionedCatalogPage> _versionedCompleted = {};

  static String _keyOf(CatalogBinding binding, String category) =>
      '${binding.extensionId}@${binding.extension.manifest.version}/'
      '${binding.catalog.id}/$category';

  CatalogPage? peek(CatalogBinding binding, String category) =>
      _completed[_keyOf(binding, category)];

  VersionedCatalogPage? peekVersioned(
    CatalogBinding binding,
    String category,
  ) => _versionedCompleted[_keyOf(binding, category)];

  Future<CatalogPage> load(
    ExtensionRegistry registry,
    CatalogBinding binding, {
    required String category,
  }) {
    final key = _keyOf(binding, category);
    final existing = _entries[key];
    if (existing != null) return existing;

    final future = registry
        .loadCatalog(binding, category: category)
        .then((page) {
          _completed[key] = page;
          return page;
        })
        .onError<Object>((error, stack) {
          _entries.remove(key);
          throw error;
        });
    _entries[key] = future;
    return future;
  }

  Future<CatalogPage> reload(
    ExtensionRegistry registry,
    CatalogBinding binding, {
    required String category,
  }) {
    _entries.remove(_keyOf(binding, category));
    return load(registry, binding, category: category);
  }

  Future<VersionedCatalogPage> loadVersioned(
    ExtensionRegistry registry,
    CatalogBinding binding, {
    required String category,
  }) {
    final key = _keyOf(binding, category);
    final existing = _versionedEntries[key];
    if (existing != null) return existing;

    final future = registry
        .loadCatalogVersioned(binding, category: category)
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

  Future<VersionedCatalogPage> reloadVersioned(
    ExtensionRegistry registry,
    CatalogBinding binding, {
    required String category,
  }) {
    _versionedEntries.remove(_keyOf(binding, category));
    return loadVersioned(registry, binding, category: category);
  }

  /// Uses the session cache unless an explicit refresh is requested.
  Future<VersionedCatalogPage> fetchCatalog(
    ExtensionRegistry registry,
    CatalogBinding binding, {
    required String category,
    bool refresh = false,
  }) => refresh
      ? reloadVersioned(registry, binding, category: category)
      : loadVersioned(registry, binding, category: category);

  void clear() {
    _entries.clear();
    _completed.clear();
    _versionedEntries.clear();
    _versionedCompleted.clear();
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
