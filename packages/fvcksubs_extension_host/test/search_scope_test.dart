@TestOn('vm')
library;

import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';
import 'package:test/test.dart';

/// Which extensions a scoped search reaches, and which scopes exist at all.
///
/// The scopes are not configured anywhere — they are whatever the installed
/// extensions declare, the same rule Home's categories follow. So the tests
/// here are all about derivation from a manifest.
void main() {
  _Stub stub(
    String id, {
    required List<String> categories,
    List<String> searchCategories = const [],
    bool withCatalog = true,
    ContentRating? catalogRating,
  }) => _Stub(
    Manifest.parse({
      'apiVersion': 2,
      'id': id,
      'name': id,
      'version': '1.0.0',
      'runtime': 'builtin',
      'categories': categories,
      'providers': [
        {
          'id': '$id.p',
          'roles': ['search', if (withCatalog) 'catalog'],
          if (searchCategories.isNotEmpty) 'searchCategories': searchCategories,
          if (withCatalog)
            'catalogs': [
              {
                'id': 'c',
                'name': 'C',
                'categories': categories,
                'kind': 'movie',
                if (catalogRating != null) 'contentRating': catalogRating.name,
              },
            ],
        },
      ],
      'permissions': {'hosts': <String>[]},
    }),
  );

  test('scopes come from the catalogs a searchable provider serves', () {
    final registry = ExtensionRegistry([
      stub('a', categories: ['movie', 'tv']),
      stub('b', categories: ['anime']),
    ]);

    expect(registry.searchCategories, ['movie', 'tv', 'anime']);
  });

  test('a category served twice is offered once', () {
    final registry = ExtensionRegistry([
      stub('a', categories: ['anime']),
      stub('b', categories: ['anime', 'movie']),
    ]);

    expect(registry.searchCategories, ['anime', 'movie']);
  });

  test('`all` is never a scope', () {
    // It is Home's "everything" chip; Search says that by choosing nothing.
    final registry = ExtensionRegistry([
      stub('a', categories: ['all', 'movie']),
    ]);

    expect(registry.searchCategories, ['movie']);
  });

  test('a search-only provider declares its scopes itself', () {
    // Nothing to derive from — this is the shape a music provider takes
    // before it has a catalog, and it should still be reachable.
    final registry = ExtensionRegistry([
      stub(
        'a',
        categories: ['music'],
        searchCategories: ['music'],
        withCatalog: false,
      ),
    ]);

    expect(registry.searchCategories, ['music']);
  });

  test('a mature catalog keeps its scope off the row until NSFW is on', () {
    ExtensionRegistry registryWith({required bool showNsfw}) =>
        ExtensionRegistry([
          stub('a', categories: ['movie']),
          stub(
            'b',
            categories: ['nsfw'],
            catalogRating: ContentRating.mature,
          ),
        ], showNsfw: showNsfw);

    expect(registryWith(showNsfw: false).searchCategories, ['movie']);
    expect(registryWith(showNsfw: true).searchCategories, ['movie', 'nsfw']);
  });

  test('a disabled extension takes its scopes with it', () {
    final registry = ExtensionRegistry([
      stub('a', categories: ['movie']),
      stub('b', categories: ['anime']),
    ], disabledExtensionIds: {'b'});

    expect(registry.searchCategories, ['movie']);
  });

  test('a scoped search only reaches what declares the scope', () async {
    final anime = stub('b', categories: ['anime']);
    final registry = ExtensionRegistry([
      stub('a', categories: ['movie']),
      anime,
    ]);

    final results = await registry.search('one piece', category: 'anime');

    expect(results.map((r) => r.item.ref.extensionId), ['b']);
    expect(anime.searchScopes, ['anime']);
  });

  test('an unscoped search still reaches everything', () async {
    final registry = ExtensionRegistry([
      stub('a', categories: ['movie']),
      stub('b', categories: ['anime']),
    ]);

    final results = await registry.search('one piece');

    expect(results.map((r) => r.item.ref.extensionId), ['a', 'b']);
  });
}

/// A [ContentExtension] that answers search with one item naming itself, and
/// records the scope it was asked for.
class _Stub extends ContentExtension {
  _Stub(this.manifest);

  @override
  final Manifest manifest;

  final List<String?> searchScopes = [];

  @override
  Future<VersionedCatalogPage> search(
    String query, {
    String? page,
    String? category,
  }) async {
    searchScopes.add(category);
    return VersionedCatalogPage(
      sections: [
        CatalogSectionV2(
          id: 'main',
          items: [
            VersionedMediaItem(
              item: VideoItemV2(
                ref: MediaRef(
                  extensionId: manifest.id,
                  providerId: '${manifest.id}.p',
                  id: 'hit',
                ),
                title: query,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
