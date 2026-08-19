import 'package:shared_preferences/shared_preferences.dart';

/// Which extensions and providers are switched off in Addons, as loaded (or
/// about to be saved) — a plain snapshot, independent of how it's persisted.
class AddonSettings {
  /// Creates a snapshot.
  const AddonSettings({
    this.disabledExtensionIds = const {},
    this.disabledProviderIds = const {},
  });

  /// Extension ids switched off.
  final Set<String> disabledExtensionIds;

  /// Provider ids (full, `"fvck.kora"`) switched off.
  final Set<String> disabledProviderIds;
}

/// Persists Addons on/off state across app restarts.
///
/// Lives here rather than in `fvcksubs_extension_host` (deliberately pure
/// Dart — see its pubspec) or loose inside the app: on/off state is app-owned
/// state, same family as Library's favourites/history, so it belongs in the
/// one local-storage package PLAN.md §15 describes, not scattered per
/// feature.
abstract class AddonSettingsStore {
  /// Loads the last-saved settings, or defaults (everything enabled) if
  /// nothing has been saved yet.
  Future<AddonSettings> load();

  /// Saves the current on/off state.
  Future<void> save(AddonSettings settings);
}

/// [AddonSettingsStore] backed by `shared_preferences`.
class SharedPreferencesAddonSettingsStore implements AddonSettingsStore {
  static const String _disabledExtensionsKey = 'addons.disabledExtensionIds';
  static const String _disabledProvidersKey = 'addons.disabledProviderIds';

  @override
  Future<AddonSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AddonSettings(
      disabledExtensionIds:
          (prefs.getStringList(_disabledExtensionsKey) ?? const []).toSet(),
      disabledProviderIds:
          (prefs.getStringList(_disabledProvidersKey) ?? const []).toSet(),
    );
  }

  @override
  Future<void> save(AddonSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _disabledExtensionsKey,
      settings.disabledExtensionIds.toList(),
    );
    await prefs.setStringList(
      _disabledProvidersKey,
      settings.disabledProviderIds.toList(),
    );
  }
}
