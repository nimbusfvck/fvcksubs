import 'package:fvcksubs_core/fvcksubs_core.dart';

import 'catalog_binding.dart';

/// The set of installed extensions, and the routing over them.
///
/// The app never talks to an extension directly — it asks the registry, which
/// discovers categories, finds the catalogs feeding each one, and routes a
/// [MediaRef]'s source and resolve calls back to the extension that owns it.
///
/// A category is not configured anywhere: it's whatever the installed
/// extensions declare. Install one, its categories appear; remove it, they go.
class ExtensionRegistry {
  /// Creates a registry over [extensions], in the order they should appear.
  ///
  /// [disabledExtensionIds] and [disabledProviderIds] (full ids, e.g.
  /// `"fvck.kora"`) seed the Addons on/off state — normally whatever the app
  /// persisted last session. Everything is enabled by default.
  ExtensionRegistry(
    List<ContentExtension> extensions, {
    Set<String> disabledExtensionIds = const {},
    Set<String> disabledProviderIds = const {},
  }) : _extensions = [...extensions],
       _disabledExtensionIds = {...disabledExtensionIds},
       _disabledProviderIds = {...disabledProviderIds};

  final List<ContentExtension> _extensions;
  final Set<String> _disabledExtensionIds;
  final Set<String> _disabledProviderIds;

  /// Manifests of every installed extension, in install order — enabled or
  /// not; Addons needs to list disabled ones too, to offer turning them
  /// back on.
  List<Manifest> get installed => [for (final e in _extensions) e.manifest];

  /// Adds [extension], replacing any already-installed one with the same id.
  ///
  /// Replacing in place (rather than appending) keeps a *reinstall* or an
  /// *update* from producing two entries for one id — which would show the
  /// extension twice in Addons and fan every query out to it twice. The
  /// replacement keeps the old one's position so an update doesn't reorder
  /// the user's shelves.
  ///
  /// On/off state lives in [_disabledExtensionIds], keyed by id, so it
  /// deliberately survives a replace: an extension switched off stays off
  /// after updating it, which is what a user who switched it off expects.
  ///
  /// Returns the extension that was replaced, or `null` if this was a fresh
  /// install — the caller owns disposing it (a [JsExtension] holds a native
  /// engine), since the registry never created it and cannot know whether
  /// something else still holds a reference.
  ContentExtension? install(ContentExtension extension) {
    final id = extension.manifest.id;
    final index = _extensions.indexWhere((e) => e.manifest.id == id);
    if (index < 0) {
      _extensions.add(extension);
      return null;
    }
    final previous = _extensions[index];
    _extensions[index] = extension;
    return previous;
  }

  /// Removes the extension with [id], if installed.
  ///
  /// Returns it so the caller can dispose it (see [install]), or `null` if
  /// nothing was installed under that id. On/off state for the id is left
  /// alone: reinstalling later should come back the way the user left it.
  ContentExtension? uninstall(String id) {
    final index = _extensions.indexWhere((e) => e.manifest.id == id);
    if (index < 0) return null;
    return _extensions.removeAt(index);
  }

  /// Extension ids currently switched off in Addons.
  Set<String> get disabledExtensionIds =>
      Set.unmodifiable(_disabledExtensionIds);

  /// Provider ids (full, `"fvck.kora"`) currently switched off in Addons.
  Set<String> get disabledProviderIds => Set.unmodifiable(_disabledProviderIds);

  /// Whether [extensionId] is switched on.
  bool isExtensionEnabled(String extensionId) =>
      !_disabledExtensionIds.contains(extensionId);

  /// Switches [extensionId] on or off — every catalog and source it owns
  /// stops contributing while off.
  void setExtensionEnabled(String extensionId, bool enabled) {
    if (enabled) {
      _disabledExtensionIds.remove(extensionId);
    } else {
      _disabledExtensionIds.add(extensionId);
    }
  }

  /// Whether [providerId] (full, `"fvck.kora"`) is switched on.
  bool isProviderEnabled(String providerId) =>
      !_disabledProviderIds.contains(providerId);

  /// Switches one provider on or off — the per-source toggle. Independent of
  /// [setExtensionEnabled]: an extension can stay on with one of its stream
  /// providers off.
  void setProviderEnabled(String providerId, bool enabled) {
    if (enabled) {
      _disabledProviderIds.remove(providerId);
    } else {
      _disabledProviderIds.add(providerId);
    }
  }

