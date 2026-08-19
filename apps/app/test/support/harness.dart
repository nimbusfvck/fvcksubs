import 'package:flutter/material.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_app/addons/addons_controller.dart';
import 'package:fvcksubs_app/addons/installer_controller.dart';
import 'package:fvcksubs_app/app_scope.dart';
import 'package:fvcksubs_app/catalog/catalog_cache.dart';
import 'package:fvcksubs_app/catalog/plugin_controller.dart';
import 'package:fvcksubs_app/player/source_cache.dart';
import 'package:fvcksubs_app/player/subtitle_preference_controller.dart';
import 'package:fvcksubs_app/library/library_controller.dart';
import 'package:fvcksubs_app/platform/device_class.dart';
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';
import 'package:fvcksubs_storage/fvcksubs_storage.dart';

/// A canned extension for widget tests — no network, no real player.
class FakeExtension extends ContentExtension {
  FakeExtension({
    this.id = 'fake',
    this.categories = const ['sport'],
    this.display = CatalogDisplay.grid,
    this.expanded = false,
    this.filterKeys = const [],
    this.items = const [],
    this.itemsByCategory = const {},
    this.pages = const {},
    this.subCategories = const [],
    this.itemsBySubCategory = const {},
    this.sourceList = const [],
    this.sourceListFor,
    this.catalogDelay,
    this.sourcesDelay,
    this.resolved,
    this.resolveFailsFor = const {},
    this.metaDetail,
    this.searchable = false,
    this.searchResults = const [],
    String? name,
    String? catalogName,
    String? description,
    String? author,
  }) : _manifest = Manifest.parse({
         'apiVersion': 1,
         'id': id,
         'name': name ?? id,
         'version': '1.0.0',
         'runtime': 'builtin',
         'description': ?description,
         'author': ?author,
         'categories': categories,
         'providers': [
           {
             'id': '$id.p',
             'roles': ['catalog', 'stream', if (searchable) 'search'],
             // One catalog listing every category it serves — the shape the
             // protocol expects, with the taxonomy inside the catalog rather
             // than a near-duplicate catalog per category.
             'catalogs': [
               {
                 'id': 'catalog',
                 'name': catalogName ?? name ?? id,
                 'categories': categories,
                 'kind': 'liveEvent',
                 'display': display.name,
                 if (expanded) 'expanded': expanded,
                 if (filterKeys.isNotEmpty) 'filters': filterKeys,
               },
             ],
           },
         ],
         'permissions': {'hosts': <String>[]},
       });

  final String id;
  final List<String> categories;
  final CatalogDisplay display;

  /// Whether the catalog declares `expanded: true` — shown in full on Home
  /// (`CatalogGridSection`) instead of a capped preview behind "See more".
  final bool expanded;

  /// Filter keys the catalog declares (`catalog.filters`).
  final List<String> filterKeys;
  final List<MediaItem> items;

  /// Cursor-keyed catalog pages, for exercising pagination: `pages[null]` is
  /// the first page, `pages['cursor']` is what a matching `nextPage` yields.
  /// Empty (the default) means [catalog] just returns [items] as one page.
  final Map<String?, CatalogPage> pages;
  final List<StreamSource> sourceList;

  /// Per-item override for [sources] — lets a test vary what's "available"
  /// by episode (e.g. probing for the latest one that actually has a
  /// source) instead of every item getting the same static [sourceList].
  final List<StreamSource> Function(MediaItem item)? sourceListFor;

  /// Holds [catalog] open for this long — lets a test tell a cache hit from
  /// a re-fetch by whether a spinner ever appears.
  final Duration? catalogDelay;

  /// Holds [sources] open for this long — lets a test observe the state a
  /// screen is in *while* sources are still being fetched, which is otherwise
  /// over within one microtask.
  final Duration? sourcesDelay;

  final PlayableStream? resolved;

  /// Source ids [resolve] throws for instead of returning [resolved] — lets
  /// a test simulate one source (a stale persisted entry, say) failing while
  /// others still work.
  final Set<String> resolveFailsFor;

  /// Whether this extension declares the `search` role.
  final bool searchable;

  /// Items [search] returns for any non-empty query.
  final List<MediaItem> searchResults;

  /// Filters from the most recent [catalog] call — lets a test assert a
  /// filter control actually changed what was queried.
  Map<String, String>? lastFilters;

