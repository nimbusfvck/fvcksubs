import 'package:shared_preferences/shared_preferences.dart';

/// The category a browsing screen was last left on.
///
/// Scoped per screen (Home, Discover) rather than shared: this is *where the
/// user is*, not what they prefer. Browsing Sport in Discover shouldn't move
/// Home off Live. Contrast [PluginSelectionStore], which is global for the
/// opposite reason.
abstract class CategorySelectionStore {
  /// The last-selected category, or `null` if none has been chosen yet.
  Future<String?> load();

  /// Saves [category], or clears it when `null`.
  Future<void> save(String? category);
}

/// [CategorySelectionStore] backed by `shared_preferences`.
class SharedPreferencesCategorySelectionStore
    implements CategorySelectionStore {
  /// Creates a store for one screen.
  ///
  /// [scope] namespaces the key (`"home"`, `"discover"`) so two screens'
  /// positions don't land on the same preference.
  const SharedPreferencesCategorySelectionStore(this.scope);

  /// This store's screen, as a key namespace.
  final String scope;

  String get _key => 'browse.$scope.category';

  @override
  Future<String?> load() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key);
  }

  @override
  Future<void> save(String? category) async {
    final prefs = await SharedPreferences.getInstance();
    if (category == null) {
      await prefs.remove(_key);
      return;
    }
    await prefs.setString(_key, category);
  }
}

/// Which installed extension the user wants their content from.
///
/// Global — one setting for the whole app, not one per screen. Two extensions
/// can cover the same ground (both serving `sport` from different upstreams),
/// and picking between them is a statement about *which data you trust*, not
/// about the screen you happen to be on; Home and Discover disagreeing on it
/// would just be confusing.
///
/// Holds an extension id, never a catalog: a user picks a plugin, and the
/// catalog it serves the current category with follows from that.
abstract class PluginSelectionStore {
  /// The selected extension id, or `null` when the user has never picked —
  /// callers fall back to the first extension serving the category.
  Future<String?> load();

  /// Saves [extensionId], or clears the preference when `null`.
  Future<void> save(String? extensionId);
}

/// [PluginSelectionStore] backed by `shared_preferences`.
class SharedPreferencesPluginSelectionStore implements PluginSelectionStore {
  /// Creates the store.
  const SharedPreferencesPluginSelectionStore();

  static const String _key = 'browse.extensionId';

  @override
  Future<String?> load() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key);
  }

  @override
  Future<void> save(String? extensionId) async {
    final prefs = await SharedPreferences.getInstance();
    if (extensionId == null) {
      await prefs.remove(_key);
      return;
    }
    await prefs.setString(_key, extensionId);
  }
}
