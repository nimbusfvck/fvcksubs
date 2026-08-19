import 'package:equatable/equatable.dart';

import '../json_util.dart';

/// Thrown when a repo index cannot be parsed.
class ExtensionRepoException implements Exception {
  /// Creates a repo exception.
  const ExtensionRepoException(this.message);

  /// Human-readable reason.
  final String message;

  @override
  String toString() => 'ExtensionRepoException: $message';
}

/// One installable extension, as listed in a repo's `repo.json` (PLAN.md
/// §20).
///
/// This is what an installer reads *before* downloading anything — [hosts]
/// is duplicated here from what the manifest itself will declare so a
/// permission prompt (not yet built) can show what an extension wants without
/// a download first. [bundleSha256] is the integrity check §20 calls
/// "verify hash/signature"; only the hash half is built so far — see
/// `ExtensionInstaller`'s doc comment.
class ExtensionRepoEntry extends Equatable {
  /// Creates an entry.
  const ExtensionRepoEntry({
    required this.id,
    required this.name,
    required this.version,
    required this.manifestUrl,
    required this.bundleUrl,
    required this.bundleSha256,
    this.hosts = const [],
    this.description,
    this.author,
    this.iconUrl,
    this.releaseNotes = const [],
  });

  /// Parses one entry from JSON.
  factory ExtensionRepoEntry.fromJson(Map<String, Object?> json) {
    try {
      return ExtensionRepoEntry(
        id: json['id']! as String,
        name: json['name']! as String,
        version: json['version']! as String,
        manifestUrl: json['manifestUrl']! as String,
        bundleUrl: json['bundleUrl']! as String,
        bundleSha256: json['bundleSha256']! as String,
        hosts: stringList(json['hosts']),
        description: json['description'] as String?,
        author: json['author'] as String?,
        iconUrl: json['iconUrl'] as String?,
        releaseNotes: stringList(json['releaseNotes']),
      );
    } on TypeError catch (e) {
      throw ExtensionRepoException('malformed repo entry: $e');
    }
  }

  /// Extension id.
  final String id;

  /// Display name, shown before install.
  final String name;

  /// Version string; compared against what's already installed to decide
  /// whether an update is available.
  final String version;

  /// Where to download this extension's manifest.
  final String manifestUrl;

  /// Where to download this extension's bundle.
  final String bundleUrl;

  /// Lowercase hex SHA-256 of the bundle's exact bytes, checked after
  /// download and before the bundle is ever evaluated.
  final String bundleSha256;

  /// Hosts this extension's manifest will declare — a preview, not the
  /// authority; the downloaded manifest's own `permissions.hosts` is what
  /// actually drives the engine's allowlist (`JsExtension.load`).
  final List<String> hosts;

  /// What this extension is for. Duplicated from the manifest for the same
  /// reason [hosts] is: the install prompt happens *before* the download, so
  /// anything the user needs in order to decide has to be readable from the
  /// index alone.
  final String? description;

  /// Who publishes it — asserted by the repo, verified by nothing yet.
  final String? author;

  /// Icon/logo URL, optional.
  final String? iconUrl;

  /// Short user-facing changes for this release, shown before an update.
  final List<String> releaseNotes;

  /// Encodes to a JSON map.
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'version': version,
    'manifestUrl': manifestUrl,
    'bundleUrl': bundleUrl,
    'bundleSha256': bundleSha256,
    if (hosts.isNotEmpty) 'hosts': hosts,
    if (description != null) 'description': description,
    if (author != null) 'author': author,
    if (iconUrl != null) 'iconUrl': iconUrl,
    if (releaseNotes.isNotEmpty) 'releaseNotes': releaseNotes,
  };

  @override
  List<Object?> get props => [
    id,
    name,
    version,
    manifestUrl,
    bundleUrl,
    bundleSha256,
    hosts,
    description,
    author,
    iconUrl,
    releaseNotes,
  ];
}

/// A repo's full index — every extension it offers.
class ExtensionRepo extends Equatable {
  /// Creates a repo index.
  const ExtensionRepo(this.extensions);

  /// Parses a whole `repo.json`.
  factory ExtensionRepo.fromJson(Map<String, Object?> json) {
    final raw = json['extensions'];
    if (raw is! List) {
      throw const ExtensionRepoException('repo.json has no "extensions" list');
    }
    try {
      return ExtensionRepo(
        raw
            .map((e) => ExtensionRepoEntry.fromJson(e as Map<String, Object?>))
            .toList(),
      );
    } on TypeError catch (e) {
      throw ExtensionRepoException('malformed repo.json: $e');
    }
  }

  /// Every extension this repo offers.
  final List<ExtensionRepoEntry> extensions;

  /// Encodes to a JSON map.
  Map<String, Object?> toJson() => {
    'extensions': [for (final e in extensions) e.toJson()],
  };

  @override
  List<Object?> get props => [extensions];
}
