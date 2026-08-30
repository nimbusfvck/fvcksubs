import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast_io.dart';

/// Where each installed extension's `host.storage` lives between launches.
///
/// One row per extension, holding that extension's whole snapshot. The rows
/// are small by construction — `MemoryExtensionStorage` caps both the number
/// of keys and each value — so reading every one at startup costs a single
/// query, which is what lets [ExtensionStorageHub.forExtension] hand out a
/// ready store synchronously while a bundle is being loaded.
abstract interface class ExtensionStorageStore {
  /// Every extension's snapshot, keyed by extension id.
  Future<Map<String, Map<String, Object?>>> loadAll();

  /// Replaces [extensionId]'s snapshot.
  Future<void> write(String extensionId, Map<String, Object?> snapshot);

  /// Drops [extensionId]'s snapshot — called when it is uninstalled.
  Future<void> remove(String extensionId);
}

/// [ExtensionStorageStore] backed by sembast, alongside the catalog cache.
class SembastExtensionStorageStore implements ExtensionStorageStore {
  SembastExtensionStorageStore._(this._database);

  final Database _database;
  final StoreRef<String, String> _store = StoreRef<String, String>(
    'extension_storage',
  );

  /// Opens (creating if needed) the on-disk database.
  static Future<SembastExtensionStorageStore> open() async {
    final directory = await getApplicationSupportDirectory();
    return SembastExtensionStorageStore._(
      await databaseFactoryIo.openDatabase(
        '${directory.path}/extension_storage.db',
      ),
    );
  }

  @override
  Future<Map<String, Map<String, Object?>>> loadAll() async {
    final records = await _store.find(_database);
    final out = <String, Map<String, Object?>>{};
    for (final record in records) {
      try {
        final decoded = jsonDecode(record.value);
        if (decoded is Map) out[record.key] = decoded.cast<String, Object?>();
      } catch (_) {
        // A row we can't read is a cache entry, not state worth recovering.
        await _store.record(record.key).delete(_database);
      }
    }
    return out;
  }

  @override
  Future<void> write(String extensionId, Map<String, Object?> snapshot) =>
      _store.record(extensionId).put(_database, jsonEncode(snapshot));

  @override
  Future<void> remove(String extensionId) =>
      _store.record(extensionId).delete(_database);
}

/// Hands each extension its own persisted [ExtensionStorage].
///
/// Hydrated once, before any bundle loads: [forExtension] is synchronous
/// because `JsExtension.load` is, and because an extension reading its cache
/// during startup must not race the read that fills it.
class ExtensionStorageHub {
  ExtensionStorageHub({this.store, Map<String, Map<String, Object?>>? initial})
    : _snapshots = {...?initial};

  /// Opens the hub with everything already on disk.
  ///
  /// A store that won't open is not worth failing startup over — the app
  /// carries on with in-memory storage, and every extension simply starts
  /// cold, the way it did before any of this existed.
  static Future<ExtensionStorageHub> open() async {
    try {
      final store = await SembastExtensionStorageStore.open();
      return ExtensionStorageHub(store: store, initial: await store.loadAll());
    } catch (error, stack) {
      debugPrint('Could not open extension storage: $error\n$stack');
      return ExtensionStorageHub();
    }
  }

  /// Where snapshots are persisted, or `null` to keep them in memory only.
  final ExtensionStorageStore? store;

  final Map<String, Map<String, Object?>> _snapshots;
  final Map<String, _PersistentExtensionStorage> _stores = {};

  /// [extensionId]'s storage, restored from disk the first time it's asked
  /// for and the same instance every time after — reinstalling an extension
  /// keeps the cache it already had, which is the point of persisting it.
  ExtensionStorage forExtension(String extensionId) {
    final existing = _stores[extensionId];
    if (existing != null) return existing;
    final created = _PersistentExtensionStorage(
      extensionId: extensionId,
      store: store,
    );
    created.restore(_snapshots[extensionId] ?? const {});
    _stores[extensionId] = created;
    return created;
  }

  /// Forgets [extensionId]'s cache, on disk and in memory.
  Future<void> remove(String extensionId) async {
    _stores.remove(extensionId);
    _snapshots.remove(extensionId);
    try {
      await store?.remove(extensionId);
    } catch (error, stack) {
      debugPrint('Could not drop storage for $extensionId: $error\n$stack');
    }
  }
}

/// A [MemoryExtensionStorage] that mirrors itself to disk after every change.
///
/// Writes are coalesced onto the next microtask and never awaited by the
/// caller: `host.storage.write` returns synchronously into JS, so a bundle
/// would have no way to await a disk write even if we wanted it to. A write
/// that fails leaves the in-memory value in place — the extension keeps its
/// cache for this session and simply starts cold next time.
class _PersistentExtensionStorage extends MemoryExtensionStorage {
  _PersistentExtensionStorage({required this.extensionId, required this.store});

  final String extensionId;
  final ExtensionStorageStore? store;

  bool _flushScheduled = false;

  @override
  void persist() {
    final target = store;
    if (target == null || _flushScheduled) return;
    _flushScheduled = true;
    scheduleMicrotask(() async {
      _flushScheduled = false;
      try {
        await target.write(extensionId, snapshot());
      } catch (error, stack) {
        debugPrint('Could not persist storage for $extensionId: $error\n$stack');
      }
    });
  }
}
