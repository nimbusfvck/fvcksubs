import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_app/detail/detail_page.dart';
import 'package:fvcksubs_app/detail/open_item.dart';
import 'package:fvcksubs_app/player/player_page.dart';
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';

import 'support/harness.dart';

/// `openItem` is the one place every tap handler (Home shelves, Discover,
/// a catalog page, Library) routes through — this proves the split itself,
/// not any one call site.
void main() {
  testWidgets('a movie/series item opens DetailPage, and stays there until Play', (
    tester,
  ) async {
    final item = fakeItem(poster: const ImageRef('https://cdn.example/x.jpg'));
    final registry = ExtensionRegistry([
      FakeExtension(metaDetail: MediaDetail(item: item)),
    ]);

    await tester.pumpWidget(
      wrapApp(
        child: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => openItem(context, item),
            child: const Text('open'),
          ),
        ),
        registry: registry,
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byType(DetailPage), findsOneWidget);
    expect(find.byType(PlayerPage), findsNothing);
  });

  testWidgets(
    'a live/channel item skips DetailPage, going straight through to the player',
    (tester) async {
      // The resolve happens under an overlay, not on a page of its own — so
      // the proof this routing works is where the viewer actually lands:
      // PlayerPage, with DetailPage never shown at all.
      final item = fakeItem();
      final registry = ExtensionRegistry([
        FakeExtension(
          sourceList: const [StreamSource(id: 's', label: 'HD 1080p')],
          resolved: const PlayableStream(
            url: 'https://edge/live.m3u8',
            format: StreamFormat.hls,
          ),
        ),
      ]);

      await tester.pumpWidget(
        wrapApp(
          child: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => openItem(context, item),
              child: const Text('open'),
            ),
          ),
          registry: registry,
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.byType(PlayerPage), findsOneWidget);
      expect(find.byType(DetailPage), findsNothing);
    },
  );
}
