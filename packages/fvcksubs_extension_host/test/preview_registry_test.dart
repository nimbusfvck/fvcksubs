@TestOn('vm')
library;

import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';
import 'package:test/test.dart';

/// `ExtensionRegistry.previewCatalogs()`/`preview()` — discovery and routing
/// for the Shorts feed, kept separate from ordinary category-based browsing.
void main() {
  Manifest manifestWith(
    String id, {
    required List<CatalogSurface> surfaces,
    ContentRating contentRating = ContentRating.unknown,
  }) => Manifest.parse({
    'apiVersion': 2,
    'id': id,
    'name': id,
    'version': '1.0.0',
    'runtime': 'builtin',
    'categories': ['movie'],
    'contentRating': contentRating.name,
    'providers': [
      {
        'id': '$id.p',
        'roles': ['catalog'],
        'catalogs': [
          for (final (index, surface) in surfaces.indexed)
            {
              'id': 'catalog-$index',
              'name': 'Catalog $index',
              'categories': surface == CatalogSurface.browse ? ['movie'] : <String>[],
              'surface': surface.name,
            },
        ],
      },
    ],
    'permissions': {'hosts': <String>[]},
  });

  test('only preview-surface catalogs are returned', () {
    final registry = ExtensionRegistry([
      _Stub(manifestWith('a', surfaces: [CatalogSurface.browse])),
      _Stub(manifestWith('b', surfaces: [CatalogSurface.preview])),
      _Stub(
        manifestWith('c', surfaces: [CatalogSurface.browse, CatalogSurface.preview]),
      ),
    ]);

    final bindings = registry.previewCatalogs();

    expect(bindings.map((b) => b.extensionId), ['b', 'c']);
    expect(bindings.every((b) => b.isPreviewSurface), isTrue);
  });

  test('a disabled extension contributes no preview catalogs', () {
    final registry = ExtensionRegistry([
      _Stub(manifestWith('a', surfaces: [CatalogSurface.preview])),
    ], disabledExtensionIds: {'a'});

    expect(registry.previewCatalogs(), isEmpty);
  });

  test('a mature preview catalog stays hidden until NSFW is on', () {
    ExtensionRegistry registryWith({required bool showNsfw}) => ExtensionRegistry(
      [_Stub(manifestWith('a', surfaces: [CatalogSurface.preview], contentRating: ContentRating.mature))],
      showNsfw: showNsfw,
    );

    expect(registryWith(showNsfw: false).previewCatalogs(), isEmpty);
    expect(registryWith(showNsfw: true).previewCatalogs(), hasLength(1));
  });

  test('preview() routes to the owning extension', () async {
    final stub = _Stub(manifestWith('a', surfaces: [CatalogSurface.preview]));
    stub.previewToReturn = const PreviewResponse(
      sources: [EmbeddedPreviewSource(id: 'yt:1', provider: 'youtube', mediaId: '1')],
    );
    final registry = ExtensionRegistry([stub]);
    final item = _item('a');

    final response = await registry.preview(item.ref, item);

    expect(response.sources, hasLength(1));
  });

  test('preview() on a disabled extension returns empty, not a throw', () async {
    final stub = _Stub(manifestWith('a', surfaces: [CatalogSurface.preview]));
    stub.previewToReturn = const PreviewResponse(
      sources: [EmbeddedPreviewSource(id: 'yt:1', provider: 'youtube', mediaId: '1')],
    );
    final registry = ExtensionRegistry([stub], disabledExtensionIds: {'a'});
    final item = _item('a');

    final response = await registry.preview(item.ref, item);

    expect(response.sources, isEmpty);
  });

  test('preview() on an extension that does not implement it returns empty', () async {
    final stub = _Stub(manifestWith('a', surfaces: [CatalogSurface.browse]));
    final registry = ExtensionRegistry([stub]);
    final item = _item('a');

    final response = await registry.preview(item.ref, item);

    expect(response.sources, isEmpty);
  });
}

VideoItemV2 _item(String extensionId) => VideoItemV2(
  ref: MediaRef(extensionId: extensionId, providerId: '$extensionId.p', id: 'item-1'),
  title: 'Some Movie',
);

/// A [ContentExtension] whose `preview` either returns [previewToReturn] or,
/// left `null`, falls through to the default `UnsupportedError` — matching a
/// real extension that never implemented the role.
class _Stub extends ContentExtension {
  _Stub(this.manifest);

  @override
  final Manifest manifest;

  PreviewResponse? previewToReturn;

  @override
  Future<PreviewResponse> preview(MediaItemV2 item) {
    final response = previewToReturn;
    if (response == null) return super.preview(item);
    return Future.value(response);
  }
}
