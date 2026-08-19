import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';
import 'package:test/test.dart';

/// A configurable in-memory extension for exercising the registry offline.
class FakeExtension extends ContentExtension {
  FakeExtension({
    required String id,
    required List<String> categories,
    Map<String, List<MediaItem>> catalogItems = const {},
    bool extraCatalog = false,
    this.failCatalog = false,
    this.searchable = false,
    this.searchResults = const [],
    this.failSearch = false,
    this.pages = const {},
    bool streams = true,
    bool subtitlesRole = false,
    this.externalSubtitlesResult = const [],
    this.failExternalSubtitles = false,
  }) : _manifest = Manifest.parse({
         'apiVersion': 1,
         'id': id,
         'name': id,
         'version': '1.0.0',
         'runtime': 'builtin',
         'categories': categories,
         'providers': [
           {
             'id': '$id.p',
             'roles': [
               'catalog',
               if (streams) 'stream',
               if (searchable) 'search',
               if (subtitlesRole) 'subtitles',
             ],
             'catalogs': [
               {
                 'id': 'catalog',
                 'name': id,
                 'categories': categories,
                 'kind': 'liveEvent',
               },
               if (extraCatalog)
                 {
                   'id': 'catalog2',
                   'name': '$id 2',
                   'categories': categories,
                   'kind': 'liveEvent',
                 },
             ],
           },
         ],
         'permissions': {'hosts': <String>[]},
       }),
       _catalogItems = catalogItems;

  final Manifest _manifest;
  final Map<String, List<MediaItem>> _catalogItems;

  /// When true, [catalog] throws — to test fan-out tolerance.
  final bool failCatalog;

  /// Whether this extension declares the `search` role.
  final bool searchable;

  /// Items [search] returns for any non-empty query.
  final List<MediaItem> searchResults;

  /// When true, [search] throws — to test fan-out tolerance.
  final bool failSearch;

  /// Cursor-keyed catalog pages, for exercising pagination: `pages[null]` is
  /// the first page, `pages['cursor']` is what a matching `nextPage` yields.
  final Map<String?, CatalogPage> pages;

  @override
  Manifest get manifest => _manifest;

  @override
  Future<CatalogPage> catalog(CatalogQuery query) async {
    if (failCatalog) throw StateError('catalog is down');
    if (pages.isNotEmpty) return pages[query.page] ?? const CatalogPage(items: []);
    return CatalogPage(items: _catalogItems[query.catalogId] ?? const []);
  }

  @override
  Future<CatalogPage> search(String query, {String? page}) async {
    if (failSearch) throw StateError('search is down');
    return CatalogPage(items: searchResults);
  }

  /// The `enabledProviders` the registry passed to the most recent [sources]
  /// call — lets a test assert what the per-source toggle computed.
  Set<String>? lastEnabledProviders;

  @override
  Future<List<StreamSource>> sources(
    MediaItem item, {
    Set<String>? enabledProviders,
  }) async {
    lastEnabledProviders = enabledProviders;
    return [StreamSource(id: 'src-of-${item.ref.id}', label: manifest.id)];
  }

  @override
  Future<PlayableStream> resolve(String sourceId) async =>
      PlayableStream(url: 'https://example/$sourceId.m3u8');

  /// What [meta] returns; `null` leaves it throwing, matching the protocol
  /// default.
  MediaDetail? metaDetail;

  @override
  Future<MediaDetail> meta(MediaRef ref) async =>
      metaDetail ?? (throw UnsupportedError('${manifest.id} does not provide meta'));

  /// What [externalSubtitles] returns when it doesn't throw.
  final List<SubtitleTrack> externalSubtitlesResult;

  /// When true, [externalSubtitles] throws — to test fan-out tolerance.
  final bool failExternalSubtitles;

  /// How many times [externalSubtitles] was actually called — lets a test
  /// assert a role guard skipped calling it at all, not just that the
  /// result came back empty.
  int externalSubtitlesCalls = 0;

