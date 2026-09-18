import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_app/detail/detail_page_v2.dart';
import 'package:fvcksubs_app/library/library_controller.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';
import 'package:fvcksubs_storage/fvcksubs_storage.dart';

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
        overview: 'A catalog synopsis',
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
      expect(find.text('A catalog synopsis'), findsOneWidget);
      final watchButton = find.widgetWithText(FilledButton, 'Watch Now');
      expect(watchButton, findsOneWidget);
      expect(
        tester.getBottomLeft(find.text('A catalog synopsis')).dy,
        greaterThan(tester.getBottomLeft(watchButton).dy),
      );
    },
  );

  testWidgets('expanded description does not keep a collapse button', (
    tester,
  ) async {
    const item = VideoItemV2(
      ref: MediaRef(
        extensionId: 'fake',
        providerId: 'fake.p',
        id: 'expanded-description',
      ),
      title: 'Expanded description',
    );
    const detail = MediaDetailV2(
      item: item,
      description:
          'A long synopsis that continues beyond the compact hero preview. '
          'The complete description should remain visible after expanding it.',
    );

    await tester.pumpWidget(
      wrapApp(
        child: const DetailPageV2(item: item),
        registry: ExtensionRegistry([FakeExtension(metaDetail: detail)]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Read More'), findsOneWidget);
    await tester.tap(find.text('Read More'));
    await tester.pumpAndSettle();

    expect(find.text('Read More'), findsNothing);
    expect(find.text('Show Less'), findsNothing);
  });

  testWidgets('back button stays visible after the detail hero scrolls away', (
    tester,
  ) async {
    const item = VideoItemV2(
      ref: MediaRef(
        extensionId: 'fake',
        providerId: 'fake.p',
        id: 'scrollable-detail',
      ),
      title: 'Scrollable detail',
    );

    await tester.pumpWidget(
      wrapApp(
        child: const DetailPageV2(item: item),
        registry: ExtensionRegistry([FakeExtension()]),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -800));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Back'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'an unreleased movie still shows Watch Now without release metadata',
    (tester) async {
      final item = VideoItemV2(
        ref: const MediaRef(
          extensionId: 'fake',
          providerId: 'fake.p',
          id: 'unreleased-movie',
        ),
        title: 'Unreleased Movie',
        releaseDate: DateTime.utc(2099, 1, 15),
      );
      final library = LibraryController(store: _MemoryLibraryStore());

      await tester.pumpWidget(
        wrapApp(
          child: DetailPageV2(item: item),
          registry: ExtensionRegistry([FakeExtension()]),
          libraryController: library,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.widgetWithText(FilledButton, 'Watch Now'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Remind Me'), findsNothing);
      expect(find.textContaining('Releases'), findsNothing);
    },
  );

  testWidgets('renders a movie collection above recommendations', (
    tester,
  ) async {
    const movie = VideoItemV2(
      ref: MediaRef(extensionId: 'fake', providerId: 'fake.p', id: 'movie'),
      title: 'Movie',
    );
    const collectionItem = VideoItemV2(
      ref: MediaRef(
        extensionId: 'fake',
        providerId: 'fake.p',
        id: 'collection-movie',
      ),
      title: 'Collection Movie',
    );
    const recommendation = VideoItemV2(
      ref: MediaRef(
        extensionId: 'fake',
        providerId: 'fake.p',
        id: 'recommendation',
      ),
      title: 'Recommendation',
    );
    const detail = MediaDetailV2(
      item: movie,
      collection: MediaCollectionV2(
        id: 'collection',
        name: 'Example Collection',
        items: [collectionItem],
      ),
      recommendations: [recommendation],
    );

    await tester.pumpWidget(
      wrapApp(
        child: const DetailPageV2(item: movie),
        registry: ExtensionRegistry([FakeExtension(metaDetail: detail)]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Example Collection'), findsOneWidget);
    expect(find.text('You Might Also Like'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Example Collection')).dy,
      lessThan(tester.getTopLeft(find.text('You Might Also Like')).dy),
    );
  });

  testWidgets('selects the season containing the latest watched episode', (
    tester,
  ) async {
    const seriesRef = MediaRef(
      extensionId: 'fake',
      providerId: 'fake.p',
      id: 'series',
    );
    const seasonOneEpisode = MediaRef(
      extensionId: 'fake',
      providerId: 'fake.p',
      id: 's1e1',
    );
    const seasonTwoEpisode = MediaRef(
      extensionId: 'fake',
      providerId: 'fake.p',
      id: 's2e2',
    );
    const series = SeriesItemV2(ref: seriesRef, title: 'Example Series');
    const detail = MediaDetailV2(
      item: series,
      episodeGuide: EpisodeGuide(
        groups: [
          EpisodeGroup(
            id: 'season-1',
            title: 'Season 1',
            episodes: [
              EpisodeSummary(
                ref: seasonOneEpisode,
                title: 'Episode 1',
                position: 1,
              ),
            ],
          ),
          EpisodeGroup(
            id: 'season-2',
            title: 'Season 2',
            episodes: [
              EpisodeSummary(
                ref: seasonTwoEpisode,
                title: 'Episode 2',
                position: 2,
              ),
            ],
          ),
        ],
      ),
    );
    const watchedEpisode = EpisodeItemV2(
      ref: seasonTwoEpisode,
      title: 'Episode 2',
      subtitle: 'Example Series',
      episode: EpisodeIdentity(
        parentRef: seriesRef,
        groupId: 'season-2',
        position: 2,
      ),
    );
    final library = LibraryController(
      store: _MemoryLibraryStore(),
      initial: {
        UserMediaState.keyFor(seasonTwoEpisode): UserMediaState(
          item: watchedEpisode,
          progress: const Duration(minutes: 4),
          lastWatched: DateTime.utc(2026, 8, 23),
        ),
      },
    );

    await tester.pumpWidget(
      wrapApp(
        child: const DetailPageV2(item: series),
        registry: ExtensionRegistry([FakeExtension(metaDetail: detail)]),
        libraryController: library,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Season 2'), findsOneWidget);
    // Once, not twice: the guide gave no episode name beyond the position, so
    // the tile prints the number instead of printing it above itself.
    expect(find.text('Episode 2'), findsOneWidget);
    expect(find.text('Episode 1'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Continue S2E2'), findsOneWidget);
  });

  testWidgets('an unseasoned group still names the episode on Play', (
    tester,
  ) async {
    // An anime cour is one group called "Episodes". The button used to fall
    // back to a bare "Continue", dropping the only detail it should carry.
    const seriesRef = MediaRef(
      extensionId: 'fake',
      providerId: 'fake.p',
      id: 'cour',
    );
    const episodeRef = MediaRef(
      extensionId: 'fake',
      providerId: 'fake.p',
      id: 'cour-e5',
    );
    const series = SeriesItemV2(ref: seriesRef, title: 'A Cour');
    const detail = MediaDetailV2(
      item: series,
      episodeGuide: EpisodeGuide(
        groups: [
          EpisodeGroup(
            id: 'season:1',
            title: 'Episodes',
            episodes: [
              EpisodeSummary(ref: episodeRef, title: 'Episode 5', position: 5),
            ],
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      wrapApp(
        child: const DetailPageV2(item: series),
        registry: ExtensionRegistry([FakeExtension(metaDetail: detail)]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FilledButton, 'Watch E5'), findsOneWidget);
  });

  testWidgets('loads a lazy episode group without an async setState error', (
    tester,
  ) async {
    const seriesRef = MediaRef(
      extensionId: 'fake',
      providerId: 'fake.p',
      id: 'lazy-series',
    );
    const episodeRef = MediaRef(
      extensionId: 'fake',
      providerId: 'fake.p',
      id: 'lazy-e1',
    );
    const series = SeriesItemV2(ref: seriesRef, title: 'Lazy Series');
    const placeholder = MediaDetailV2(
      item: series,
      episodeGuide: EpisodeGuide(
        groups: [
          EpisodeGroup(
            id: 'season:1',
            title: 'Season 1',
            episodes: [],
            loaded: false,
          ),
        ],
      ),
    );
    const loaded = MediaDetailV2(
      item: series,
      episodeGuide: EpisodeGuide(
        groups: [
          EpisodeGroup(
            id: 'season:1',
            title: 'Season 1',
            episodes: [
              EpisodeSummary(ref: episodeRef, title: 'Episode 1', position: 1),
            ],
            loaded: true,
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      wrapApp(
        child: const DetailPageV2(item: series),
        registry: ExtensionRegistry([
          FakeExtension(
            metaForGroup: (groupId) => groupId == null ? placeholder : loaded,
          ),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Episode 1'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('lazy groups keep Continue on the watched season', (
    tester,
  ) async {
    const seriesRef = MediaRef(
      extensionId: 'fake',
      providerId: 'fake.p',
      id: 'lazy-resume-series',
    );
    const watchedRef = MediaRef(
      extensionId: 'fake',
      providerId: 'fake.p',
      id: 'lazy-s1e4',
    );
    const series = SeriesItemV2(ref: seriesRef, title: 'Lazy Resume');
    const placeholder = MediaDetailV2(
      item: series,
      episodeGuide: EpisodeGuide(
        groups: [
          EpisodeGroup(
            id: 'season:1',
            title: 'Season 1',
            episodes: [],
            loaded: false,
          ),
          EpisodeGroup(
            id: 'season:2',
            title: 'Season 2',
            episodes: [],
            loaded: false,
          ),
        ],
      ),
    );
    const loadedSeasonOne = MediaDetailV2(
      item: series,
      episodeGuide: EpisodeGuide(
        groups: [
          EpisodeGroup(
            id: 'season:1',
            title: 'Season 1',
            episodes: [
              EpisodeSummary(ref: watchedRef, title: 'Episode 4', position: 4),
            ],
            loaded: true,
          ),
        ],
      ),
    );
    const loadedSeasonTwo = MediaDetailV2(
      item: series,
      episodeGuide: EpisodeGuide(
        groups: [
          EpisodeGroup(
            id: 'season:2',
            title: 'Season 2',
            episodes: [
              EpisodeSummary(
                ref: MediaRef(
                  extensionId: 'fake',
                  providerId: 'fake.p',
                  id: 'lazy-s2e1',
                ),
                title: 'Episode 1',
                position: 1,
              ),
            ],
            loaded: true,
          ),
        ],
      ),
    );
    final watched = EpisodeItemV2(
      ref: watchedRef,
      title: 'Episode 4',
      subtitle: 'Lazy Resume',
      episode: const EpisodeIdentity(
        parentRef: seriesRef,
        groupId: 'season:1',
        position: 4,
      ),
    );
    final library = LibraryController(
      store: _MemoryLibraryStore(),
      initial: {
        UserMediaState.keyFor(watchedRef): UserMediaState(
          item: watched,
          progress: const Duration(minutes: 3),
          lastWatched: DateTime.utc(2026, 9, 15),
        ),
      },
    );

    await tester.pumpWidget(
      wrapApp(
        child: const DetailPageV2(item: series),
        registry: ExtensionRegistry([
          FakeExtension(
            metaForGroup: (groupId) {
              if (groupId == null) return placeholder;
              return groupId == 'season:1' ? loadedSeasonOne : loadedSeasonTwo;
            },
          ),
        ]),
        libraryController: library,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Season 1'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Continue S1E4'), findsOneWidget);
    expect(find.text('Episode 4'), findsWidgets);
  });

  group('a group too long to scroll', () {
    const seriesRef = MediaRef(
      extensionId: 'fake',
      providerId: 'fake.p',
      id: 'long-series',
    );
    const series = SeriesItemV2(ref: seriesRef, title: 'Long Runner');

    MediaRef episodeRef(int position) =>
        MediaRef(extensionId: 'fake', providerId: 'fake.p', id: 'e$position');

    MediaDetailV2 detailWith(int episodes) => MediaDetailV2(
      item: series,
      episodeGuide: EpisodeGuide(
        groups: [
          EpisodeGroup(
            id: 'season:1',
            title: 'Episodes',
            episodes: [
              for (var position = 1; position <= episodes; position++)
                EpisodeSummary(
                  ref: episodeRef(position),
                  title: 'Episode $position',
                  position: position,
                ),
            ],
          ),
        ],
      ),
    );

    Future<void> open(
      WidgetTester tester,
      MediaDetailV2 detail, {
      LibraryController? library,
    }) async {
      await tester.pumpWidget(
        wrapApp(
          child: const DetailPageV2(item: series),
          registry: ExtensionRegistry([FakeExtension(metaDetail: detail)]),
          libraryController: library,
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('is split into ranges of a hundred', (tester) async {
      await open(tester, detailWith(250));

      expect(find.text('1–100'), findsOneWidget);
      expect(find.text('101–200'), findsOneWidget);
      expect(find.text('201–250'), findsOneWidget);

      // Only the selected range is built. Episode tiles are built eagerly, so
      // this bounds the work as much as the scrolling. Nothing is watched, so
      // the range shown is the one Play would start from — the newest.
      expect(find.text('Episode 250'), findsWidgets);
      expect(find.text('Episode 200'), findsNothing);
    });

    testWidgets('opens on the range holding what Play would resume', (
      tester,
    ) async {
      final library = LibraryController(
        store: _MemoryLibraryStore(),
        initial: {
          UserMediaState.keyFor(episodeRef(150)): UserMediaState(
            item: EpisodeItemV2(
              ref: episodeRef(150),
              title: 'Episode 150',
              subtitle: 'Long Runner',
              episode: const EpisodeIdentity(
                parentRef: seriesRef,
                groupId: 'season:1',
                position: 150,
              ),
            ),
            progress: const Duration(minutes: 4),
            lastWatched: DateTime.utc(2026, 8, 23),
          ),
        },
      );

      await open(tester, detailWith(250), library: library);

      // Resuming episode 150 must not begin with a scroll from episode 1.
      expect(find.text('Episode 150'), findsWidgets);
      expect(find.text('Episode 1'), findsNothing);
    });

    testWidgets('switches range when a chip is tapped', (tester) async {
      await open(tester, detailWith(250));

      final firstRange = find.text('1–100');
      await tester.drag(
        find.byType(CustomScrollView).first,
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();
      await tester.tap(firstRange);
      await tester.pumpAndSettle();

      expect(find.text('Episode 1'), findsWidgets);
      expect(find.text('Episode 250'), findsNothing);
    });

    testWidgets('a group that fits gets no range row', (tester) async {
      await open(tester, detailWith(100));

      expect(find.text('1–100'), findsNothing);
      expect(find.text('Episode 1'), findsWidgets);
      expect(find.text('Episode 100'), findsWidgets);
    });
  });
}

class _MemoryLibraryStore implements LibraryStore {
  @override
  Future<Map<String, UserMediaState>> load() async => {};

  @override
  Future<void> save(Map<String, UserMediaState> records) async {}
}
