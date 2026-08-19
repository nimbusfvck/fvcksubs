import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'user_media_state_v2.dart';

/// Persists protocol-v2 library and playback records.
abstract class LibraryStoreV2 {
  /// Loads all records by their stable key.
  Future<Map<String, UserMediaStateV2>> load();

  /// Replaces the persisted record set.
  Future<void> save(Map<String, UserMediaStateV2> records);
}

/// Shared-preferences implementation of [LibraryStoreV2].
class SharedPreferencesLibraryStoreV2 implements LibraryStoreV2 {
  static const String _key = 'library.records.v2';

  @override
  Future<Map<String, UserMediaStateV2>> load() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_key);
    if (raw == null) return {};
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      throw const FormatException('library records must be a list');
    }
    final records = <String, UserMediaStateV2>{};
    for (final entry in decoded) {
      if (entry is! Map) {
        throw const FormatException('library record must be an object');
      }
      final state = UserMediaStateV2.fromJson(entry.cast<String, Object?>());
      records[state.key] = state;
    }
    return records;
  }

  @override
  Future<void> save(Map<String, UserMediaStateV2> records) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _key,
      jsonEncode([for (final state in records.values) state.toJson()]),
    );
  }
}
