import 'package:shared_preferences/shared_preferences.dart';

/// The user's global mature-content visibility preference.
class NsfwSettings {
  /// Creates a mature-content visibility snapshot.
  const NsfwSettings({this.showNsfw = false});

  /// Whether the user allows catalogs marked as NSFW.
  final bool showNsfw;
}

/// Persists the NSFW visibility preference across app restarts.
abstract class NsfwSettingsStore {
  /// Loads the saved preference.
  Future<NsfwSettings> load();

  /// Persists the preference.
  Future<void> save(NsfwSettings settings);
}

/// Shared Preferences implementation of [NsfwSettingsStore].
class SharedPreferencesNsfwSettingsStore implements NsfwSettingsStore {
  static const _showNsfwKey = 'content.showNsfw';

  @override
  Future<NsfwSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return NsfwSettings(showNsfw: prefs.getBool(_showNsfwKey) ?? false);
  }

  @override
  Future<void> save(NsfwSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_showNsfwKey, settings.showNsfw);
  }
}
