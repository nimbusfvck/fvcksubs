import 'package:equatable/equatable.dart';

import '../content/media_item.dart';
import '../json_util.dart';

/// A role a provider can fill. One provider may fill several.
enum ProviderRole {
  /// Lists items with filters (date, genre, page).
  catalog,

  /// Returns one item's detail.
  meta,

  /// Lists sources for an item and resolves one into a playable stream.
  stream,

  /// Free-text search.
  search,

  /// Looks up subtitles for an item independently of any stream source —
  /// a fallback for when a resolved source's own tracks are missing, out of
  /// sync, or erroring.
  subtitles,
}

/// Thrown when a manifest cannot be loaded — malformed, or a protocol version
/// this app can't run.
class ManifestException implements Exception {
  /// Creates a manifest exception.
  const ManifestException(this.message);

  /// Human-readable reason.
  final String message;

  @override
  String toString() => 'ManifestException: $message';
}

/// How a catalog wants to be laid out on the Home screen.
///
/// Only the extension knows whether its catalog is a short curated shelf or a
/// long list meant to be scanned — the app can't infer it from the data. In
/// Discover every catalog renders as a grid regardless.
enum CatalogDisplay {
  /// Horizontal carousel. For short, curated shelves ("Top Movies").
  row,

  /// Vertical grid showing everything at once. For long lists worth scanning
  /// (20 live matches). Column count is the app's call — it adapts to the
  /// screen — so the extension is only saying "show it all", not how wide.
  grid,

  /// Vertical single-column list. Same "show it all" intent as [grid], but
  /// for items whose content needs the full width to read — a two-sided
  /// fixture spells out both names, which a half-width grid cell truncates
  /// to nothing.
  ///
  /// Still a shape, not a measurement: the extension says "one per line",
  /// the app decides how tall a line is and what it holds.
  list,
}

/// One catalog a provider exposes — the **root** of everything that provider
/// serves, not a slice of a taxonomy.
///
/// An extension normally declares exactly one, and the taxonomy lives *inside*
/// it, narrowing as it goes:
///
/// ```
/// catalog                                  ← this declaration
///   └── category   live, sport             ← [categories], the Home chips
///         └── subCategory  Football, …     ← CatalogPage.subCategories, per response
///               └── group  Coppa Italia, … ← MediaItem.group, sections in one response
/// ```
///
/// [categories] is a list, not a single value: one catalog legitimately spans
/// several, and the same item may surface under more than one of them (a live
/// football match belongs to both `live` and `sport`). Which category the user
/// is browsing arrives as [CatalogQuery.category], so the extension answers
/// per-category from the one catalog rather than declaring a near-duplicate
/// catalog for each.
class CatalogDecl extends Equatable {
  /// Creates a catalog declaration.
  const CatalogDecl({
    required this.id,
    required this.name,
    required this.categories,
    required this.kind,
    this.display = CatalogDisplay.grid,
    this.filters = const [],
    this.expanded = false,
  });

  /// Builds a [CatalogDecl] from decoded JSON.
  ///
  /// Accepts a bare `"category": "sport"` as well as `"categories": [...]`,
  /// so a manifest written against either spelling loads — the one-category
  /// case is just a list of one.
  factory CatalogDecl.fromJson(Map<String, Object?> json) => CatalogDecl(
    id: json['id'] as String,
    name: json['name'] as String,
    categories: json.containsKey('categories')
        ? stringList(json['categories'])
        : [json['category']! as String],
    kind: enumByNameStrict(MediaKind.values, json['kind']),
    display: enumByName(
      CatalogDisplay.values,
      json['display'],
      orElse: CatalogDisplay.grid,
    ),
    filters: stringList(json['filters']),
    expanded: (json['expanded'] as bool?) ?? false,
  );

  /// Catalog id, unique within its provider.
  final String id;

  /// Display name (`"Live Now"`).
  final String name;

  /// Categories this catalog serves (`["live", "sport"]`) — each becomes a
  /// chip on Home, and arrives back as [CatalogQuery.category].
  final List<String> categories;

  /// Kind of item this catalog yields.
  final MediaKind kind;

  /// Requested layout on Home.
  final CatalogDisplay display;

  /// Filter keys this catalog accepts (`"date"`, `"genre"`).
  final List<String> filters;

  /// Whether Home shows this catalog in full immediately, rather than a
  /// capped preview behind "See more".
  ///
  /// The extension's call, like [display] — a curated shelf (a handful of
  /// named sections) wants the preview-and-See-more treatment every other
  /// catalog gets by default (`false`), but one flat, already-paginated feed
  /// with nothing to name or cap reads better shown in full and grown as the
  /// viewer scrolls, with no heading and no tap required to see the rest.
  /// Independent of [display]: this is about *how much* Home shows up
  /// front, not what shape it's shown in.
  final bool expanded;

  /// Encodes to a JSON map.
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'categories': categories,
    'kind': kind.name,
    'display': display.name,
    if (filters.isNotEmpty) 'filters': filters,
    if (expanded) 'expanded': expanded,
  };

  @override
  List<Object?> get props => [
    id,
    name,
    categories,
    kind,
    display,
    filters,
    expanded,
  ];
}

/// One provider declared by an extension.
class ProviderDecl extends Equatable {
  /// Creates a provider declaration.
  const ProviderDecl({
    required this.id,
    required this.roles,
    this.catalogs = const [],
  });

