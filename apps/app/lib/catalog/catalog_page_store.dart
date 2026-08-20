import 'dart:convert';

import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast_io.dart';

abstract interface class CatalogPageStore {
  Future<VersionedCatalogPage?> read(String key);
  Future<void> write(String key, VersionedCatalogPage page);
  Future<void> removeByPrefix(String prefix);
}

class SembastCatalogPageStore implements CatalogPageStore {
  SembastCatalogPageStore._(this._database);

  final Database _database;
  final StoreRef<String, String> _store = StoreRef<String, String>('catalogs');

  static Future<SembastCatalogPageStore> open() async {
    final directory = await getApplicationSupportDirectory();
    return SembastCatalogPageStore._(
      await databaseFactoryIo.openDatabase(
        '${directory.path}/catalog_cache.db',
      ),
    );
  }

  @override
  Future<VersionedCatalogPage?> read(String key) async {
    final value = await _store.record(key).get(_database);
    if (value == null) return null;
    try {
      return VersionedCatalogPage.fromProtocolJson(
        (jsonDecode(value) as Map).cast<String, Object?>(),
        apiVersion: 2,
      );
    } catch (_) {
      await _store.record(key).delete(_database);
      return null;
    }
  }

  @override
  Future<void> write(String key, VersionedCatalogPage page) =>
      _store.record(key).put(_database, jsonEncode(page.toJson()));

  @override
  Future<void> removeByPrefix(String prefix) async {
    final keys = await _store.findKeys(_database);
    await _store
        .records(keys.where((key) => key.startsWith(prefix)))
        .delete(_database);
  }
}
