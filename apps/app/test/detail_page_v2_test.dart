import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_app/detail/detail_page_v2.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';

import 'support/harness.dart';

void main() {
  testWidgets(
    'catalog video without metadata still opens a playable detail page',
    (tester) async {
      const item = VideoItemV2(
        ref: MediaRef(
          extensionId: 'fake',
          providerId: 'fake.p',
          id: 'catalog-item',
        ),
        title: 'Catalog item',
      );

      await tester.pumpWidget(
        wrapApp(
          child: const DetailPageV2(item: item),
          registry: ExtensionRegistry([FakeExtension()]),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Could not load details.'), findsNothing);
      expect(find.text('Catalog item'), findsWidgets);
      expect(find.widgetWithText(FilledButton, 'Play'), findsOneWidget);
    },
  );
}
