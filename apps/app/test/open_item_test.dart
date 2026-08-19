import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_app/detail/detail_page.dart';
import 'package:fvcksubs_app/detail/open_item.dart';
import 'package:fvcksubs_app/detail/detail_page_v2.dart';
import 'package:fvcksubs_app/detail/open_versioned_item.dart';
import 'package:fvcksubs_app/player/player_page.dart';
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';

import 'support/harness.dart';

/// `openItem` is the one place every tap handler (Home shelves, Discover,
/// a catalog page, Library) routes through — this proves the split itself,
/// not any one call site.
void main() {
  testWidgets(
    'a movie/series item opens DetailPage, and stays there until Play',
    (tester) async {
      final item = fakeItem(
        poster: const ImageRef('https://cdn.example/x.jpg'),
      );
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
    },
  );

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

  testWidgets('protocol v2 series opens its native detail page', (
    tester,
  ) async {
    const item = SeriesItemV2(
      ref: MediaRef(extensionId: 'fake', providerId: 'fake.p', id: 'series'),
      title: 'Example collection',
    );
    final registry = ExtensionRegistry([
      _DetailV2Extension(detail: const MediaDetailV2(item: item)),
    ]);

    await tester.pumpWidget(
      wrapApp(
        child: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => openVersionedItem(
              context,
              const VersionedMediaItem(item: item),
            ),
            child: const Text('open v2'),
          ),
        ),
        registry: registry,
      ),
    );
    await tester.tap(find.text('open v2'));
    await tester.pumpAndSettle();

    expect(find.byType(DetailPageV2), findsOneWidget);
    expect(find.text('Example collection'), findsOneWidget);
    expect(find.text('Add to favorites'), findsOneWidget);
  });

  testWidgets('protocol v2 detail renders credit and episode artwork', (
    tester,
  ) async {
    const item = SeriesItemV2(
      ref: MediaRef(
        extensionId: 'fake',
        providerId: 'fake.p',
        id: 'series-artwork',
      ),
      title: 'Artwork collection',
    );
    const episodeRef = MediaRef(
      extensionId: 'fake',
      providerId: 'fake.p',
      id: 'episode-7',
    );
    const detail = MediaDetailV2(
      item: item,
      credits: [
        MediaCredit(
          name: 'Example Person',
          image: ImageRef('https://cdn.example/person.jpg'),
        ),
      ],
      episodeGuide: EpisodeGuide(
        groups: [
          EpisodeGroup(
            id: 'group',
            title: 'Group',
            episodes: [
              EpisodeSummary(
                ref: episodeRef,
                title: 'Seventh entry',
                position: 7,
                artwork: Artwork(
                  landscape: ImageRef('https://cdn.example/episode.jpg'),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      wrapApp(
        child: const DetailPageV2(item: item),
        registry: ExtensionRegistry([_DetailV2Extension(detail: detail)]),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Episode 7'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();

    expect(find.text('Example Person'), findsOneWidget);
    expect(find.text('Episode 7'), findsOneWidget);
    expect(find.text('Seventh entry'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is CachedNetworkImage &&
            widget.imageUrl == 'https://cdn.example/person.jpg',
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is CachedNetworkImage &&
            widget.imageUrl == 'https://cdn.example/episode.jpg',
      ),
      findsOneWidget,
    );
  });
}

class _DetailV2Extension extends FakeExtension {
  _DetailV2Extension({required this.detail});

  final MediaDetailV2 detail;

  @override
  Future<MediaDetailV2> metaV2(MediaRef ref) async => detail;
}