  @override
  Future<List<SubtitleTrack>> externalSubtitles(MediaItem item) async {
    externalSubtitlesCalls++;
    if (failExternalSubtitles) throw StateError('subtitle lookup is down');
    return externalSubtitlesResult;
  }
}

MediaItem _item(String extId, String id) => MediaItem(
  ref: MediaRef(extensionId: extId, providerId: '$extId.p', id: id),
  kind: MediaKind.liveEvent,
  title: id,
);

void main() {
  group('categories', () {
    test('are the union of installed extensions, first-seen order', () {
      final registry = ExtensionRegistry([
        FakeExtension(id: 'a', categories: ['live', 'sport']),
        FakeExtension(id: 'b', categories: ['sport', 'movie']),
      ]);
      expect(registry.categories, ['live', 'sport', 'movie']);
    });

    test('an empty registry has no categories', () {
      expect(ExtensionRegistry([]).categories, isEmpty);
    });
  });

  group('catalogsFor', () {
    test('returns one binding per catalog, unmerged, across extensions', () {
      final registry = ExtensionRegistry([
        FakeExtension(id: 'a', categories: ['sport']),
        FakeExtension(id: 'b', categories: ['sport']),
      ]);

      final bindings = registry.catalogsFor('sport');
      expect(bindings, hasLength(2));
      expect(bindings.map((b) => b.extensionId), ['a', 'b']);
      expect(bindings.every((b) => b.categories.contains('sport')), isTrue);
    });

    test('an unknown category has no catalogs', () {
      final registry = ExtensionRegistry([
        FakeExtension(id: 'a', categories: ['sport']),
      ]);
      expect(registry.catalogsFor('movie'), isEmpty);
    });

    test('one catalog spanning categories is found under each', () {
      // The shape the protocol expects: a catalog is the root of what a
      // provider serves and lists the categories inside it, so the same
      // declaration answers for both.
      final registry = ExtensionRegistry([
        FakeExtension(id: 'a', categories: ['live', 'sport']),
      ]);

      final live = registry.catalogsFor('live');
      final sport = registry.catalogsFor('sport');
      expect(live, hasLength(1));
      expect(sport, hasLength(1));
      expect(live.single.catalog.id, sport.single.catalog.id);
    });
  });

  group('pluginsFor', () {
    test('one entry per extension serving the category, in install order', () {
      final registry = ExtensionRegistry([
        FakeExtension(id: 'a', categories: ['sport']),
        FakeExtension(id: 'b', categories: ['sport']),
        FakeExtension(id: 'c', categories: ['movie']),
      ]);

      expect(registry.pluginsFor('sport').map((m) => m.id), ['a', 'b']);
      expect(registry.pluginsFor('movie').map((m) => m.id), ['c']);
    });

    test('a disabled extension is not offered', () {
      final registry = ExtensionRegistry([
        FakeExtension(id: 'a', categories: ['sport']),
        FakeExtension(id: 'b', categories: ['sport']),
      ]);
      registry.setExtensionEnabled('a', false);

      expect(registry.pluginsFor('sport').map((m) => m.id), ['b']);
    });

    test('an extension is listed once even if it declares two catalogs', () {
      final registry = ExtensionRegistry([
        FakeExtension(id: 'a', categories: ['sport'], extraCatalog: true),
      ]);

      expect(registry.catalogsFor('sport'), hasLength(2));
      expect(registry.pluginsFor('sport').map((m) => m.id), ['a']);
    });
  });

  group('loadCatalog', () {
    test('loads a single catalog\'s items', () async {
      final registry = ExtensionRegistry([
        FakeExtension(
          id: 'a',
          categories: ['sport'],
          catalogItems: {
            'catalog': [_item('a', 'a1'), _item('a', 'a2')],
          },
        ),
      ]);

      final page = await registry.loadCatalog(
        registry.catalogsFor('sport').single,
      );
      expect(page.items.map((i) => i.ref.id), ['a1', 'a2']);
    });

    test('propagates a failure instead of swallowing it', () {
      // Each shelf owns its own error state, so the registry must not hide
      // this — one dead catalog shows an error in its shelf, and the other
      // shelves still render.
      final registry = ExtensionRegistry([
        FakeExtension(id: 'a', categories: ['sport'], failCatalog: true),
      ]);

      expect(
        registry.loadCatalog(registry.catalogsFor('sport').single),
        throwsA(isA<StateError>()),
      );
    });

    test('a page cursor fetches the next page', () async {
      final registry = ExtensionRegistry([
        FakeExtension(
          id: 'a',
          categories: ['sport'],
          pages: {
            null: CatalogPage(items: [_item('a', 'a1')], nextPage: 'p2'),
            'p2': CatalogPage(items: [_item('a', 'a2')]),
          },
        ),
      ]);
      final binding = registry.catalogsFor('sport').single;

      final first = await registry.loadCatalog(binding);
      expect(first.items.map((i) => i.ref.id), ['a1']);
      expect(first.nextPage, 'p2');

      final second = await registry.loadCatalog(binding, page: first.nextPage);
      expect(second.items.map((i) => i.ref.id), ['a2']);
      expect(second.nextPage, isNull);
    });
  });

  group('search', () {
    test('fans out to every search-role extension and merges the results', () async {
      final registry = ExtensionRegistry([
        FakeExtension(
          id: 'a',
          categories: ['sport'],
          searchable: true,
          searchResults: [_item('a', 'a1')],
        ),
        FakeExtension(
          id: 'b',
          categories: ['movie'],
          searchable: true,
          searchResults: [_item('b', 'b1')],
        ),
      ]);

      final results = await registry.search('anything');
      expect(results.map((i) => i.ref.id), ['a1', 'b1']);
    });

    test('skips an extension that doesn\'t declare the search role', () async {
      final registry = ExtensionRegistry([
        FakeExtension(
          id: 'a',
          categories: ['sport'],
          searchable: false,
          searchResults: [_item('a', 'a1')],
        ),
      ]);

      expect(await registry.search('anything'), isEmpty);
    });

    test('one provider failing does not blank the others\' results', () async {
      final registry = ExtensionRegistry([
        FakeExtension(id: 'a', categories: ['sport'], searchable: true, failSearch: true),
        FakeExtension(
          id: 'b',
          categories: ['movie'],
          searchable: true,
          searchResults: [_item('b', 'b1')],
        ),
      ]);

      final results = await registry.search('anything');
      expect(results.map((i) => i.ref.id), ['b1']);
    });

    test('an empty registry returns no results', () async {
      expect(await ExtensionRegistry([]).search('anything'), isEmpty);
    });

    test('skips a disabled provider even on an enabled extension', () async {
      final registry = ExtensionRegistry([
        FakeExtension(
          id: 'a',
          categories: ['sport'],
          searchable: true,
          searchResults: [_item('a', 'a1')],
        ),
      ]);
      expect(await registry.search('anything'), isNotEmpty);

      registry.setProviderEnabled('a.p', false);
      expect(await registry.search('anything'), isEmpty);
    });

    test('skips a disabled extension even if its provider is enabled', () async {
      final registry = ExtensionRegistry([
        FakeExtension(
          id: 'a',
          categories: ['sport'],
          searchable: true,
          searchResults: [_item('a', 'a1')],
        ),
      ], disabledExtensionIds: {'a'});

      expect(await registry.search('anything'), isEmpty);
    });
  });

  group('enable/disable', () {
    test('starts enabled; setExtensionEnabled toggles categories/catalogs live', () {
      final registry = ExtensionRegistry([
        FakeExtension(id: 'a', categories: ['sport']),
      ]);
      expect(registry.isExtensionEnabled('a'), isTrue);
      expect(registry.categories, ['sport']);

      registry.setExtensionEnabled('a', false);
      expect(registry.isExtensionEnabled('a'), isFalse);
      expect(registry.categories, isEmpty);
      expect(registry.catalogsFor('sport'), isEmpty);

      registry.setExtensionEnabled('a', true);
      expect(registry.categories, ['sport']);
    });

    test('seeding disabled ids at construction takes effect immediately', () {
      final registry = ExtensionRegistry([
        FakeExtension(id: 'a', categories: ['sport']),
      ], disabledExtensionIds: {'a'});
      expect(registry.categories, isEmpty);
      expect(registry.disabledExtensionIds, {'a'});
    });

    test('setProviderEnabled excludes that provider\'s catalogs only', () {
      final registry = ExtensionRegistry([
        FakeExtension(id: 'a', categories: ['sport']),
        FakeExtension(id: 'b', categories: ['sport']),
      ]);
      expect(registry.catalogsFor('sport'), hasLength(2));

      registry.setProviderEnabled('a.p', false);
      final bindings = registry.catalogsFor('sport');
      expect(bindings, hasLength(1));
      expect(bindings.single.extensionId, 'b');
    });

    test('sources() short-circuits to empty for a disabled extension, without calling it', () async {
      final fake = FakeExtension(id: 'a', categories: ['sport']);
      final registry = ExtensionRegistry([fake], disabledExtensionIds: {'a'});

      expect(await registry.sources(_item('a', 'x')), isEmpty);
      expect(fake.lastEnabledProviders, isNull);
    });

    test('sources() passes only this extension\'s enabled stream providers', () async {
      final fake = FakeExtension(id: 'a', categories: ['sport']);
      final registry = ExtensionRegistry([fake]);

      await registry.sources(_item('a', 'x'));
      expect(fake.lastEnabledProviders, {'a.p'});

      registry.setProviderEnabled('a.p', false);
      await registry.sources(_item('a', 'x'));
      expect(fake.lastEnabledProviders, isEmpty);
    });
  });

  group('routing', () {
    final registry = ExtensionRegistry([
      FakeExtension(id: 'a', categories: ['sport']),
      FakeExtension(id: 'b', categories: ['movie']),
    ]);

    test('sources go to the extension that owns the item', () async {
      final sources = await registry.sources(_item('b', 'x'));
      expect(sources.single.label, 'b');
      expect(sources.single.id, 'src-of-x');
    });

    test('resolveSource routes by ref extension', () async {
      final stream = await registry.resolveSource(_item('a', 'x').ref, 'k');
      expect(stream.url, 'https://example/k.m3u8');
    });

    test('an unknown extension id throws', () {
      expect(() => registry.sources(_item('ghost', '1')), throwsStateError);
    });

    test('a catalog-only extension yields no sources, and is not asked', () {
      // ContentExtension.sources throws by default — it is a guard for a role
      // the manifest never declared, not a code path. Before this, a
      // catalog-only extension (the JS by433 port is one) turned every detail
      // page into an error.
      final registry = ExtensionRegistry([
        FakeExtension(id: 'catalog-only', categories: ['live'], streams: false),
      ]);
      final item = MediaItem(
        ref: const MediaRef(
          extensionId: 'catalog-only',
          providerId: 'catalog-only.p',
          id: '1',
        ),
        kind: MediaKind.liveEvent,
        title: 'A vs B',
      );

      expect(registry.sources(item), completion(isEmpty));
    });

    group('externalSubtitles', () {
      test('reaches an extension that declares the role', () async {
        final fake = FakeExtension(
          id: 'subs',
          categories: ['movie'],
          subtitlesRole: true,
          externalSubtitlesResult: const [
            SubtitleTrack(language: 'id', url: 'https://x/id.srt'),
          ],
        );
        final registry = ExtensionRegistry([fake]);

        final tracks = await registry.externalSubtitles(_item('subs', 'x'));
        expect(tracks, hasLength(1));
        expect(tracks.single.language, 'id');
      });

      test('an extension that never declares the role is not asked', () async {
        // ContentExtension.externalSubtitles throws by default — a guard for
        // a role the manifest never declared, not a code path. Every
        // FakeExtension here omits `subtitlesRole`, mirroring the vast
        // majority of extensions that won't offer this fallback.
        final fake = FakeExtension(id: 'a', categories: ['sport']);
        final registry = ExtensionRegistry([fake]);

        expect(await registry.externalSubtitles(_item('a', 'x')), isEmpty);
        expect(fake.externalSubtitlesCalls, 0);
      });

      test('short-circuits to empty for a disabled extension, without calling it', () async {
        final fake = FakeExtension(
          id: 'subs',
          categories: ['movie'],
          subtitlesRole: true,
        );
        final registry = ExtensionRegistry(
          [fake],
          disabledExtensionIds: {'subs'},
        );

        expect(await registry.externalSubtitles(_item('subs', 'x')), isEmpty);
        expect(fake.externalSubtitlesCalls, 0);
      });

      test('a lookup failure comes back empty rather than throwing', () async {
        final fake = FakeExtension(
          id: 'subs',
          categories: ['movie'],
          subtitlesRole: true,
          failExternalSubtitles: true,
        );
        final registry = ExtensionRegistry([fake]);

        expect(await registry.externalSubtitles(_item('subs', 'x')), isEmpty);
      });
    });

    test('meta routes to the extension that owns the ref', () async {
      final detail = MediaDetail(item: _item('a', 'x'));
      final extension = registry.extensionById('a') as FakeExtension;
      extension.metaDetail = detail;

      expect(await registry.meta(_item('a', 'x').ref), detail);
    });
  });

  group('install / uninstall at runtime', () {
    test('install adds a new extension and its categories appear', () {
      final registry = ExtensionRegistry([
        FakeExtension(id: 'a', categories: ['live']),
      ]);
      expect(registry.installed.map((m) => m.id), ['a']);

      final replaced = registry.install(
        FakeExtension(id: 'b', categories: ['sport']),
      );

      expect(replaced, isNull, reason: 'fresh install replaces nothing');
      expect(registry.installed.map((m) => m.id), ['a', 'b']);
      expect(registry.categories, contains('sport'));
    });

    test('installing the same id replaces in place, not appends', () {
      final registry = ExtensionRegistry([
        FakeExtension(id: 'a', categories: ['live']),
        FakeExtension(id: 'b', categories: ['sport']),
      ]);
      final original = registry.extensionById('a');

      final replacement = FakeExtension(id: 'a', categories: ['movie']);
      final replaced = registry.install(replacement);

      expect(replaced, same(original), reason: 'caller must be able to dispose it');
      expect(registry.installed.map((m) => m.id), ['a', 'b'],
          reason: 'replaced in place, so order is unchanged');
      expect(registry.extensionById('a'), same(replacement));
      expect(registry.categories, contains('movie'));
    });

    test('a disabled extension stays disabled after being replaced', () {
      final registry = ExtensionRegistry([
        FakeExtension(id: 'a', categories: ['live']),
      ]);
      registry.setExtensionEnabled('a', false);

      registry.install(FakeExtension(id: 'a', categories: ['live']));

      expect(registry.isExtensionEnabled('a'), isFalse,
          reason: 'updating an extension the user switched off must not switch it back on');
    });

    test('uninstall removes the extension and returns it', () {
      final registry = ExtensionRegistry([
        FakeExtension(id: 'a', categories: ['live']),
        FakeExtension(id: 'b', categories: ['sport']),
      ]);
      final original = registry.extensionById('b');

      final removed = registry.uninstall('b');

      expect(removed, same(original));
      expect(registry.installed.map((m) => m.id), ['a']);
      expect(registry.categories, isNot(contains('sport')));
    });

    test('uninstalling an id that is not installed returns null', () {
      final registry = ExtensionRegistry([
        FakeExtension(id: 'a', categories: ['live']),
      ]);
      expect(registry.uninstall('nope'), isNull);
      expect(registry.installed, hasLength(1));
    });
  });
}