  final Manifest _manifest;

  @override
  Manifest get manifest => _manifest;

  @override
  Future<CatalogPage> catalog(CatalogQuery query) async {
    catalogCalls++;
    if (catalogDelay != null) await Future<void>.delayed(catalogDelay!);
    lastFilters = query.filters;
    lastSubCategory = query.subCategory;
    lastCategory = query.category;
    if (pages.isNotEmpty) {
      return pages[query.page] ?? const CatalogPage(items: []);
    }
    if (query.subCategory != null) {
      return CatalogPage(
        items: itemsBySubCategory[query.subCategory] ?? const [],
        subCategories: subCategories,
      );
    }
    return CatalogPage(
      items: itemsByCategory[query.category] ?? items,
      // Returned on every response, narrowed or not — the real extensions do
      // the same so the chips don't vanish once one is picked.
      subCategories: subCategories,
    );
  }

  @override
  Future<CatalogPage> search(String query, {String? page}) async =>
      CatalogPage(items: searchResults);

  /// Items to return for a given category, falling back to [items].
  final Map<String?, List<MediaItem>> itemsByCategory;

  /// The `category` of the most recent [catalog] call.
  String? lastCategory;

  /// How many times [catalog] has been called — lets a test assert that a
  /// screen served a category from cache instead of fetching it again.
  int catalogCalls = 0;

  /// Subcategories every catalog response advertises.
  final List<SubCategory> subCategories;

  /// Items to return when a given subcategory is selected.
  final Map<String, List<MediaItem>> itemsBySubCategory;

  /// The `subCategory` of the most recent [catalog] call.
  String? lastSubCategory;

  /// The `enabledProviders` the registry passed to the most recent [sources]
  /// call — lets a test assert what the per-source toggle computed.
  Set<String>? lastEnabledProviders;

  /// How many times [sources] has been called — lets a test assert that a
  /// cached resolve skipped asking the extension again.
  int sourcesCalls = 0;

  /// How many times [resolve] has been called — the expensive half of the
  /// pair (PLAN.md §2.5), and the one a source cache exists to spare.
  int resolveCalls = 0;

  @override
  Future<List<StreamSource>> sources(
    MediaItem item, {
    Set<String>? enabledProviders,
  }) async {
    sourcesCalls++;
    lastEnabledProviders = enabledProviders;
    if (sourcesDelay != null) await Future<void>.delayed(sourcesDelay!);
    return sourceListFor?.call(item) ?? sourceList;
  }

  @override
  Future<PlayableStream> resolve(String sourceId) async {
    resolveCalls++;
    if (resolveFailsFor.contains(sourceId)) {
      throw Exception('$id: source $sourceId no longer resolves');
    }
    return resolved ?? const PlayableStream(url: 'https://example/live.m3u8');
  }

  /// What [meta] returns; `null` leaves it throwing, matching the protocol
  /// default for extensions that don't implement the role.
  MediaDetail? metaDetail;

  @override
  Future<MediaDetail> meta(MediaRef ref) async =>
      metaDetail ?? (throw UnsupportedError('$id does not provide meta'));
}

/// An extension whose sources each resolve to their own subtitle set — what
/// the real ones do, and what ordering by preferred language depends on.
class SubtitleFakeExtension extends ContentExtension {
  /// Creates a fake offering one source per key, resolving to those languages.
  SubtitleFakeExtension({
    required this.subtitlesBySourceId,
    this.resolveDelay,
  })
    : _manifest = Manifest.parse({
        'apiVersion': 1,
        'id': 'subs',
        'name': 'subs',
        'version': '1.0.0',
        'runtime': 'builtin',
        'categories': ['sport'],
        'providers': [
          {
            'id': 'subs.p',
            'roles': ['catalog', 'stream'],
            'catalogs': [
              {
                'id': 'catalog',
                'name': 'subs',
                'categories': ['sport'],
                'kind': 'liveEvent',
              },
            ],
          },
        ],
        'permissions': {'hosts': <String>[]},
      });

  /// Subtitle language tags, keyed by the source id that carries them. Order
  /// here is the order `sources()` returns them in.
  final Map<String, List<String>> subtitlesBySourceId;

