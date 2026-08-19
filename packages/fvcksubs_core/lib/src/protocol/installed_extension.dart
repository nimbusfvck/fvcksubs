import 'package:equatable/equatable.dart';

/// One extension `ExtensionInstaller` (`fvcksubs_extension_host`) has
/// downloaded and hash-verified, ready to load or already installed — its
/// manifest and bundle content, exactly as downloaded, plus the version they
/// came from so a later repo check can tell whether a newer one is
/// available.
///
/// Lives here, not in `fvcksubs_extension_host` or `fvcksubs_storage`,
/// because both need it and neither should depend on the other:
/// `fvcksubs_extension_host` stays pure Dart (no Flutter), and
/// `fvcksubs_storage` needs `shared_preferences` (Flutter) to persist it —
/// `fvcksubs_core` is the one place both already depend on.
class InstalledExtension extends Equatable {
  /// Creates a record.
  const InstalledExtension({
    required this.id,
    required this.version,
    required this.manifestJson,
    required this.bundleJs,
  });

  /// Parses one record from JSON.
  factory InstalledExtension.fromJson(Map<String, Object?> json) =>
      InstalledExtension(
        id: json['id']! as String,
        version: json['version']! as String,
        manifestJson: json['manifestJson']! as String,
        bundleJs: json['bundleJs']! as String,
      );

  /// Extension id.
  final String id;

  /// Version this record was installed at.
  final String version;

  /// The downloaded `manifest.json`, verbatim.
  final String manifestJson;

  /// The downloaded `bundle.js`, verbatim.
  final String bundleJs;

  /// Encodes to a JSON map.
  Map<String, Object?> toJson() => {
    'id': id,
    'version': version,
    'manifestJson': manifestJson,
    'bundleJs': bundleJs,
  };

  @override
  List<Object?> get props => [id, version, manifestJson, bundleJs];
}
