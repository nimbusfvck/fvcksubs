import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:test/test.dart';

import '../support/round_trip.dart';

void main() {
  test('a catalog without "surface" decodes to browse', () {
    final catalog = CatalogDecl.fromJson({
      'id': 'discover',
      'name': 'Discover',
      'categories': ['movie'],
    });
    expect(catalog.surface, CatalogSurface.browse);
    expect(catalog.toJson().containsKey('surface'), isFalse);
  });

  test('a catalog declaring "surface": "preview" decodes correctly', () {
    final catalog = CatalogDecl.fromJson({
      'id': 'previews',
      'name': 'Previews',
      'categories': <String>[],
      'surface': 'preview',
    });
    expect(catalog.surface, CatalogSurface.preview);
    expect(catalog.categories, isEmpty);
  });

  test('CatalogDecl round-trips with a non-default surface', () {
    const catalog = CatalogDecl(
      id: 'previews',
      name: 'Previews',
      categories: [],
      surface: CatalogSurface.preview,
    );
    expectRoundTrips(
      catalog,
      toJson: (c) => c.toJson(),
      fromJson: CatalogDecl.fromJson,
    );
    expect(catalog.toJson()['surface'], 'preview');
  });

  test('CatalogDecl round-trips with the default browse surface', () {
    const catalog = CatalogDecl(
      id: 'discover',
      name: 'Discover',
      categories: ['movie', 'tv'],
    );
    expectRoundTrips(
      catalog,
      toJson: (c) => c.toJson(),
      fromJson: CatalogDecl.fromJson,
    );
  });

  test('an unrecognized surface value falls back to browse', () {
    final catalog = CatalogDecl.fromJson({
      'id': 'discover',
      'name': 'Discover',
      'categories': ['movie'],
      'surface': 'something-future-apps-invented',
    });
    expect(catalog.surface, CatalogSurface.browse);
  });

  test('a legacy manifest with no surface field parses unchanged', () {
    final manifest = Manifest.parse({
      'apiVersion': 2,
      'id': 'legacy',
      'name': 'Legacy Extension',
      'version': '1.0.0',
      'runtime': 'js',
      'categories': ['movie'],
      'providers': [
        {
          'id': 'legacy.catalog',
          'roles': ['catalog'],
          'catalogs': [
            {
              'id': 'discover',
              'name': 'Discover',
              'categories': ['movie'],
            },
          ],
        },
      ],
      'permissions': {'hosts': <String>[]},
    });

    final catalog = manifest.providers.single.catalogs.single;
    expect(catalog.surface, CatalogSurface.browse);
  });

  test('a preview-only catalog with no browse categories parses', () {
    final manifest = Manifest.parse({
      'apiVersion': 2,
      'id': 'nimora',
      'name': 'Nimora',
      'version': '1.0.0',
      'runtime': 'js',
      'categories': ['movie'],
      'providers': [
        {
          'id': 'nimora.tmdb',
          'roles': ['catalog'],
          'catalogs': [
            {
              'id': 'previews',
              'name': 'Previews',
              'categories': <String>[],
              'surface': 'preview',
            },
          ],
        },
      ],
      'permissions': {'hosts': <String>[]},
    });

    final catalog = manifest.providers.single.catalogs.single;
    expect(catalog.surface, CatalogSurface.preview);
    expect(catalog.categories, isEmpty);
  });
}