  /// Holds each [resolve] open this long — lets a test observe the wait while
  /// sources are genuinely still outstanding.
  final Duration? resolveDelay;

  final Manifest _manifest;

  @override
  Manifest get manifest => _manifest;

  @override
  Future<CatalogPage> catalog(CatalogQuery query) async =>
      const CatalogPage(items: []);

  @override
  Future<List<StreamSource>> sources(
    MediaItem item, {
    Set<String>? enabledProviders,
  }) async => [
    for (final id in subtitlesBySourceId.keys)
      StreamSource(id: id, label: 'Source $id'),
  ];

  @override
  Future<PlayableStream> resolve(String sourceId) async {
    if (resolveDelay != null) await Future<void>.delayed(resolveDelay!);
    return PlayableStream(
    url: 'https://edge/$sourceId.m3u8',
    format: StreamFormat.hls,
    subtitles: [
      for (final language in subtitlesBySourceId[sourceId] ?? const <String>[])
          SubtitleTrack(language: language, url: 'https://edge/$language.vtt'),
      ],
    );
  }
}

/// Builds a [MediaItem] for tests.
MediaItem fakeItem({
  String id = 'e1',
  String extensionId = 'fake',
  String title = 'Home vs Away',
  String? subtitle,
  LiveStatus status = LiveStatus.live,
  String? statusLabel,
  List<Participant> participants = const [],
  ImageRef? poster,
  String? group,
}) => MediaItem(
  ref: MediaRef(extensionId: extensionId, providerId: '$extensionId.p', id: id),
  kind: poster == null ? MediaKind.liveEvent : MediaKind.movie,
  title: title,
  subtitle: subtitle,
  status: status,
  statusLabel: statusLabel,
  participants: participants,
  poster: poster,
  group: group,
);

/// A player builder that records the stream it was given and renders a marker,
/// so a test can assert playback started without a native player.
class RecordingPlayer {
  PlayableStream? played;

  /// The `isLive` the most recent build was called with — lets a test assert
  /// the detail page told the player the right thing for the item's kind.
  bool? playedIsLive;

  /// How many times [build] has been called — lets a test assert a source
  /// switch actually rebuilt the player, not just updated its stream field.
  int buildCount = 0;

  /// The `preferredSubtitleLanguage` the most recent build was called with
  /// — lets a test assert the player was told the viewer's subtitle
  /// preference.
  String? playedPreferredSubtitleLanguage;

  // [key] is accepted (real callers, `PlayerPage` in particular, rely on it
  // to force better_player's controller to be recreated on a source switch)
  // but not used for the returned widget's own identity — this fake has no
  // internal state for a key to matter to, and tests find it by the one
  // stable `Key('fake-player')` regardless of which source is "playing".
  Widget build(
    BuildContext context,
    PlayableStream stream, {
    required bool isLive,
    void Function(Object? controller)? onControllerCreated,
    Widget Function(
      BuildContext context,
      Object? controller,
      void Function(bool visibility) onVisibilityChanged,
    )?
    customControlsBuilder,
    String? preferredSubtitleLanguage,
    Key? key,
  }) {
    played = stream;
    playedIsLive = isLive;
    playedPreferredSubtitleLanguage = preferredSubtitleLanguage;
    buildCount++;
    if (customControlsBuilder != null) {
      return Stack(
        children: [
          const SizedBox(key: Key('fake-player'), height: 100),
          customControlsBuilder(context, null, (_) {}),
        ],
      );
    }
    return const SizedBox(key: Key('fake-player'), height: 100);
  }
}

/// In-memory [AddonSettingsStore] — no real `shared_preferences` plugin in a
/// widget test.
class FakeAddonSettingsStore implements AddonSettingsStore {
  AddonSettings? saved;

  @override
  Future<AddonSettings> load() async => saved ?? const AddonSettings();

  @override
  Future<void> save(AddonSettings settings) async => saved = settings;
}

/// In-memory [InstalledExtensionStore] — nothing downloaded in a widget test
/// unless the test puts it here.
class FakeInstalledExtensionStore implements InstalledExtensionStore {
  Map<String, InstalledExtension> saved = {};

  @override
  Future<Map<String, InstalledExtension>> loadAll() async => Map.of(saved);

  @override
  Future<void> save(InstalledExtension extension) async =>
      saved[extension.id] = extension;