  /// Categories declared by installed, *enabled* extensions, de-duplicated,
  /// first-seen order. These become the chips on Home.
  List<String> get categories {
    final seen = <String>{};
    final ordered = <String>[];
    for (final extension in _extensions) {
      if (!isExtensionEnabled(extension.manifest.id)) continue;
      for (final category in extension.manifest.categories) {
        if (seen.add(category)) ordered.add(category);
      }
    }
    return ordered;
  }

  /// Every catalog serving [category], across enabled extensions and
  /// providers.
  ///
  /// A catalog is the root of everything its provider serves and may span
  /// several categories, so this matches against
  /// [CatalogDecl.categories] rather than a single value — one catalog can
  /// appear under both `live` and `sport`.
  ///
  /// Returned unmerged, one binding per catalog: each becomes its own shelf,
  /// loads independently, and fails independently. That's deliberate — a dead
  /// catalog should show an error in its own shelf, not blank the page. With
  /// the usual one-catalog-per-extension shape, that means one binding per
  /// installed extension, which is why the app's catalog picker reads as a
  /// plugin picker.
  List<CatalogBinding> catalogsFor(String category) {
    final bindings = <CatalogBinding>[];
    for (final extension in _extensions) {
      if (!isExtensionEnabled(extension.manifest.id)) continue;
      for (final provider in extension.manifest.providers) {
        if (!isProviderEnabled(provider.id)) continue;
        for (final catalog in provider.catalogs) {
          if (catalog.categories.contains(category)) {
            bindings.add(
              CatalogBinding(
                extension: extension,
                providerId: provider.id,
                catalog: catalog,
              ),
            );
          }
        }
      }
    }
    return bindings;
  }

  /// The extensions serving [category], in install order.
  ///
  /// What the app's plugin picker lists: two extensions can cover the same
  /// category from different upstreams, and the user picks whose data they
  /// want. Returns manifests rather than bindings because the choice is about
  /// the *extension*, not any one of its catalogs.
  List<Manifest> pluginsFor(String category) {
    final seen = <String>{};
    return [
      for (final binding in catalogsFor(category))
        if (seen.add(binding.extensionId)) binding.extension.manifest,
    ];
  }

  /// Loads one page of a catalog.
  ///
  /// [category] names which of the catalog's categories is being browsed —
  /// pass the one whose chip is selected, since a catalog spanning several
  /// otherwise cannot tell which slice to answer with.
  ///
  /// [page] is `null` for the first page, or a cursor from a previous
  /// [CatalogPage.nextPage]. Errors propagate to the caller: each shelf owns
  /// its own failure state, so the registry doesn't swallow them.
  Future<CatalogPage> loadCatalog(
    CatalogBinding binding, {
    String? category,
    String? page,
    Map<String, String> filters = const {},
    String? subCategory,
  }) => binding.extension.catalog(
    CatalogQuery(
      providerId: binding.providerId,
      catalogId: binding.catalog.id,
      category: category,
      page: page,
      filters: filters,
      subCategory: subCategory,
    ),
  );

  /// Loads and normalizes one catalog page through its protocol version.
  Future<VersionedCatalogPage> loadCatalogVersioned(
    CatalogBinding binding, {
    String? category,
    String? page,
    Map<String, String> filters = const {},
    String? subCategory,
  }) => binding.extension.catalogVersioned(
    CatalogQuery(
      providerId: binding.providerId,
      catalogId: binding.catalog.id,
      category: category,
      page: page,
      filters: filters,
      subCategory: subCategory,
    ),
  );

  /// Free-text search, fanned out to every installed extension that declares
  /// [ProviderRole.search], merged into one list.
  ///
  /// Content-agnostic per PLAN.md §10: results are plain [MediaItem]s, so the
  /// caller never needs to know which extension or vertical a hit came from.
  /// Tolerant of a single provider failing (network error, provider down) —
  /// mirrors `FvckExtension._sourcesFrom`'s fan-out — so one broken extension
  /// doesn't blank the whole result list. No merged pagination across
  /// providers: each provider's [CatalogPage.nextPage] would need its own
  /// cursor tracked independently, which isn't worth the complexity while
  /// only one search-capable extension exists.
  Future<List<MediaItem>> search(String query) async {
    final providers = <ContentExtension>[
      for (final extension in _extensions)
        if (isExtensionEnabled(extension.manifest.id) &&
            extension.manifest.providers.any(
              (p) =>
                  isProviderEnabled(p.id) &&
                  p.roles.contains(ProviderRole.search),
            ))
          extension,
    ];
    final results = await Future.wait<List<MediaItem>>(
      providers.map((extension) => _searchOne(extension, query)),
    );
    return results.expand((items) => items).toList();
  }

