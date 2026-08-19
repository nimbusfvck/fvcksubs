import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_app/catalog/media_grid_v2.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';

void main() {
  VersionedMediaItem item(String id) => VersionedMediaItem(
    item: VideoItemV2(
      ref: MediaRef(
        extensionId: 'example',
        providerId: 'example.catalog',
        id: id,
      ),
      title: id,
    ),
  );

  testWidgets('renders explicit section headings and routes the envelope', (
    tester,
  ) async {
    VersionedMediaItem? tapped;
    final first = item('First');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaGridV2(
            sections: [
              CatalogSectionV2(
                id: 'featured',
                title: 'Featured',
                items: [first, item('Second')],
              ),
            ],
            showSectionHeaders: true,
            onTap: (value) => tapped = value,
          ),
        ),
      ),
    );

    expect(find.text('Featured'), findsOneWidget);
    expect(find.text('First'), findsOneWidget);
    await tester.tap(find.text('First'));
    expect(tapped, same(first));
  });
}
