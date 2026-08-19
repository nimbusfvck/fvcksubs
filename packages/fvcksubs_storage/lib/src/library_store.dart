import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'user_media_state.dart';

/// Persists protocol-v2 library and playback records.
abstract class LibraryStore {
  /// Loads all records by their stable key.
  Future<Map<String, UserMediaState>> load();

  /// Replaces the persisted record set.
  Future<void> save(Map<String, UserMediaState> records);
}

/// Shared-preferences implementation of [LibraryStore].
class SharedPreferencesLibraryStore implements LibraryStore {
  static const String _key = 'library.records.v2';

  @override
  Future<Map<String, UserMediaState>> load() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_key);
    if (raw == null) return {};
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      throw const FormatException('library records must be a list');
    }
    final records = <String, UserMediaState>{};
    for (final entry in decoded) {
      if (entry is! Map) {
        throw const FormatException('library record must be an object');
      }
      final state = UserMediaState.fromJson(entry.cast<String, Object?>());
      records[state.key] = state;
    }
    return records;
  }

  @override
  Future<void> save(Map<String, UserMediaState> records) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _key,
      jsonEncode([for (final state in records.values) state.toJson()]),
    );
  }
}
