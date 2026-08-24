import 'dart:convert';

import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The subtitle language the viewer wants, as a primary language subtag
/// (`"id"`, `"en"`), or `null` for no preference.
///
/// Global and persistent, like the plugin choice: it describes what the
/// viewer wants out of any title, not where they are in the app.
///
/// It does two jobs, and the first is the less obvious one. Sources are
/// ordered by it before playback — a source carrying the preferred language
/// is played ahead of one that doesn't — because subtitles are a property of
/// the *source*, not of the title: the same film from two providers can come
/// with completely different tracks. Without this the viewer lands on
/// whichever source resolved first and has to hunt for one that happens to
/// carry their language.
abstract class SubtitlePreferenceStore {
  /// The preferred language subtag, or `null` when none is set.
  Future<String?> load();

  /// Saves [languageCode], or clears the preference when `null`.
  Future<void> save(String? languageCode);

  /// Loads the last explicitly selected external subtitle per media item.
  Future<Map<String, SubtitleTrack>> loadExternalSelections() async => {};

  /// Persists or clears an explicit external subtitle selection.
  Future<void> saveExternalSelection(MediaRef ref, SubtitleTrack? track) async {}

  /// Loads all external subtitle tracks fetched for each media item.
  Future<Map<String, List<SubtitleTrack>>> loadExternalTracks() async => {};

  /// Persists the external subtitle tracks fetched for [ref].
  Future<void> saveExternalTracks(
    MediaRef ref,
    List<SubtitleTrack> tracks,
  ) async {}
}

/// [SubtitlePreferenceStore] backed by `shared_preferences`.
class SharedPreferencesSubtitlePreferenceStore
    implements SubtitlePreferenceStore {
  /// Creates the store.
  const SharedPreferencesSubtitlePreferenceStore();

  static const String _key = 'playback.subtitleLanguage';
  static const String _externalKey = 'playback.externalSubtitleSelections';
  static const String _externalTracksKey = 'playback.externalSubtitleTracks';

  @override
  Future<String?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_key);
    return (value == null || value.isEmpty) ? null : value;
  }

  @override
  Future<void> save(String? languageCode) async {
    final prefs = await SharedPreferences.getInstance();
    if (languageCode == null || languageCode.isEmpty) {
      await prefs.remove(_key);
      return;
    }
    await prefs.setString(_key, languageCode);
  }

  @override
  Future<Map<String, SubtitleTrack>> loadExternalSelections() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_externalKey);
    if (raw == null || raw.isEmpty) return {};

    try {
      final decoded = jsonDecode(raw) as Map;
      return {
        for (final entry in decoded.entries)
          entry.key as String: SubtitleTrack.fromJson(
            (entry.value as Map).cast<String, Object?>(),
          ),
      };
    } on FormatException {
      return {};
    } on TypeError {
      return {};
    }
  }

  @override
  Future<void> saveExternalSelection(
    MediaRef ref,
    SubtitleTrack? track,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final selections = await loadExternalSelections();
    final key = _mediaKey(ref);
    if (track == null) {
      selections.remove(key);
    } else {
      selections[key] = track;
    }
    await prefs.setString(
      _externalKey,
      jsonEncode({
        for (final entry in selections.entries) entry.key: entry.value.toJson(),
      }),
    );
  }

  @override
  Future<Map<String, List<SubtitleTrack>>> loadExternalTracks() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_externalTracksKey);
    if (raw == null || raw.isEmpty) return {};

    try {
      final decoded = jsonDecode(raw) as Map;
      return {
        for (final entry in decoded.entries)
          entry.key as String: [
            for (final value in (entry.value as List))
              SubtitleTrack.fromJson((value as Map).cast<String, Object?>()),
          ],
      };
    } on FormatException {
      return {};
    } on TypeError {
      return {};
    }
  }

  @override
  Future<void> saveExternalTracks(
    MediaRef ref,
    List<SubtitleTrack> tracks,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final records = await loadExternalTracks();
    final key = _mediaKey(ref);
    if (tracks.isEmpty) {
      records.remove(key);
    } else {
      records[key] = List.of(tracks);
    }
    await prefs.setString(
      _externalTracksKey,
      jsonEncode({
        for (final entry in records.entries)
          entry.key: [for (final track in entry.value) track.toJson()],
      }),
    );
  }

  static String _mediaKey(MediaRef ref) =>
      '${ref.extensionId}\u0000${ref.providerId}\u0000${ref.id}';
}

/// Persists the preferred order of stable stream-provider ids.
abstract class SourcePriorityStore {
  /// Loads provider ids from highest to lowest priority.
  Future<List<String>> load();

  /// Replaces the saved provider order.
  Future<void> save(List<String> providerIds);
}

/// [SourcePriorityStore] backed by `shared_preferences`.
class SharedPreferencesSourcePriorityStore implements SourcePriorityStore {
  /// Creates the shared-preferences-backed store.
  const SharedPreferencesSourcePriorityStore();

  static const String _key = 'playback.sourcePriority';

  @override
  Future<List<String>> load() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_key) ?? const [];
  }

  @override
  Future<void> save(List<String> providerIds) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, providerIds);
  }
}
