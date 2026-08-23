import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:test/test.dart';

void main() {
  test('manifest rating is inherited by an unclassified catalog', () {
    final manifest = Manifest.parse(_manifestJson());
    final catalog = manifest.providers.single.catalogs.single;

    expect(manifest.contentRating, ContentRating.mature);
    expect(catalog.contentRating, isNull);
  });

  test('catalog rating overrides the manifest rating', () {
    final json = _manifestJson()
      ..['providers'] = [
        {
          'id': 'example.catalog',
          'roles': ['catalog'],
          'catalogs': [
            {
              'id': 'general',
              'name': 'General',
              'categories': ['movie'],
              'contentRating': 'general',
            },
          ],
        },
      ];
    final manifest = Manifest.parse(json);

    expect(
      manifest.providers.single.catalogs.single.contentRating,
      ContentRating.general,
    );
  });

  test('unknown ratings stay backward compatible in JSON', () {
    final manifest = Manifest.parse(_manifestJson()..remove('contentRating'));
    expect(manifest.contentRating, ContentRating.unknown);
    expect(manifest.toJson().containsKey('contentRating'), isFalse);
  });
}

Map<String, Object?> _manifestJson() => {
  'apiVersion': 2,
  'id': 'example',
  'name': 'Example',
  'version': '1.0.0',
  'runtime': 'builtin',
  'contentRating': 'mature',
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
        },
      ],
    },
  ],
  'permissions': {'hosts': <String>[]},
};
