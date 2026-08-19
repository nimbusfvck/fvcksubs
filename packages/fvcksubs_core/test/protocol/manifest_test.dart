import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:test/test.dart';

import '../support/round_trip.dart';

/// A representative Cricfy-shaped manifest, matching PLAN.md.
Map<String, Object?> cricfyManifestJson() => {
  'apiVersion': 1,
  'id': 'cricfy',
  'name': 'Cricfy',
  'version': '1.2.0',
  'runtime': 'js',
  'entry': 'bundle.js',
  'categories': ['live', 'sport'],
  'providers': [
    {
      'id': 'cricfy.events',
      'name': 'Atlas',
      'roles': ['catalog', 'stream'],
      'catalogs': [
        {
          'id': 'live',
          'name': 'Live Now',
          'category': 'live',
          'kind': 'liveEvent',
          'filters': ['date'],
        },
      ],
    },
  ],
  'permissions': {
    'hosts': ['*.cricyplayers.com', 'p.genzdev.xyz', 'c.playtek.xyz'],
  },
};

void main() {
  group('Manifest.parse', () {
    test('parses a valid manifest and round-trips', () {
      final manifest = Manifest.parse(cricfyManifestJson());

      expect(manifest.id, 'cricfy');
      expect(manifest.categories, contains('sport'));
      expect(manifest.providers.single.roles, [
        ProviderRole.catalog,
        ProviderRole.stream,
      ]);
      expect(manifest.providers.single.name, 'Atlas');
      expect(
        manifest.providers.single.catalogs.single.kind,
        MediaKind.liveEvent,
      );
      expect(manifest.permissions.hosts, hasLength(3));
      // Not declared in the fixture, so it falls back to the safe default.
      expect(
        manifest.providers.single.catalogs.single.display,
        CatalogDisplay.grid,
      );

      expectRoundTrips(
        manifest,
        toJson: (m) => m.toJson(),
        fromJson: Manifest.parse,
      );
    });

    test('rejects an apiVersion newer than this build', () {
      final json = cricfyManifestJson()..['apiVersion'] = 2;
      expect(
        () => Manifest.parse(json),
        throwsA(
          isA<ManifestException>().having(
            (e) => e.message,
            'message',
            contains('newer app'),
          ),
        ),
      );
    });

    test('rejects a missing apiVersion', () {
      final json = cricfyManifestJson()..remove('apiVersion');
      expect(() => Manifest.parse(json), throwsA(isA<ManifestException>()));
    });

    test('rejects an invalid apiVersion (< 1)', () {
      final json = cricfyManifestJson()..['apiVersion'] = 0;
      expect(() => Manifest.parse(json), throwsA(isA<ManifestException>()));
    });

    test('reads an explicit display, and survives an unknown one', () {
      Manifest withDisplay(Object? display) {
        final json = cricfyManifestJson();
        final providers = json['providers']! as List;
        final catalogs =
            (providers.single as Map<String, Object?>)['catalogs']! as List;
        (catalogs.single as Map<String, Object?>)['display'] = display;
        return Manifest.parse(json);
      }

      expect(
        withDisplay('row').providers.single.catalogs.single.display,
        CatalogDisplay.row,
      );
      // A display shape a future app version might add: fall back rather than
      // refuse the whole manifest, since layout is cosmetic.
      expect(
        withDisplay('hologram').providers.single.catalogs.single.display,
        CatalogDisplay.grid,
      );
    });

    test('wraps a malformed body in ManifestException', () {
      final json = cricfyManifestJson()..['id'] = 123; // wrong type
      expect(
        () => Manifest.parse(json),
        throwsA(
          isA<ManifestException>().having(
            (e) => e.message,
            'message',
            contains('malformed'),
          ),
        ),
      );
    });
  });

  test('CatalogQuery and CatalogPage round-trip', () {
    const query = CatalogQuery(
      providerId: 'cricfy.events',
      catalogId: 'live',
      filters: {'date': '2026-08-16'},
    );
    expectRoundTrips(
      query,
      toJson: (q) => q.toJson(),
      fromJson: CatalogQuery.fromJson,
    );

    const page = CatalogPage(
      items: [
        MediaItem(
          ref: MediaRef(
            extensionId: 'cricfy',
            providerId: 'cricfy.events',
            id: 'e1',
          ),
          kind: MediaKind.liveEvent,
          title: 'Event One',
        ),
      ],
      nextPage: 'cursor-2',
    );
    expectRoundTrips(
      page,
      toJson: (p) => p.toJson(),
      fromJson: CatalogPage.fromJson,
    );
  });

  group('optional metadata (M25)', () {
    Map<String, Object?> base() => {
      'apiVersion': 1,
      'id': 'x',
      'name': 'X',
      'version': '1.0.0',
      'runtime': 'js',
      'categories': <String>['live'],
      'providers': <Object?>[],
      'permissions': {'hosts': <String>[]},
    };

    test('description/author/iconUrl round-trip when present', () {
      final manifest = Manifest.parse({
        ...base(),
        'description': 'What it is for.',
        'author': 'Someone',
        'iconUrl': 'https://x/icon.png',
      });

      expect(manifest.description, 'What it is for.');
      expect(manifest.author, 'Someone');
      expect(manifest.iconUrl, 'https://x/icon.png');
      expect(Manifest.parse(manifest.toJson()), manifest);
    });

    test('a manifest without them still parses — they are additive', () {
      // The point of keeping apiVersion at 1: an older manifest is not
      // invalidated by fields added later.
      final manifest = Manifest.parse(base());
      expect(manifest.description, isNull);
      expect(manifest.author, isNull);
      expect(manifest.iconUrl, isNull);
      expect(manifest.toJson().containsKey('description'), isFalse);
    });
  });

  group('subCategories (M26)', () {
    test('CatalogPage round-trips its subCategories', () {
      const page = CatalogPage(
        items: [],
        subCategories: [
          SubCategory(id: 'epl', name: 'Premier League'),
          SubCategory(id: 'liga1', name: 'Liga 1'),
        ],
      );

      final decoded = CatalogPage.fromJson(page.toJson());
      expect(decoded, page);
      expect(decoded.subCategories.map((s) => s.name), [
        'Premier League',
        'Liga 1',
      ]);
    });

    test('a catalog with no subCategories omits the key entirely', () {
      const page = CatalogPage(items: []);
      expect(page.subCategories, isEmpty);
      expect(page.toJson().containsKey('subCategories'), isFalse);
      // The common case stays exactly as it was — additive, not a new
      // requirement on every catalog.
      expect(CatalogPage.fromJson(page.toJson()), page);
    });

    test('CatalogQuery round-trips the selected subCategory', () {
      const query = CatalogQuery(
        providerId: 'p',
        catalogId: 'c',
        subCategory: 'epl',
      );
      expect(CatalogQuery.fromJson(query.toJson()), query);
      expect(query.toJson()['subCategory'], 'epl');
    });

    test('an unnarrowed query omits subCategory', () {
      const query = CatalogQuery(providerId: 'p', catalogId: 'c');
      expect(query.subCategory, isNull);
      expect(query.toJson().containsKey('subCategory'), isFalse);
    });

    test('subCategory takes part in equality — two narrowings differ', () {
      const a = CatalogQuery(providerId: 'p', catalogId: 'c', subCategory: 'x');
      const b = CatalogQuery(providerId: 'p', catalogId: 'c', subCategory: 'y');
      expect(a, isNot(b));
    });
  });
}
