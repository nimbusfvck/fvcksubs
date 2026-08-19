import 'package:fvcksubs_core/fvcksubs_core.dart';

/// One catalog an installed extension exposes, bound to the extension that owns
/// it — enough to query it and know where its items came from.
class CatalogBinding {
  /// Creates a binding.
  const CatalogBinding({
    required this.extension,
    required this.providerId,
    required this.catalog,
  });

  /// The extension that serves this catalog.
  final ContentExtension extension;

  /// The provider within [extension] that declares it.
  final String providerId;

  /// The catalog declaration.
  final CatalogDecl catalog;

  /// Categories this catalog serves.
  List<String> get categories => catalog.categories;

  /// Id of the owning extension.
  String get extensionId => extension.manifest.id;
}
