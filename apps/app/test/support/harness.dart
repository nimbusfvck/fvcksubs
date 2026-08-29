import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_app/addons/addons_controller.dart';
import 'package:fvcksubs_app/addons/installer_controller.dart';
import 'package:fvcksubs_app/app_scope.dart';
import 'package:fvcksubs_app/catalog/catalog_cache.dart';
import 'package:fvcksubs_app/catalog/plugin_controller.dart';
import 'package:fvcksubs_app/player/models/app_player_controller.dart';
import 'package:fvcksubs_app/player/state/source_cache.dart';
import 'package:fvcksubs_app/player/widgets/app_preview_player.dart';
import 'package:fvcksubs_app/player/state/source_priority_controller.dart';
import 'package:fvcksubs_app/player/state/subtitle_preference_controller.dart';
import 'package:fvcksubs_app/settings/nsfw_controller.dart';
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
    this.sectionTitle,
    this.catalogSections = const [],
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
    this.previewFor = const {},
    this.searchable = false,
    this.searchResults = const [],
    this.searchResultsByCategory = const {},
    String? name,
    String? providerName,
    String? catalogName,
    String? description,
    String? author,
    String version = '1.0.0',
    this.contentRating = ContentRating.unknown,
    ContentRating? catalogContentRating,
    this.catalogs = const [],
  }) : _manifest = Manifest.parse({
         'apiVersion': 2,
         'id': id,
         'name': name ?? id,
         'version': version,
         'runtime': 'builtin',
         'description': ?description,
         'author': ?author,
         if (contentRating != ContentRating.unknown)
           'contentRating': contentRating.name,
         'categories': categories,
         'providers': [
           {
             'id': '$id.p',
             'name': ?providerName,
             'roles': ['catalog', 'stream', if (searchable) 'search'],
             // One catalog listing every category it serves — the shape the
             // protocol expects, with the taxonomy inside the catalog rather
             // than a near-duplicate catalog per category.
             'catalogs': catalogs.isEmpty
                 ? [
                     {
                       'id': 'catalog',
                       'name': catalogName ?? name ?? id,
                       'categories': categories,
                       'kind': 'liveEvent',
                       'display': display.name,
                       if (expanded) 'expanded': expanded,
                       if (filterKeys.isNotEmpty) 'filters': filterKeys,
                       if (catalogContentRating != null)
                         'contentRating': catalogContentRating.name,
                     },
                   ]
                 : [for (final catalog in catalogs) catalog.toJson()],
           },
         ],
         'permissions': {'hosts': <String>[]},
       });

  final String id;
  final List<String> categories;
  final ContentRating contentRating;
  final CatalogDisplay display;

  /// Optional catalog declarations for Home tests that need more than the
  /// usual one-catalog-per-extension shape.
  final List<FakeCatalog> catalogs;

  /// Whether the catalog declares `expanded: true` — shown in full on Home
  /// (`CatalogGridSection`) instead of a capped preview behind "See more".
  final bool expanded;

  /// Filter keys the catalog declares (`catalog.filters`).
  final List<String> filterKeys;
  final List<MediaItemV2> items;

  final String? sectionTitle;

  /// Explicit response sections for Home tests that exercise section-level
  /// grouping inside one catalog.
  final List<CatalogSectionV2> catalogSections;

  /// Cursor-keyed catalog pages, for exercising pagination: `pages[null]` is
  /// the first page, `pages['cursor']` is what a matching `nextPage` yields.
  /// Empty (the default) means [catalog] just returns [items] as one page.
  final Map<String?, VersionedCatalogPage> pages;
  final List<StreamSource> sourceList;

  /// Per-item override for [sources] — lets a test vary what's "available"
  /// by episode (e.g. probing for the latest one that actually has a
  /// source) instead of every item getting the same static [sourceList].
  final List<StreamSource> Function(MediaItemV2 item)? sourceListFor;

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

  /// Results per search scope, for asserting that a scoped search reaches the
  /// right provider. Falls back to [searchResults] when the scope has no
  /// entry, which is what an unscoped search gets.
  final Map<String?, List<MediaItemV2>> searchResultsByCategory;

  /// Scopes [search] was called with, in order — null for an unscoped call.
  /// Empty means this extension was never asked, which is the assertion when
  /// a scope should have filtered it out entirely.
  final List<String?> searchCategories = [];

  /// Items [search] returns for any non-empty query.
  final List<MediaItemV2> searchResults;

  /// Filters from the most recent [catalog] call — lets a test assert a
  /// filter control actually changed what was queried.
  Map<String, String>? lastFilters;

  final Manifest _manifest;

  @override
  Manifest get manifest => _manifest;

  @override
  Future<VersionedCatalogPage> catalog(CatalogQuery query) async {
    catalogCalls++;
    if (catalogDelay != null) await Future<void>.delayed(catalogDelay!);
    lastFilters = query.filters;
    lastSubCategory = query.subCategory;
    lastCategory = query.category;
    if (pages.isNotEmpty) {
      return pages[query.page] ?? const VersionedCatalogPage(sections: []);
    }
    if (catalogs.isNotEmpty) {
      final catalog = catalogs.firstWhere(
        (value) => value.id == query.catalogId,
      );
      return _page(catalog.items);
    }
    if (query.subCategory != null) {
      return _page(itemsBySubCategory[query.subCategory] ?? const []);
    }
    return _page(itemsByCategory[query.category] ?? items);
  }

  @override
  Future<VersionedCatalogPage> search(
    String query, {
    String? page,
    String? category,
  }) async {
    searchCategories.add(category);
    return _page(searchResultsByCategory[category] ?? searchResults);
  }

  VersionedCatalogPage _page(List<MediaItemV2> values) => VersionedCatalogPage(
    sections: catalogSections.isNotEmpty
        ? catalogSections
        : [
            CatalogSectionV2(
              id: 'main',
              title: sectionTitle,
              items: [
                for (final item in values) VersionedMediaItem(item: item),
              ],
            ),
          ],
    subCategories: subCategories,
  );

  /// Items to return for a given category, falling back to [items].
  final Map<String?, List<MediaItemV2>> itemsByCategory;

  /// The `category` of the most recent [catalog] call.
  String? lastCategory;

  /// How many times [catalog] has been called — lets a test assert that a
  /// screen served a category from cache instead of fetching it again.
  int catalogCalls = 0;

  /// Subcategories every catalog response advertises.
  final List<SubCategory> subCategories;

  /// Items to return when a given subcategory is selected.
  final Map<String, List<MediaItemV2>> itemsBySubCategory;

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
    MediaItemV2 item, {
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
  MediaDetailV2? metaDetail;

  @override
  Future<MediaDetailV2> meta(MediaRef ref) async =>
      metaDetail ?? (throw UnsupportedError('$id does not provide meta'));

  /// What [preview] returns per item id; an id with no entry leaves it
  /// throwing, matching the protocol default for extensions that don't
  /// implement the role.
  final Map<String, PreviewResponse> previewFor;

  /// How many times [preview] has been called, keyed by item id — lets a
  /// test assert lazy/idempotent resolution (called once per item, not once
  /// up front for the whole feed).
  final Map<String, int> previewCalls = {};

  @override
  Future<PreviewResponse> preview(MediaItemV2 item) async {
    previewCalls.update(item.ref.id, (count) => count + 1, ifAbsent: () => 1);
    final response = previewFor[item.ref.id];
    if (response == null) {
      throw UnsupportedError('$id does not provide previews');
    }
    return response;
  }
}

