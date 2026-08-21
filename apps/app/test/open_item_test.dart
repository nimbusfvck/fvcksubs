import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_app/catalog/media_card_v2.dart';
import 'package:fvcksubs_app/detail/detail_page.dart';
import 'package:fvcksubs_app/detail/open_item.dart';
import 'package:fvcksubs_app/detail/detail_page_v2.dart';
import 'package:fvcksubs_app/detail/open_versioned_item.dart';
import 'package:fvcksubs_app/library/library_controller.dart';
import 'package:fvcksubs_app/player/player_page.dart';
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';
import 'package:fvcksubs_storage/fvcksubs_storage.dart';

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

  testWidgets('protocol v2 video opens its native detail page', (tester) async {
    const item = VideoItemV2(
      ref: MediaRef(extensionId: 'fake', providerId: 'fake.p', id: 'video'),
      title: 'Example movie',
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
            child: const Text('open video'),
          ),
        ),
        registry: registry,
      ),
    );
    await tester.tap(find.text('open video'));
    await tester.pumpAndSettle();

    expect(find.byType(DetailPageV2), findsOneWidget);
    expect(find.byType(PlayerPage), findsNothing);
  });

  testWidgets('protocol v2 series resumes the last watched episode', (
    tester,
  ) async {
    const series = SeriesItemV2(
      ref: MediaRef(extensionId: 'fake', providerId: 'fake.p', id: 'series'),
      title: 'Resume series',
    );
    const episodeRef = MediaRef(
      extensionId: 'fake',
      providerId: 'fake.p',
      id: 'episode-3',
    );
    const watchedEpisode = EpisodeItemV2(
      ref: episodeRef,
      title: 'Episode 3',
      episode: EpisodeIdentity(
        parentRef: MediaRef(
          extensionId: 'fake',
          providerId: 'fake.p',
          id: 'series',
        ),
        groupId: 'season-2',
        position: 3,
      ),
    );
    const record = UserMediaState(
      item: watchedEpisode,
      progress: Duration(minutes: 12),
      duration: Duration(minutes: 24),
    );
    const detail = MediaDetailV2(
      item: series,
      episodeGuide: EpisodeGuide(
        groups: [
          EpisodeGroup(
            id: 'season-2',
            title: 'Season 2',
            episodes: [
              EpisodeSummary(ref: episodeRef, title: 'Episode 3', position: 3),
            ],
          ),
        ],
      ),
    );
    final libraryController = LibraryController(
      store: _MemoryLibraryStoreV2(),
      initial: {record.key: record},
    );

    await tester.pumpWidget(
      wrapApp(
        child: const DetailPageV2(item: series),
        registry: ExtensionRegistry([_DetailV2Extension(detail: detail)]),
        libraryController: libraryController,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Continue S2E3'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('protocol v2 movie with progress offers to continue watching', (
    tester,
  ) async {
    const item = VideoItemV2(
      ref: MediaRef(extensionId: 'fake', providerId: 'fake.p', id: 'movie'),
      title: 'Resume movie',
    );
    const record = UserMediaState(
      item: item,
      progress: Duration(minutes: 20),
      duration: Duration(minutes: 40),
    );
    final libraryController = LibraryController(
      store: _MemoryLibraryStoreV2(),
      initial: {record.key: record},
    );

    await tester.pumpWidget(
      wrapApp(
        child: const DetailPageV2(item: item),
        registry: ExtensionRegistry([
          _DetailV2Extension(detail: const MediaDetailV2(item: item)),
        ]),
        libraryController: libraryController,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Continue Watching'), findsOneWidget);
    expect(find.text('Play'), findsNothing);
    expect(find.byType(FilledButton), findsOneWidget);
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
    final playButton = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(find.text('Coming soon'), findsNWidgets(2));
    expect(playButton.onPressed, isNull);
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

  testWidgets('protocol v2 detail renders facts without interpreting them', (
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
        MediaFact(label: 'Runtime', value: '50 minutes'),
      ],
    );

    await tester.pumpWidget(
      wrapApp(
        child: const DetailPageV2(item: item),
        registry: ExtensionRegistry([_DetailV2Extension(detail: detail)]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Year'), findsOneWidget);
    expect(find.text('2025'), findsOneWidget);
    expect(find.text('Certification'), findsOneWidget);
    expect(find.text('TV-MA'), findsOneWidget);
    expect(find.text('Rating'), findsOneWidget);
    expect(find.text('8.7'), findsOneWidget);
    expect(find.text('Runtime'), findsOneWidget);
    expect(find.text('50 minutes'), findsOneWidget);
  });

  testWidgets(
    'protocol v2 header displays structured metadata with a rating icon',
    (tester) async {
      const item = SeriesItemV2(
        ref: MediaRef(
          extensionId: 'fake',
          providerId: 'fake.p',
          id: 'series-subtitle-meta',
        ),
        title: 'Reacher',
        subtitle: 'Drama',
        releaseYear: 2025,
        rating: 8.76,
        artwork: Artwork(
          portrait: ImageRef('https://cdn.example/reacher-poster.jpg'),
        ),
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
      expect(find.text('-'), findsOneWidget);
      expect(find.byIcon(Icons.star_rounded), findsOneWidget);
      expect(find.text('8.8'), findsOneWidget);
      expect(find.text('Drama'), findsOneWidget);
      expect(find.byType(Hero), findsOneWidget);
    },
  );

  testWidgets('protocol v2 detail renders trailer actions', (tester) async {
    const item = VideoItemV2(
      ref: MediaRef(
        extensionId: 'fake',
        providerId: 'fake.p',
        id: 'video-trailer',
      ),
      title: 'Example movie',
    );
    const detail = MediaDetailV2(
      item: item,
      trailers: [
        MediaTrailer(
          title: 'Official Trailer',
          url: 'https://www.youtube.com/watch?v=example',
          site: 'YouTube',
          thumbnail: ImageRef(
            'https://img.youtube.com/vi/example/mqdefault.jpg',
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      wrapApp(
        child: const DetailPageV2(item: item),
        registry: ExtensionRegistry([_DetailV2Extension(detail: detail)]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Official Trailer'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is CachedNetworkImage &&
            widget.imageUrl ==
                'https://img.youtube.com/vi/example/mqdefault.jpg',
      ),
      findsOneWidget,
    );
  });

  testWidgets('protocol v2 detail renders recommendations at the bottom', (
    tester,
  ) async {
    const item = VideoItemV2(
      ref: MediaRef(
        extensionId: 'fake',
        providerId: 'fake.p',
        id: 'video-recommendations',
      ),
      title: 'Example movie',
    );
    const recommendation = VideoItemV2(
      ref: MediaRef(
        extensionId: 'fake',
        providerId: 'fake.p',
        id: 'related-video',
      ),
      title: 'Related movie',
      artwork: Artwork(portrait: ImageRef('https://cdn.example/related.jpg')),
    );
    const detail = MediaDetailV2(item: item, recommendations: [recommendation]);

    await tester.pumpWidget(
      wrapApp(
        child: const DetailPageV2(item: item),
        registry: ExtensionRegistry([_DetailV2Extension(detail: detail)]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Similar'), findsOneWidget);
    expect(find.text('Related movie'), findsOneWidget);
    expect(find.byType(MediaCardV2), findsOneWidget);
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

class _MemoryLibraryStoreV2 implements LibraryStore {
  @override
  Future<Map<String, UserMediaState>> load() async => {};

  @override
  Future<void> save(Map<String, UserMediaState> records) async {}
}
