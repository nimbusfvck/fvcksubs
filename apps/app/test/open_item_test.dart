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
    expect(find.byTooltip('Add to favorites'), findsOneWidget);
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

  testWidgets('protocol v2 detail labels unreleased episodes and hides play', (
    tester,
  ) async {
    const item = SeriesItemV2(
      ref: MediaRef(
        extensionId: 'fake',
        providerId: 'fake.p',
        id: 'series-release',
      ),
      title: 'Release collection',
    );
    const episodeRef = MediaRef(
      extensionId: 'fake',
      providerId: 'fake.p',
      id: 'episode-unreleased',
    );
    final detail = MediaDetailV2(
      item: item,
      episodeGuide: EpisodeGuide(
        groups: [
          EpisodeGroup(
            id: 'season-1',
            title: 'Season 1',
            episodes: [
              EpisodeSummary(
                ref: episodeRef,
                title: 'Coming soon',
                position: 1,
                availableAt: DateTime.now().toUtc().add(
                  const Duration(days: 1),
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

    expect(find.textContaining('Releases'), findsOneWidget);
    expect(find.byIcon(Icons.play_circle_outline), findsNothing);
  });

  testWidgets('protocol v2 detail defaults to the latest season and episode', (
    tester,
  ) async {
    const item = SeriesItemV2(
      ref: MediaRef(
        extensionId: 'fake',
        providerId: 'fake.p',
        id: 'series-latest',
      ),
      title: 'Reacher',
    );
    const detail = MediaDetailV2(
      item: item,
      episodeGuide: EpisodeGuide(
        groups: [
          EpisodeGroup(
            id: 'season-1',
            title: 'Season 1',
            episodes: [
              EpisodeSummary(
                ref: MediaRef(
                  extensionId: 'fake',
                  providerId: 'fake.p',
                  id: 's1e1',
                ),
                title: 'First',
                position: 1,
              ),
            ],
          ),
          EpisodeGroup(
            id: 'season-4',
            title: 'Season 4',
            episodes: [
              EpisodeSummary(
                ref: MediaRef(
                  extensionId: 'fake',
                  providerId: 'fake.p',
                  id: 's4e1',
                ),
                title: 'Fourth first',
                position: 1,
              ),
              EpisodeSummary(
                ref: MediaRef(
                  extensionId: 'fake',
                  providerId: 'fake.p',
                  id: 's4e2',
                ),
                title: 'Fourth latest',
                position: 2,
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

    expect(find.text('Play S4E2'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Fourth latest'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    expect(find.text('Fourth latest'), findsOneWidget);
    expect(find.text('First'), findsNothing);
  });

  testWidgets('protocol v2 header shows year certification and score', (
    tester,
  ) async {
    const item = SeriesItemV2(
      ref: MediaRef(
        extensionId: 'fake',
        providerId: 'fake.p',
        id: 'series-header-meta',
      ),
      title: 'Reacher',
    );
    const detail = MediaDetailV2(
      item: item,
      facts: [
        MediaFact(label: 'Year', value: '2025'),
        MediaFact(label: 'Certification', value: 'TV-MA'),
        MediaFact(label: 'Rating', value: '8.7'),
      ],
    );

    await tester.pumpWidget(
      wrapApp(
        child: const DetailPageV2(item: item),
        registry: ExtensionRegistry([_DetailV2Extension(detail: detail)]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('2025'), findsNWidgets(2));
    expect(find.text('TV-MA'), findsNWidgets(2));
    expect(find.text('8.7'), findsNWidgets(2));
    expect(find.byIcon(Icons.star), findsOneWidget);
  });

  testWidgets('protocol v2 header parses metadata from subtitle', (
    tester,
  ) async {
    const item = SeriesItemV2(
      ref: MediaRef(
        extensionId: 'fake',
        providerId: 'fake.p',
        id: 'series-subtitle-meta',
      ),
      title: 'Reacher',
      subtitle: '2025 • TV-MA • 8.7',
    );
    const detail = MediaDetailV2(item: item);

    await tester.pumpWidget(
      wrapApp(
        child: const DetailPageV2(item: item),
        registry: ExtensionRegistry([_DetailV2Extension(detail: detail)]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('2025'), findsOneWidget);
    expect(find.text('TV-MA'), findsOneWidget);
    expect(find.text('8.7'), findsOneWidget);
    expect(find.text('2025 • TV-MA • 8.7'), findsNothing);
  });

  testWidgets('protocol v2 season selector fits a narrow screen', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(400, 800));

    const item = SeriesItemV2(
      ref: MediaRef(
        extensionId: 'fake',
        providerId: 'fake.p',
        id: 'series-narrow',
      ),
      title: 'Narrow collection',
    );
    const detail = MediaDetailV2(
      item: item,
      episodeGuide: EpisodeGuide(
        groups: [
          EpisodeGroup(
            id: 'season-1',
            title: 'Season 1',
            episodes: [
              EpisodeSummary(
                ref: MediaRef(
                  extensionId: 'fake',
                  providerId: 'fake.p',
                  id: 'narrow-e1',
                ),
                title: 'Episode',
                position: 1,
              ),
            ],
          ),
          EpisodeGroup(
            id: 'season-4',
            title: 'Season 4 with a very long display title',
            episodes: [
              EpisodeSummary(
                ref: MediaRef(
                  extensionId: 'fake',
                  providerId: 'fake.p',
                  id: 'narrow-e2',
                ),
                title: 'Episode',
                position: 1,
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

    expect(tester.takeException(), isNull);
  });
}

class _DetailV2Extension extends FakeExtension {
  _DetailV2Extension({required this.detail});

  final MediaDetailV2 detail;

  @override
  Future<MediaDetailV2> metaV2(MediaRef ref) async => detail;
}
