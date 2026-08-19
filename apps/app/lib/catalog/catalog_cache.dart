import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';

class CatalogCache {
  final Map<String, Future<CatalogPage>> _entries = {};
  final Map<String, CatalogPage> _completed = {};

  static String _keyOf(CatalogBinding binding, String category) =>
      '${binding.extensionId}/${binding.catalog.id}/$category';

  CatalogPage? peek(CatalogBinding binding, String category) =>
      _completed[_keyOf(binding, category)];

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

  void clear() {
    _entries.clear();
    _completed.clear();
  }
}
