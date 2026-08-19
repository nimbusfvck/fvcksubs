import 'dart:convert';

import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists installed (downloaded) extensions across app restarts.
///
/// [InstalledExtension] itself lives in `fvcksubs_core` — see its doc
/// comment for why.
abstract class InstalledExtensionStore {
  /// Loads every installed extension, keyed by [InstalledExtension.id].
  Future<Map<String, InstalledExtension>> loadAll();

  /// Saves one extension, replacing any earlier version of the same id.
  Future<void> save(InstalledExtension extension);

  /// Removes an installed extension, if present.
  Future<void> remove(String id);
}

/// [InstalledExtensionStore] backed by `shared_preferences` — the whole set
/// as one JSON-encoded string, same choice `SharedPreferencesLibraryStore`
/// makes and for the same reason: fine at this scale (a handful of
/// extensions), not indexed or partial-write. A bundle is tens of KB of
/// text; revisit (a real file store, `path_provider`) if that stops being
/// true — many extensions, or bundles large enough that rewriting the whole
/// set on every install gets expensive.
class SharedPreferencesInstalledExtensionStore
    implements InstalledExtensionStore {
  static const String _key = 'extensions.installed';

  @override
  Future<Map<String, InstalledExtension>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return {};
    final decoded = jsonDecode(raw) as List<Object?>;
    final extensions = [
      for (final entry in decoded)
        InstalledExtension.fromJson(entry! as Map<String, Object?>),
    ];
    return {for (final e in extensions) e.id: e};
  }

  @override
  Future<void> save(InstalledExtension extension) async {
    final all = await loadAll();
    all[extension.id] = extension;
    await _write(all);
  }

  @override
  Future<void> remove(String id) async {
    final all = await loadAll();
    if (all.remove(id) == null) return;
    await _write(all);
  }

  Future<void> _write(Map<String, InstalledExtension> all) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode([for (final e in all.values) e.toJson()]);
    await prefs.setString(_key, encoded);
  }
}