class FakeCatalog {
  const FakeCatalog({
    required this.id,
    required this.name,
    required this.categories,
    required this.items,
    this.display = CatalogDisplay.row,
    this.expanded = false,
    this.surface = CatalogSurface.browse,
  });

  final String id;
  final String name;
  final List<String> categories;
  final List<MediaItemV2> items;
  final CatalogDisplay display;
  final bool expanded;

  /// Browse (the default, a Home shelf) or preview (a Shorts feed source).
  final CatalogSurface surface;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'categories': categories,
    'kind': 'video',
    'display': display.name,
    if (expanded) 'expanded': expanded,
    if (surface != CatalogSurface.browse) 'surface': surface.name,
  };
}

/// An extension whose sources each resolve to their own subtitle set — what
/// the real ones do, and what ordering by preferred language depends on.
class SubtitleFakeExtension extends ContentExtension {
  /// Creates a fake offering one source per key, resolving to those languages.
  SubtitleFakeExtension({required this.subtitlesBySourceId, this.resolveDelay})
    : _manifest = Manifest.parse({
        'apiVersion': 2,
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
  Future<VersionedCatalogPage> catalog(CatalogQuery query) async =>
      const VersionedCatalogPage(sections: []);

  @override
  Future<List<StreamSource>> sources(
    MediaItemV2 item, {
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
        for (final language
            in subtitlesBySourceId[sourceId] ?? const <String>[])
          SubtitleTrack(language: language, url: 'https://edge/$language.vtt'),
      ],
    );
  }
}

/// Builds a protocol-v2 item for tests.
MediaItemV2 fakeItem({
  String id = 'e1',
  String extensionId = 'fake',
  String title = 'Home vs Away',
  String? subtitle,
  ScheduleState status = ScheduleState.live,
  String? statusLabel,
  DateTime? startsAt,
  List<Participant> participants = const [],
  ImageRef? poster,
  String? group,
}) {
  final ref = MediaRef(
    extensionId: extensionId,
    providerId: '$extensionId.p',
    id: id,
  );
  if (poster != null) {
    return VideoItemV2(
      ref: ref,
      title: title,
      subtitle: subtitle,
      artwork: Artwork(portrait: poster),
    );
  }
  return EventItemV2(
    ref: ref,
    title: title,
    subtitle: subtitle ?? group,
    schedule: Schedule(
      startsAt: startsAt ?? DateTime.utc(2026, 1, 1),
      state: status,
      label: statusLabel,
    ),
    participants: participants,
  );
}

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