  @override
  Future<void> remove(String id) async => saved.remove(id);
}

/// In-memory [RepoStore].
class FakeRepoStore implements RepoStore {
  String? saved;

  @override
  Future<String?> load() async => saved;

  @override
  Future<void> save(String? url) async => saved = url;
}

/// In-memory [LibraryStore] — no real `shared_preferences` plugin in a
/// widget test.
class FakeLibraryStore implements LibraryStore {
  Map<String, UserMediaState> saved = {};

  @override
  Future<Map<String, UserMediaState>> load() async => saved;

  @override
  Future<void> save(Map<String, UserMediaState> records) async =>
      saved = records;
}

/// In-memory [SourceListStore].
class FakeSourceListStore implements SourceListStore {
  Map<String, CachedSourceList> saved = {};

  @override
  Future<Map<String, CachedSourceList>> load() async => saved;

  @override
  Future<void> save(Map<String, CachedSourceList> records) async =>
      saved = records;
}

/// In-memory [SubtitlePreferenceStore].
class FakeSubtitlePreferenceStore implements SubtitlePreferenceStore {
  /// Seeds the store as if [initial] had already been saved.
  FakeSubtitlePreferenceStore({String? initial}) : saved = initial;

  String? saved;

  @override
  Future<String?> load() async => saved;

  @override
  Future<void> save(String? languageCode) async => saved = languageCode;
}

/// In-memory [CategorySelectionStore].
class FakeCategorySelectionStore implements CategorySelectionStore {
  /// Seeds the store as if [initial] had already been saved — for tests that
  /// check a screen restores the category it was left on.
  FakeCategorySelectionStore({String? initial}) : saved = initial;

  String? saved;

  @override
  Future<String?> load() async => saved;

  @override
  Future<void> save(String? category) async => saved = category;
}

/// In-memory [PluginSelectionStore].
class FakePluginSelectionStore implements PluginSelectionStore {
  /// Seeds the store as if [initial] had already been saved.
  FakePluginSelectionStore({String? initial}) : saved = initial;

  String? saved;

  @override
  Future<String?> load() async => saved;

  @override
  Future<void> save(String? extensionId) async => saved = extensionId;
}

/// Wraps [child] in an [AppScope] + [MaterialApp] for pumping a screen.
///
/// Pages that aren't themselves a [Scaffold] (HomePage, which normally sits
/// inside HomeShell's) get one here, so Material widgets find their ancestor
/// the same way they do in the running app. A [child] that brings its own
/// Scaffold is unaffected by the extra one.
///
/// [addonsController] and [libraryController] each default to a fresh one
/// over an in-memory store — pass an explicit one when a test needs to
/// observe toggles, favorites, or persistence.
Widget wrapApp({
  required Widget child,
  required ExtensionRegistry registry,
  DeviceClass deviceClass = DeviceClass.handheld,
  RecordingPlayer? player,
  AddonsController? addonsController,
  InstallerController? installerController,
  LibraryController? libraryController,
  PluginController? pluginController,
  CatalogCache? catalogCache,
  SubtitlePreferenceController? subtitlePreferenceController,
  CategorySelectionStore? homeCategoryStore,
  SourceCache? sourceCache,
}) => AppScope(
  registry: registry,
  deviceClass: deviceClass,
  playerBuilder: (player ?? RecordingPlayer()).build,
  addonsController:
      addonsController ??
      AddonsController(registry: registry, store: FakeAddonSettingsStore()),
  installerController:
      installerController ??
      InstallerController(
        registry: registry,
        installer: ExtensionInstaller(),
        installedStore: FakeInstalledExtensionStore(),
        repoStore: FakeRepoStore(),
      ),
  libraryController:
      libraryController ??
      LibraryController(store: FakeLibraryStore()),
  pluginController:
      pluginController ?? PluginController(store: FakePluginSelectionStore()),
  catalogCache: catalogCache ?? CatalogCache(),
  subtitlePreferenceController:
      subtitlePreferenceController ??
      SubtitlePreferenceController(store: FakeSubtitlePreferenceStore()),
  homeCategoryStore: homeCategoryStore ?? FakeCategorySelectionStore(),
  sourceCache: sourceCache ?? SourceCache(),
  child: MaterialApp(home: Scaffold(body: child)),
);
