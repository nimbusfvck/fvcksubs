import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_app/catalog/catalog_cache.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';

void main() {
  const ref = MediaRef(
    extensionId: 'example',
    providerId: 'example.catalog',
    id: 'item',
  );

  VersionedMediaItem item(String id) => VersionedMediaItem(
    item: VideoItemV2(
      ref: MediaRef(
        extensionId: ref.extensionId,
        providerId: ref.providerId,
        id: id,
      ),
      title: id,
    ),
  );

  test('pagination appends items to a section with the same stable id', () {
    final merged = mergeVersionedCatalogPages(
      VersionedCatalogPage(
        sections: [
          CatalogSectionV2(
            id: 'featured',
            title: 'Featured',
            items: [item('one')],
          ),
        ],
        nextPage: 'cursor',
      ),
      VersionedCatalogPage(
        sections: [
          CatalogSectionV2(id: 'featured', items: [item('two')]),
        ],
      ),
    );

    expect(merged.sections, hasLength(1));
    expect(merged.sections.single.items.map((entry) => entry.item.ref.id), [
      'one',
      'two',
    ]);
    expect(merged.sections.single.title, 'Featured');
    expect(merged.nextPage, isNull);
  });

  test('pagination preserves order when a new section appears', () {
    final merged = mergeVersionedCatalogPages(
      VersionedCatalogPage(
        sections: [
          CatalogSectionV2(id: 'first', items: [item('one')]),
        ],
        subCategories: const [SubCategory(id: 'all', name: 'All')],
      ),
      VersionedCatalogPage(
        sections: [
          CatalogSectionV2(id: 'second', items: [item('two')]),
        ],
      ),
    );

    expect(merged.sections.map((section) => section.id), ['first', 'second']);
    expect(merged.subCategories.single.id, 'all');
  });
}
