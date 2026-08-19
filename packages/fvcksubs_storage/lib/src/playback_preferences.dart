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
}

/// [SubtitlePreferenceStore] backed by `shared_preferences`.
class SharedPreferencesSubtitlePreferenceStore
    implements SubtitlePreferenceStore {
  /// Creates the store.
  const SharedPreferencesSubtitlePreferenceStore();

  static const String _key = 'playback.subtitleLanguage';

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
}