  /// The `preferredExternalSubtitle` the most recent build was called with —
  /// lets a test assert an external track only stands in for a source that
  /// carries nothing in the preferred language.
  SubtitleTrack? playedPreferredExternalSubtitle;

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
    void Function(Object? controller)? onPlaybackReady,
    Widget Function(
      BuildContext context,
      Object? controller,
      void Function(bool visibility) onVisibilityChanged,
    )?
    customControlsBuilder,
    String? preferredSubtitleLanguage,
    SubtitleTrack? preferredExternalSubtitle,
    SubtitleAppearance? subtitleAppearance,
    Key? key,
  }) {
    played = stream;
    playedIsLive = isLive;
    playedPreferredSubtitleLanguage = preferredSubtitleLanguage;
    playedPreferredExternalSubtitle = preferredExternalSubtitle;
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

/// A minimal [AppPlayerController] fake — just enough surface to construct
/// one and emit an [AppPlayerEventType.error] on demand.
class FakeAppPlayerController implements AppPlayerController {
  FakeAppPlayerController({AppPlayerValue initialValue = const AppPlayerValue()})
    : _value = ValueNotifier(initialValue);

  final ValueNotifier<AppPlayerValue> _value;
  final StreamController<AppPlayerEvent> _events =
      StreamController<AppPlayerEvent>.broadcast(sync: true);

  void emitError(Object error) {
    _events.add(AppPlayerEvent(AppPlayerEventType.error, error: error));
  }

  bool get hasListener => _events.hasListener;

  @override
  ValueListenable<AppPlayerValue> get value => _value;

  @override
  Stream<AppPlayerEvent> get events => _events.stream;

  @override
  List<AppQualityTrack> get qualityTracks => const [];

  @override
  AppQualityTrack? get activeQuality => null;

  @override
  List<AppAudioTrack> get audioTracks => const [];

  @override
  AppAudioTrack? get activeAudio => null;

  @override
  SubtitleTrack? get activeSubtitle => null;

  @override
  bool get isFullScreen => false;

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> seekTo(Duration position) async {}

  @override
  Future<void> setSubtitle(SubtitleTrack? track) async {}

  @override
  Future<void> setQuality(AppQualityTrack? track) async {}

  @override
  Future<void> setAudioTrack(AppAudioTrack track) async {}

  @override
  Future<void> setFit(PlayerFitMode mode) async {}

  @override
  Future<void> setViewportAspectRatio(double ratio) async {}

  @override
  Future<void> toggleFullScreen() async {}

  @override
  Future<void> exitFullScreen() async {}
}

/// A [PreviewNativePlayerBuilder] fake that records the stream/flags it was
/// given and renders a marker, so a test can assert preview playback started
/// without a native player. [controller] is a fresh [FakeAppPlayerController]
/// per build — use it to simulate a native playback error via [emitError].
class RecordingPreviewPlayer {
  PlayableStream? played;
  bool? playedMuted;
  bool? playedLooping;
  bool? playedPlaying;
  BoxFit? playedFit;
  int buildCount = 0;
  FakeAppPlayerController? controller;

  Widget build(
    BuildContext context,
    PlayableStream stream, {
    required bool muted,
    required bool looping,
    required bool playing,
    required BoxFit fit,
    Key? key,
    void Function(Object? controller)? onControllerCreated,
    void Function(Object? controller)? onPlaybackReady,
  }) {
    played = stream;
    playedMuted = muted;
    playedLooping = looping;
    playedPlaying = playing;
    playedFit = fit;
    buildCount++;
    controller = FakeAppPlayerController();
    onControllerCreated?.call(controller);
    return const SizedBox(key: Key('fake-preview-player'), height: 100);
  }

  void emitError(Object error) => controller?.emitError(error);
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
  SubtitleAppearancePreferences appearanceSaved =
      const SubtitleAppearancePreferences();

  final Map<String, SubtitleTrack> externalSelections = {};
  final Map<String, List<SubtitleTrack>> externalTracks = {};

  @override
  Future<String?> load() async => saved;

  @override
  Future<void> save(String? languageCode) async => saved = languageCode;

  @override
  Future<SubtitleAppearancePreferences> loadAppearance() async =>
      appearanceSaved;

  @override
  Future<void> saveAppearance(SubtitleAppearancePreferences appearance) async {
    appearanceSaved = appearance;
  }

  @override
  Future<Map<String, SubtitleTrack>> loadExternalSelections() async =>
      Map.of(externalSelections);

  @override
  Future<void> saveExternalSelection(MediaRef ref, SubtitleTrack? track) async {
    final key = '${ref.extensionId}\u0000${ref.providerId}\u0000${ref.id}';
    if (track == null) {
      externalSelections.remove(key);
    } else {
      externalSelections[key] = track;
    }
  }

  @override
  Future<Map<String, List<SubtitleTrack>>> loadExternalTracks() async => {
    for (final entry in externalTracks.entries) entry.key: List.of(entry.value),
  };

  @override
  Future<void> saveExternalTracks(
    MediaRef ref,
    List<SubtitleTrack> tracks,
  ) async {
    final key = '${ref.extensionId}\u0000${ref.providerId}\u0000${ref.id}';
    externalTracks[key] = List.of(tracks);
  }
}

class FakeSourcePriorityStore implements SourcePriorityStore {
  List<String> saved = const [];

  @override
  Future<List<String>> load() async => saved;

  @override
  Future<void> save(List<String> providerIds) async => saved = providerIds;
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

/// In-memory NSFW preference store.
class FakeNsfwSettingsStore implements NsfwSettingsStore {
  NsfwSettings saved = const NsfwSettings();

  @override
  Future<NsfwSettings> load() async => saved;

  @override
  Future<void> save(NsfwSettings settings) async => saved = settings;
}

/// Wraps [child] in an [AppScope] + [MaterialApp] for pumping a screen.
///
/// Pages that aren't themselves a [Scaffold] (HomePage, which normally sits
/// inside HomeShell's) get one here, so Material widgets find their ancestor
/// the same way they do in the running app. A [child] that brings its own
/// Scaffold is unaffected by the extra one.
///
/// Controllers default to fresh in-memory stores — pass an explicit one when a test needs to
/// observe toggles, favorites, or persistence.
Widget wrapApp({
  required Widget child,
  required ExtensionRegistry registry,
  DeviceClass deviceClass = DeviceClass.handheld,
  RecordingPlayer? player,
  RecordingPreviewPlayer? previewPlayer,
  AddonsController? addonsController,
  InstallerController? installerController,
  LibraryController? libraryController,
  PluginController? pluginController,
  CatalogCache? catalogCache,
  SubtitlePreferenceController? subtitlePreferenceController,
  SourcePriorityController? sourcePriorityController,
  CategorySelectionStore? homeCategoryStore,
  SourceCache? sourceCache,
  NsfwController? nsfwController,
}) => AppScope(
  registry: registry,
  deviceClass: deviceClass,
  playerBuilder: (player ?? RecordingPlayer()).build,
  previewPlayerBuilder: (previewPlayer ?? RecordingPreviewPlayer()).build,
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
      libraryController ?? LibraryController(store: _FakeLibraryStoreV2()),
  pluginController:
      pluginController ?? PluginController(store: FakePluginSelectionStore()),
  catalogCache: catalogCache ?? CatalogCache(),
  subtitlePreferenceController:
      subtitlePreferenceController ??
      SubtitlePreferenceController(store: FakeSubtitlePreferenceStore()),
  sourcePriorityController:
      sourcePriorityController ??
      SourcePriorityController(
        registry: registry,
        store: FakeSourcePriorityStore(),
      ),
  homeCategoryStore: homeCategoryStore ?? FakeCategorySelectionStore(),
  sourceCache: sourceCache ?? SourceCache(),
  nsfwController:
      nsfwController ??
      NsfwController(
        registry: registry,
        store: FakeNsfwSettingsStore(),
        showNsfw: registry.showNsfw,
      ),
  child: MaterialApp(home: Scaffold(body: child)),
);

class _FakeLibraryStoreV2 implements LibraryStore {
  @override
  Future<Map<String, UserMediaState>> load() async => {};

  @override
  Future<void> save(Map<String, UserMediaState> records) async {}
}
