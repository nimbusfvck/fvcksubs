import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:dio/dio.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';

/// Thrown when a download, hash check, or manifest check fails during
/// install.
class ExtensionInstallException implements Exception {
  /// Creates an install exception.
  const ExtensionInstallException(this.message);

  /// Human-readable reason.
  final String message;

  @override
  String toString() => 'ExtensionInstallException: $message';
}

/// Downloads and verifies extensions from a repo (PLAN.md §20).
///
/// Deliberately storage-agnostic: [download] returns an [InstalledExtension]
/// value rather than persisting it, so this class stays pure Dart (no
/// Flutter, no `shared_preferences`) — the caller decides where a verified
/// download goes. That caller is app code today; nothing here is wired into
/// `main.dart` yet (see PLAN.md's M22 notes for what's still open: repo
/// hosting, an update-check trigger, and permission-diff re-consent UI).
class ExtensionInstaller {
  /// Creates an installer over its own [Dio], or a caller-supplied one (a
  /// fake adapter or the app's shared instance).
  ExtensionInstaller({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  /// Fetches and parses a repo's `repo.json`.
  Future<ExtensionRepo> fetchRepo(String repoUrl) async {
    final text = await _getText(repoUrl);
    return ExtensionRepo.fromJson(jsonDecode(text) as Map<String, Object?>);
  }

  /// Which of [repo]'s extensions are new or newer than what's already
  /// installed, per [installedVersions] (extension id → installed version).
  ///
  /// Pure comparison, no network — call [fetchRepo] first, and read
  /// installed versions from wherever the caller persists them
  /// (`InstalledExtensionStore`, `fvcksubs_storage`).
  List<ExtensionRepoEntry> checkForUpdates(
    ExtensionRepo repo,
    Map<String, String> installedVersions,
  ) => [
    for (final entry in repo.extensions)
      if (_isNewerOrMissing(entry.version, installedVersions[entry.id]))
        entry,
  ];

  /// Downloads [entry]'s manifest and bundle, verifies the bundle's SHA-256
  /// against [ExtensionRepoEntry.bundleSha256], and confirms the manifest's
  /// own `id` matches [entry.id] — a mismatched manifest (wrong extension,
  /// or a repo entry pointing at the wrong URL) fails loudly here rather
  /// than silently installing under the wrong id.
  ///
  /// **Hash only, not yet signature** (PLAN.md §19's "signed bundles"
  /// mitigation). This proves the download matches what `repo.json` itself
  /// currently claims — catches transit corruption and a bundle URL that's
  /// been swapped without updating the hash next to it — but nothing here
  /// verifies `repo.json`'s own integrity against a trusted key. Whoever can
  /// edit (or intercept) `repo.json` can currently point `bundleSha256` at
  /// whatever they replaced the bundle with. Real signature verification
  /// needs a keypair and a place for the app to carry the public half,
  /// neither of which exist yet — see PLAN.md §20's implementation note.
  ///
  /// Throws [ExtensionInstallException] on any mismatch. Never returns a
  /// partially-verified result — either every check passes, or nothing is
  /// handed back for the caller to persist.
  Future<InstalledExtension> download(ExtensionRepoEntry entry) async {
    final manifestJson = await _getText(entry.manifestUrl);
    final bundleJs = await _getText(entry.bundleUrl);

    final actualHash = crypto.sha256
        .convert(utf8.encode(bundleJs))
        .toString();
    final expectedHash = entry.bundleSha256.toLowerCase();
    if (actualHash != expectedHash) {
      throw ExtensionInstallException(
        'Hash mismatch for ${entry.id}: expected $expectedHash, got $actualHash',
      );
    }

    final Manifest manifest;
    try {
      manifest = Manifest.parse(
        jsonDecode(manifestJson) as Map<String, Object?>,
      );
    } on Object catch (e) {
      throw ExtensionInstallException(
        '${entry.id}: manifest failed to parse ($e)',
      );
    }
    if (manifest.id != entry.id) {
      throw ExtensionInstallException(
        'Manifest id "${manifest.id}" does not match repo entry "${entry.id}"',
      );
    }

    return InstalledExtension(
      id: entry.id,
      version: entry.version,
      manifestJson: manifestJson,
      bundleJs: bundleJs,
    );
  }

  Future<String> _getText(String url) async {
    final response = await _dio.get<String>(
      url,
      options: Options(responseType: ResponseType.plain),
    );
    return response.data ?? '';
  }

  static bool _isNewerOrMissing(String candidate, String? installed) {
    if (installed == null) return true;
    return isVersionNewer(candidate, installed);
  }

  /// Whether [candidate] is newer than [installed] using the repo's dotted
  /// integer version rules.
  static bool isVersionNewer(String candidate, String installed) =>
      _compareVersions(candidate, installed) > 0;

  /// Compares two dotted-integer version strings ("0.2.0" vs "0.10.0"),
  /// numeric per segment rather than lexicographic — "0.10.0" is newer than
  /// "0.9.0". A missing or non-numeric segment reads as 0. No `pub_semver`
  /// dependency: every version in this repo is already this plain shape,
  /// and pre-release/build-metadata suffixes aren't in use anywhere yet.
  static int _compareVersions(String a, String b) {
    final partsA = a.split('.');
    final partsB = b.split('.');
    final length = partsA.length > partsB.length
        ? partsA.length
        : partsB.length;
    for (var i = 0; i < length; i++) {
      final numA = i < partsA.length ? int.tryParse(partsA[i]) ?? 0 : 0;
      final numB = i < partsB.length ? int.tryParse(partsB[i]) ?? 0 : 0;
      if (numA != numB) return numA.compareTo(numB);
    }
    return 0;
  }
}
