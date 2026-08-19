import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'legacy_user_media_state.dart';

/// Persists Library records (favourites, history, continue-watching) across
/// app restarts.
abstract class LegacyLibraryStore {
  /// Loads every saved record, keyed by [LegacyUserMediaState.key].
  Future<Map<String, LegacyUserMediaState>> load();

  /// Saves the full set of records, replacing whatever was there before.
  Future<void> save(Map<String, LegacyUserMediaState> records);
}

/// [LegacyLibraryStore] backed by `shared_preferences` — the whole set as one
/// JSON-encoded string. Fine at Library's scale (favourites/history for one
/// person); revisit if this ever needs indexing or partial writes.
class SharedPreferencesLegacyLibraryStore implements LegacyLibraryStore {
  static const String _key = 'library.records';

  @override
  Future<Map<String, LegacyUserMediaState>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return {};
    final decoded = jsonDecode(raw) as List<Object?>;
    final records = <String, LegacyUserMediaState>{};
    for (final entry in decoded) {
      final state = LegacyUserMediaState.fromJson(
        entry! as Map<String, Object?>,
      );
      records[state.key] = state;
    }
    return records;
  }

  @override
  Future<void> save(Map<String, LegacyUserMediaState> records) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode([
      for (final state in records.values) state.toJson(),
    ]);
    await prefs.setString(_key, encoded);
  }
}
