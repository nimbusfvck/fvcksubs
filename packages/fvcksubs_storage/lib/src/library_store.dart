import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'user_media_state.dart';

/// Persists Library records (favourites, history, continue-watching) across
/// app restarts.
abstract class LibraryStore {
  /// Loads every saved record, keyed by [UserMediaState.key].
  Future<Map<String, UserMediaState>> load();

  /// Saves the full set of records, replacing whatever was there before.
  Future<void> save(Map<String, UserMediaState> records);
}

/// [LibraryStore] backed by `shared_preferences` — the whole set as one
/// JSON-encoded string. Fine at Library's scale (favourites/history for one
/// person); revisit if this ever needs indexing or partial writes.
class SharedPreferencesLibraryStore implements LibraryStore {
  static const String _key = 'library.records';

  @override
  Future<Map<String, UserMediaState>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return {};
    final decoded = jsonDecode(raw) as List<Object?>;
    final records = <String, UserMediaState>{};
    for (final entry in decoded) {
      final state = UserMediaState.fromJson(entry! as Map<String, Object?>);
      records[state.key] = state;
    }
    return records;
  }

  @override
  Future<void> save(Map<String, UserMediaState> records) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode([
      for (final state in records.values) state.toJson(),
    ]);
    await prefs.setString(_key, encoded);
  }
}