  /// Searches through the versioned boundary and returns normalized items.
  Future<List<VersionedMediaItem>> searchVersioned(String query) async {
    final providers = <ContentExtension>[
      for (final extension in _extensions)
        if (isExtensionEnabled(extension.manifest.id) &&
            extension.manifest.providers.any(
              (provider) =>
                  isProviderEnabled(provider.id) &&
                  provider.roles.contains(ProviderRole.search),
            ))
          extension,
    ];
    final results = await Future.wait<List<VersionedMediaItem>>(
      providers.map((extension) async {
        try {
          return (await extension.searchVersioned(query)).items.toList();
        } catch (_) {
          return <VersionedMediaItem>[];
        }
      }),
    );
    return results.expand((items) => items).toList();
  }

  Future<List<MediaItem>> _searchOne(
    ContentExtension extension,
    String query,
  ) async {
    try {
      final page = await extension.search(query);
      return page.items;
    } catch (_) {
      return const [];
    }
  }

  /// Lists playable sources for [item], from the extension that owns it.
  ///
  /// Empty (never a throw) when the owning extension is switched off. Passes
  /// down exactly which of the extension's own *stream*-role providers are
  /// enabled, so an extension fanning out across several internal sources
  /// (Kora, later Cricfy) can filter itself — see [ContentExtension.sources].
  Future<List<StreamSource>> sources(MediaItem item) {
    final extension = extensionById(item.ref.extensionId);
    if (!isExtensionEnabled(extension.manifest.id)) {
      return Future.value(const []);
    }
    // An extension that declares no `stream` provider at all doesn't
    // implement the role, and `ContentExtension.sources` throws by default —
    // a guard, not a code path (see its doc comment). Asking anyway would
    // turn "this extension only serves a catalog" into an error on every
    // detail page. Distinct from *all its stream providers being disabled*,
    // which is a real call with an empty set.
    final declaresStream = extension.manifest.providers.any(
      (provider) => provider.roles.contains(ProviderRole.stream),
    );
    if (!declaresStream) return Future.value(const []);

    final enabledStreamProviders = <String>{
      for (final provider in extension.manifest.providers)
        if (provider.roles.contains(ProviderRole.stream) &&
            isProviderEnabled(provider.id))
          provider.id,
    };
    return extension.sources(item, enabledProviders: enabledStreamProviders);
  }

  /// Resolves [sourceId] (produced by [sources] for [ref]) into a stream.
  Future<PlayableStream> resolveSource(MediaRef ref, String sourceId) =>
      extensionById(ref.extensionId).resolve(sourceId);

  /// Looks up subtitles for [item] independently of any resolved source —
  /// a manual fallback for when a source's own tracks are missing, out of
  /// sync, or erroring.
  ///
  /// Empty (never a throw) when the owning extension is switched off, or
  /// doesn't declare [ProviderRole.subtitles] at all — mirrors [sources]'
  /// guard for the same reason: this is a nice-to-have on top of playback,
  /// not something every detail/player screen should have to handle failing.
  Future<List<SubtitleTrack>> externalSubtitles(MediaItem item) async {
    final extension = extensionById(item.ref.extensionId);
    if (!isExtensionEnabled(extension.manifest.id)) return const [];

    final declaresSubtitles = extension.manifest.providers.any(
      (provider) => provider.roles.contains(ProviderRole.subtitles),
    );
    if (!declaresSubtitles) return const [];

    try {
      return await extension.externalSubtitles(item);
    } catch (_) {
      return const [];
    }
  }

  /// Fetches fresh detail for [ref], from the extension that owns it.
  ///
  /// Not gated on [isExtensionEnabled] (unlike [sources]) — a disabled
  /// extension is hidden from browsing, not uninstalled, and Library
  /// (PLAN.md §14) only needs to treat a ref as unavailable once its
  /// extension is actually gone from [installed], which callers check via
  /// [extensionById] throwing.
  Future<MediaDetail> meta(MediaRef ref) =>
      extensionById(ref.extensionId).meta(ref);

  /// The installed extension with [id]. Throws [StateError] if none.
  ContentExtension extensionById(String id) => _extensions.firstWhere(
    (extension) => extension.manifest.id == id,
    orElse: () => throw StateError('No extension installed with id "$id"'),
  );
}