  /// Builds a [ProviderDecl] from decoded JSON.
  factory ProviderDecl.fromJson(Map<String, Object?> json) => ProviderDecl(
    id: json['id'] as String,
    roles: ((json['roles'] as List?) ?? const [])
        .map((r) => enumByNameStrict(ProviderRole.values, r))
        .toList(),
    catalogs: ((json['catalogs'] as List?) ?? const [])
        .map((c) => CatalogDecl.fromJson(c as Map<String, Object?>))
        .toList(),
  );

  /// Provider id (`"cricfy.events"`).
  final String id;

  /// Roles this provider fills.
  final List<ProviderRole> roles;

  /// Catalogs this provider exposes (empty unless it fills [ProviderRole.catalog]).
  final List<CatalogDecl> catalogs;

  /// Encodes to a JSON map.
  Map<String, Object?> toJson() => {
    'id': id,
    'roles': roles.map((r) => r.name).toList(),
    if (catalogs.isNotEmpty)
      'catalogs': catalogs.map((c) => c.toJson()).toList(),
  };

  @override
  List<Object?> get props => [id, roles, catalogs];
}

/// What an extension is allowed to do. Enforced by the host, not documentation.
class Permissions extends Equatable {
  /// Creates a permission set.
  const Permissions({this.hosts = const []});

  /// Builds [Permissions] from decoded JSON.
  factory Permissions.fromJson(Map<String, Object?>? json) =>
      Permissions(hosts: stringList(json?['hosts']));

  /// Host patterns the extension may fetch. Single-label wildcards only
  /// (`*.example.com`); enforced on every request, including after redirects.
  final List<String> hosts;

  /// Encodes to a JSON map.
  Map<String, Object?> toJson() => {'hosts': hosts};

  @override
  List<Object?> get props => [hosts];
}

/// An extension's manifest — its identity, providers, and permissions.
class Manifest extends Equatable {
  /// Creates a manifest.
  const Manifest({
    required this.apiVersion,
    required this.id,
    required this.name,
    required this.version,
    required this.runtime,
    required this.categories,
    required this.providers,
    required this.permissions,
    this.entry,
    this.description,
    this.author,
    this.iconUrl,
  });

  /// Highest protocol version this app build can run.
  ///
  /// A manifest above this is refused ([parse]); this is the single knob that
  /// keeps a newer extension from running against an app that predates the
  /// capability it needs.
  static const int supportedApiVersion = 1;

  /// Parses and validates a manifest.
  ///
  /// Throws [ManifestException] when the payload is malformed or declares an
  /// [apiVersion] this build can't run.
  factory Manifest.parse(Map<String, Object?> json) {
    final rawVersion = json['apiVersion'];
    if (rawVersion is! int) {
      throw const ManifestException('apiVersion missing or not an integer');
    }
    if (rawVersion < 1) {
      throw ManifestException('apiVersion $rawVersion is invalid');
    }
    if (rawVersion > supportedApiVersion) {
      throw ManifestException(
        'apiVersion $rawVersion needs a newer app '
        '(this build supports up to $supportedApiVersion)',
      );
    }
    try {
      return Manifest(
        apiVersion: rawVersion,
        id: json['id'] as String,
        name: json['name'] as String,
        version: json['version'] as String,
        runtime: json['runtime'] as String,
        entry: json['entry'] as String?,
        description: json['description'] as String?,
        author: json['author'] as String?,
        iconUrl: json['iconUrl'] as String?,
        categories: stringList(json['categories']),
        providers: ((json['providers'] as List?) ?? const [])
            .map((p) => ProviderDecl.fromJson(p as Map<String, Object?>))
            .toList(),
        permissions: Permissions.fromJson(
          json['permissions'] as Map<String, Object?>?,
        ),
      );
    } on TypeError catch (e) {
      throw ManifestException('malformed manifest: $e');
    }
  }

  /// Protocol version this manifest targets.
  final int apiVersion;

  /// Extension id (`"cricfy"`).
  final String id;

  /// Display name.
  final String name;

  /// Extension version (semver string; drives auto-update).
  final String version;

  /// Runtime that executes the bundle (`"js"`), or `"builtin"` for a Fase-1
  /// Dart adapter shipped with the app.
  final String runtime;

  /// Bundle entry point, relative to the manifest. `null` for builtin runtimes.
  final String? entry;

  /// One or two sentences on what this extension is for, shown in Addons and
  /// — via the repo index — in the install prompt, so "what am I agreeing
  /// to" has an answer beyond a name and a host list.
  final String? description;

  /// Who publishes it. Not verified by anything: until bundles are signed
  /// (§19, §20) this is a label the manifest asserts about itself, and it is
  /// presented as such rather than as provenance.
  final String? author;

  /// Icon/logo URL. Optional, and never required to render — an extension
  /// without one falls back to a plain tile, not a broken image.
  final String? iconUrl;

  /// Categories this extension contributes (`["live", "sport"]`). Each one
  /// becomes a chip on Home.
  final List<String> categories;

  /// Providers this extension declares.
  final List<ProviderDecl> providers;

  /// What this extension is allowed to do.
  final Permissions permissions;

  /// Encodes to a JSON map.
  Map<String, Object?> toJson() => {
    'apiVersion': apiVersion,
    'id': id,
    'name': name,
    'version': version,
    'runtime': runtime,
    if (entry != null) 'entry': entry,
    if (description != null) 'description': description,
    if (author != null) 'author': author,
    if (iconUrl != null) 'iconUrl': iconUrl,
    'categories': categories,
    'providers': providers.map((p) => p.toJson()).toList(),
    'permissions': permissions.toJson(),
  };

  @override
  List<Object?> get props => [
    apiVersion,
    id,
    name,
    version,
    runtime,
    entry,
    description,
    author,
    iconUrl,
    categories,
    providers,
    permissions,
  ];
}
