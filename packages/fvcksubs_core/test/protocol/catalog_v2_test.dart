import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:test/test.dart';

void main() {
  const ref = MediaRef(
    extensionId: 'example',
    providerId: 'example.catalog',
    id: 'item',
  );

  test('v1 contiguous groups become explicit sections', () {
    final page = VersionedCatalogPage.fromV1(
      const CatalogPage(
        items: [
          MediaItem(
            ref: ref,
            kind: MediaKind.movie,
            title: 'First',
            group: 'Featured',
          ),
          MediaItem(
            ref: MediaRef(
              extensionId: 'example',
              providerId: 'example.catalog',
              id: 'item-2',
            ),
            kind: MediaKind.movie,
            title: 'Second',
            group: 'Featured',
          ),
          MediaItem(
            ref: MediaRef(
              extensionId: 'example',
              providerId: 'example.catalog',
              id: 'item-3',
            ),
            kind: MediaKind.movie,
            title: 'Third',
          ),
        ],
        nextPage: 'cursor',
      ),
    );

    expect(page.sections, hasLength(2));
    expect(page.sections.first.title, 'Featured');
    expect(page.sections.first.items, hasLength(2));
    expect(page.sections.last.title, isNull);
    expect(page.items, hasLength(3));
    expect(page.nextPage, 'cursor');
  });

  test('v2 page decodes strict sections and items', () {
    final page = VersionedCatalogPage.fromProtocolJson({
      'sections': [
        {
          'id': 'featured',
          'title': 'Featured',
          'items': [
            {'ref': ref.toJson(), 'kind': 'video', 'title': 'A video'},
          ],
        },
      ],
      'subCategories': [
        {'id': 'new', 'name': 'New'},
      ],
    }, apiVersion: 2);

    expect(page.sections.single.id, 'featured');
    expect(page.items.single.item, isA<VideoItemV2>());
    expect(page.items.single.requiresLegacyRequest, isFalse);
    expect(page.subCategories.single.id, 'new');
    expect(
      VersionedCatalogPage.fromProtocolJson(page.toJson(), apiVersion: 2),
      page,
    );
  });

  test('v2 page rejects the v1 flat items shape', () {
    expect(
      () => VersionedCatalogPage.fromProtocolJson({
        'items': [
          {'ref': ref.toJson(), 'kind': 'video', 'title': 'A video'},
        ],
      }, apiVersion: 2),
      throwsFormatException,
    );
  });
}
