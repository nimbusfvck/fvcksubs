import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';
import 'package:test/test.dart';

void main() {
  test('mature catalogs are hidden until NSFW is enabled', () {
    final extension = _FakeExtension(ContentRating.mature);
    final registry = ExtensionRegistry([extension]);

    expect(registry.categories, isEmpty);
    expect(registry.catalogsFor('movie'), isEmpty);

    registry.setNsfwEnabled(true);

    expect(registry.categories, ['movie']);
    expect(registry.catalogsFor('movie'), hasLength(1));
  });

  test('catalog rating overrides an otherwise general extension', () {
    final extension = _FakeExtension(
      ContentRating.general,
      catalogRating: ContentRating.mature,
    );
    final registry = ExtensionRegistry([extension]);

    expect(registry.categories, isEmpty);
    expect(registry.catalogsFor('movie'), isEmpty);
  });
}

class _FakeExtension extends ContentExtension {
  _FakeExtension(ContentRating rating, {ContentRating? catalogRating})
    : _manifest = Manifest.parse({
        'apiVersion': 2,
        'id': 'example',
        'name': 'Example',
        'version': '1.0.0',
        'runtime': 'builtin',
        'contentRating': rating.name,
        'categories': ['movie'],
        'providers': [
          {
            'id': 'example.catalog',
            'roles': ['catalog'],
            'catalogs': [
              {
                'id': 'main',
                'name': 'Main',
                'categories': ['movie'],
                if (catalogRating != null) 'contentRating': catalogRating.name,
              },
            ],
          },
        ],
        'permissions': {'hosts': <String>[]},
      });

  final Manifest _manifest;

  @override
  Manifest get manifest => _manifest;
}
