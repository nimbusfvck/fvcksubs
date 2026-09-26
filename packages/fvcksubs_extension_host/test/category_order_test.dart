import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';
import 'package:test/test.dart';

void main() {
  test('Home categories use the stable built-in order', () {
    final extension = _StubExtension(
      categories: const ['all', 'sport', 'movie', 'tv', 'anime', 'live'],
    );

    expect(ExtensionRegistry([extension]).categories, [
      'all',
      'live',
      'sport',
      'movie',
      'tv',
      'anime',
    ]);
  });
}

class _StubExtension extends ContentExtension {
  _StubExtension({required List<String> categories})
    : _manifest = Manifest.parse({
        'apiVersion': 2,
        'id': 'category-order',
        'name': 'Category Order',
        'version': '1.0.0',
        'runtime': 'builtin',
        'categories': categories,
        'providers': [
          {
            'id': 'category-order.catalog',
            'roles': ['catalog'],
            'catalogs': [
              {
                'id': 'main',
                'name': 'Main',
                'categories': categories,
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
