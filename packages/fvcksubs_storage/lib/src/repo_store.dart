import 'package:shared_preferences/shared_preferences.dart';

/// Persists the extension repo the user points the installer at (PLAN.md
/// §20's `repo.json`).
///
/// One URL, not a list: §20 describes a single `fvcksubs-extensions` repo,
/// and one field is a much simpler thing to put in front of a user than
/// add/remove list management. Multi-repo is a real feature (it's how
/// Cloudstream and Stremio work) but it is not this milestone, and nothing
/// here forecloses it — the store just grows a list later.
abstract class RepoStore {
  /// The saved repo URL, or `null` if the user has not set one.
  Future<String?> load();

  /// Saves [url], or clears it when `null`.
  Future<void> save(String? url);
}

/// [RepoStore] backed by `shared_preferences`.
class SharedPreferencesRepoStore implements RepoStore {
  static const String _key = 'extensions.repoUrl';

  @override
  Future<String?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_key);
    return (value == null || value.trim().isEmpty) ? null : value;
  }

  @override
  Future<void> save(String? url) async {
    final prefs = await SharedPreferences.getInstance();
    if (url == null || url.trim().isEmpty) {
      await prefs.remove(_key);
      return;
    }
    await prefs.setString(_key, url.trim());
  }
}
