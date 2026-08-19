import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_app/detail/detail_page.dart';
import 'package:fvcksubs_app/library/legacy_library_controller.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';

import 'support/harness.dart';

void main() {
  testWidgets(
    'picking a source resolves it and hands the stream to the player',
    (tester) async {
      final registry = ExtensionRegistry([
        FakeExtension(
          sourceList: const [
            StreamSource(id: 'src-1', label: 'HD 1080p', provider: 'Kora'),
          ],
          resolved: const PlayableStream(
            url: 'https://edge/live.m3u8',
            format: StreamFormat.hls,
          ),
        ),
      ]);
      final player = RecordingPlayer();

      await tester.pumpWidget(
        wrapApp(
          child: DetailPage(item: fakeItem()),
          registry: registry,
          player: player,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Play'), findsOneWidget);
      expect(find.byKey(const Key('fake-player')), findsNothing);

      await tester.tap(find.text('Play'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('fake-player')), findsOneWidget);
      expect(player.played?.url, 'https://edge/live.m3u8');
    },
  );

  testWidgets('an unsupported source shows an honest message, not the player', (
    tester,
  ) async {
    // Unsupported DRM is refused on every target (here the default: android),
    // so this exercises the honest-gate branch without a platform override.
    final registry = ExtensionRegistry([
      FakeExtension(
        sourceList: const [StreamSource(id: 's', label: 'Protected source')],
        resolved: const PlayableStream(
          url: 'https://edge/live.mpd',
          format: StreamFormat.dash,
          drm: DrmConfig(scheme: DrmScheme.unsupported),
        ),
      ),
    ]);
    final player = RecordingPlayer();

    await tester.pumpWidget(
      wrapApp(
        child: DetailPage(item: fakeItem()),
        registry: registry,
        player: player,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Play'));
    await tester.pumpAndSettle();

    expect(find.textContaining('No playable sources found.'), findsOneWidget);
    expect(find.byKey(const Key('fake-player')), findsNothing);
    expect(player.played, isNull);
  });

  testWidgets(
    'on iOS, DASH is refused too — even with no DRM at all (M6 honest-gate)',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

      final registry = ExtensionRegistry([
        FakeExtension(
          sourceList: const [StreamSource(id: 's', label: 'DASH source')],
          resolved: const PlayableStream(
            url: 'https://edge/live.mpd',
            format: StreamFormat.dash,
          ),
        ),
      ]);
      final player = RecordingPlayer();

      await tester.pumpWidget(
        wrapApp(
          child: DetailPage(item: fakeItem()),
          registry: registry,
          player: player,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Play'));
      await tester.pumpAndSettle();

      expect(find.textContaining('No playable sources found.'), findsOneWidget);
      expect(player.played, isNull);

      // Must be unset before the test ends — TestWidgetsFlutterBinding
      // asserts every debug var is back to its default once the test body
      // returns, which runs before a file-level tearDown would fire.
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('the favorite button toggles Library state', (tester) async {
    final item = fakeItem();
    final controller = LegacyLibraryController(store: FakeLibraryStore());

    await tester.pumpWidget(
      wrapApp(
        child: DetailPage(item: item),
        registry: ExtensionRegistry([FakeExtension()]),
        legacyLibraryController: controller,
      ),
    );
    await tester.pumpAndSettle();

    expect(controller.isFavorite(item.ref), isFalse);
    expect(find.byIcon(Icons.add), findsOneWidget);

    await tester.tap(find.text('My List'));
    await tester.pumpAndSettle();

    expect(controller.isFavorite(item.ref), isTrue);
    expect(find.byIcon(Icons.check), findsOneWidget);
  });

  testWidgets('successfully playing a source records it as watched', (
    tester,
  ) async {
    final item = fakeItem();
    final controller = LegacyLibraryController(store: FakeLibraryStore());
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
        child: DetailPage(item: item),
        registry: registry,
        legacyLibraryController: controller,
      ),
    );
    await tester.pumpAndSettle();

    expect(controller.history, isEmpty);

    await tester.tap(find.text('Play'));
    await tester.pumpAndSettle();

    expect(controller.history, hasLength(1));
    expect(controller.history.single.ref, item.ref);
  });

  testWidgets('the hero shows title and subtitle correctly', (tester) async {
    final item = fakeItem(
      title: 'Arsenal vs Chelsea',
      subtitle: 'Premier League',
      participants: const [
        Participant(name: 'Arsenal'),
        Participant(name: 'Chelsea'),
      ],
    );

    await tester.pumpWidget(
      wrapApp(
        child: DetailPage(item: item),
        registry: ExtensionRegistry([FakeExtension()]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Arsenal vs Chelsea'), findsOneWidget);
    expect(find.text('Premier League'), findsAtLeast(1));
  });

  group('a series Play button', () {
    MediaDetail showWith(MediaItem item, List<SeriesSeason> seasons) =>
        MediaDetail(item: item, seasons: seasons);

    SeriesSeason season(int number, int episodes) => SeriesSeason(
      number: number,
      name: 'Season $number',
      episodes: [
        for (var i = 1; i <= episodes; i++) SeriesEpisode(title: 'Ep $i'),
      ],
    );

    testWidgets(
      'shows the metadata guess in the label before any tap — S1E1 with '
      'no last-aired hint to say otherwise',
      (tester) async {
        final item = fakeItem(poster: const ImageRef('https://cdn/x.jpg'));
        final registry = ExtensionRegistry([
          FakeExtension(
            metaDetail: showWith(item, [season(1, 10), season(2, 8)]),
            sourceList: const [StreamSource(id: 's', label: 'HD')],
            resolved: const PlayableStream(
              url: 'https://edge/x.m3u8',
              format: StreamFormat.hls,
            ),
          ),
        ]);

        await tester.pumpWidget(
          wrapApp(
            child: DetailPage(item: item),
            registry: registry,
          ),
        );
        await tester.pumpAndSettle();

        // Shown right away — episodeTargetFor's own guess, not yet
        // confirmed streamable by the probe that runs on tap.
        expect(find.text('Play S1E1'), findsOneWidget);
      },
    );

    testWidgets('pressing Play on a fresh series lands on the latest available '
        'episode, not S1E1', (tester) async {
      final item = fakeItem(poster: const ImageRef('https://cdn/x.jpg'));
      final controller = LegacyLibraryController(store: FakeLibraryStore());
      final registry = ExtensionRegistry([
        FakeExtension(
          metaDetail: showWith(item, [season(1, 10)]),
          // The catalog lists all 10 episodes' titles, but only the first
          // 3 have actually aired anywhere a provider can reach them.
          sourceListFor: (probed) {
            final episode = probed.extra['episode'];
            return (episode is int && episode <= 3)
                ? const [StreamSource(id: 's', label: 'HD')]
                : const [];
          },
          resolved: const PlayableStream(
            url: 'https://edge/x.m3u8',
            format: StreamFormat.hls,
          ),
        ),
      ]);

      await tester.pumpWidget(
        wrapApp(
          child: DetailPage(item: item),
          registry: registry,
          legacyLibraryController: controller,
        ),
      );
      await tester.pumpAndSettle();

      // No last-aired hint here, so the label's own guess is S1E1 — the
      // probe below is what actually finds episode 3.
      await tester.tap(find.text('Play S1E1'));
      await tester.pumpAndSettle();

      expect(controller.history, hasLength(1));
      expect(controller.history.single.item.extra['season'], 1);
      expect(controller.history.single.item.extra['episode'], 3);
    });

    testWidgets(
      'a last-aired hint sends the probe straight there — nothing after '
      'it is ever even asked about',
      (tester) async {
        final item = fakeItem(poster: const ImageRef('https://cdn/x.jpg'));
        final controller = LegacyLibraryController(store: FakeLibraryStore());
        final probed = <int>[];
        final registry = ExtensionRegistry([
          FakeExtension(
            // The catalog lists 10 episodes, but TMDB's own last-aired data
            // says only the first 3 are actually out yet.
            metaDetail: MediaDetail(
              item: item,
              seasons: [season(1, 10)],
              lastAiredSeason: 1,
              lastAiredEpisode: 3,
            ),
            sourceListFor: (candidate) {
              final episode = candidate.extra['episode'];
              if (episode is int) probed.add(episode);
              return const [StreamSource(id: 's', label: 'HD')];
            },
            resolved: const PlayableStream(
              url: 'https://edge/x.m3u8',
              format: StreamFormat.hls,
            ),
          ),
        ]);

        await tester.pumpWidget(
          wrapApp(
            child: DetailPage(item: item),
            registry: registry,
            legacyLibraryController: controller,
          ),
        );
        await tester.pumpAndSettle();

        // The hint means the label already says S1E3 up front.
        await tester.tap(find.text('Play S1E3'));
        await tester.pumpAndSettle();

        // Episodes 4 through 10 — TMDB says unaired — are never even asked
        // about; the probe stays within the hinted bound.
        expect(probed.every((episode) => episode <= 3), isTrue);
        // And within that bound, it still landed on the true newest one.
        expect(controller.history.single.item.extra['episode'], 3);
      },
    );

    testWidgets('falls back to S1E1 when nothing probes as available', (
      tester,
    ) async {
      final item = fakeItem(poster: const ImageRef('https://cdn/x.jpg'));
      final registry = ExtensionRegistry([
        FakeExtension(
          metaDetail: showWith(item, [season(1, 3)]),
          sourceListFor: (_) => const [],
          resolved: const PlayableStream(
            url: 'https://edge/x.m3u8',
            format: StreamFormat.hls,
          ),
        ),
      ]);

      await tester.pumpWidget(
        wrapApp(
          child: DetailPage(item: item),
          registry: registry,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Play S1E1'));
      await tester.pumpAndSettle();

      // The probe found nothing, fell back to S1E1, and playItem itself
      // then found no sources for that either — same honest message as
      // any other item with nothing playable.
      expect(find.textContaining('No playable sources found.'), findsOneWidget);
    });

    testWidgets('continues from the episode last watched', (tester) async {
      final item = fakeItem(poster: const ImageRef('https://cdn/x.jpg'));
      final registry = ExtensionRegistry([
        FakeExtension(
          metaDetail: showWith(item, [season(1, 10), season(2, 8)]),
          sourceList: const [StreamSource(id: 's', label: 'HD')],
          resolved: const PlayableStream(
            url: 'https://edge/x.m3u8',
            format: StreamFormat.hls,
          ),
        ),
      ]);
      final controller = LegacyLibraryController(store: FakeLibraryStore());
      // What playing S2E3 leaves behind: episodes share the series' ref and
      // carry their coordinates in `extra`.
      controller.recordWatched(
        MediaItem(
          ref: item.ref,
          kind: MediaKind.episode,
          title: 'Ep 3 (S2E3)',
          extra: const {'season': 2, 'episode': 3},
        ),
      );

      await tester.pumpWidget(
        wrapApp(
          child: DetailPage(item: item),
          registry: registry,
          legacyLibraryController: controller,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Continue S2E3'), findsOneWidget);
      expect(find.text('Play S1E1'), findsNothing);
    });

    testWidgets('a movie keeps a plain Play', (tester) async {
      final item = fakeItem(poster: const ImageRef('https://cdn/x.jpg'));
      final registry = ExtensionRegistry([
        FakeExtension(metaDetail: MediaDetail(item: item)),
      ]);

      await tester.pumpWidget(
        wrapApp(
          child: DetailPage(item: item),
          registry: registry,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Play'), findsOneWidget);
    });

    testWidgets('a movie with a saved position offers to continue watching', (
      tester,
    ) async {
      final item = fakeItem(poster: const ImageRef('https://cdn/x.jpg'));
      final registry = ExtensionRegistry([
        FakeExtension(metaDetail: MediaDetail(item: item)),
      ]);
      final controller = LegacyLibraryController(store: FakeLibraryStore());
      controller.recordWatched(item, progress: const Duration(minutes: 20));

      await tester.pumpWidget(
        wrapApp(
          child: DetailPage(item: item),
          registry: registry,
          legacyLibraryController: controller,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Continue Watching'), findsOneWidget);
      expect(find.text('Play'), findsNothing);
    });

    testWidgets(
      'a movie watched but with no saved position keeps a plain Play',
      (tester) async {
        // Distinguishes "no watch record at all" from "watched, but nothing
        // to resume" (finished, or progress explicitly cleared) — both
        // should read as a plain Play, not just the never-watched case.
        final item = fakeItem(poster: const ImageRef('https://cdn/x.jpg'));
        final registry = ExtensionRegistry([
          FakeExtension(metaDetail: MediaDetail(item: item)),
        ]);
        final controller = LegacyLibraryController(store: FakeLibraryStore());
        controller.recordWatched(item);

        await tester.pumpWidget(
          wrapApp(
            child: DetailPage(item: item),
            registry: registry,
            legacyLibraryController: controller,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Play'), findsOneWidget);
        expect(find.text('Continue Watching'), findsNothing);
      },
    );
  });

  group('episodes list', () {
    SeriesSeason seasonNamed(int number, int episodes) => SeriesSeason(
      number: number,
      name: 'Season $number',
      episodes: [
        for (var i = 1; i <= episodes; i++)
          SeriesEpisode(title: 'S${number}E$i'),
      ],
    );

    testWidgets(
      'defaults to the latest season, not whichever is listed first',
      (tester) async {
        final item = fakeItem(poster: const ImageRef('https://cdn/x.jpg'));
        final registry = ExtensionRegistry([
          FakeExtension(
            metaDetail: MediaDetail(
              item: item,
              seasons: [
                seasonNamed(1, 2),
                seasonNamed(3, 2),
                seasonNamed(2, 2),
              ],
            ),
          ),
        ]);

        await tester.pumpWidget(
          wrapApp(
            child: DetailPage(item: item),
            registry: registry,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('1. S3E1'), findsOneWidget);
        expect(find.text('1. S1E1'), findsNothing);
      },
    );

    testWidgets(
      'a future release date dims the tile and hides its play button',
      (tester) async {
        final item = fakeItem(poster: const ImageRef('https://cdn/x.jpg'));
        final future = DateTime.now().add(const Duration(days: 30));
        final registry = ExtensionRegistry([
          FakeExtension(
            metaDetail: MediaDetail(
              item: item,
              seasons: [
                SeriesSeason(
                  number: 1,
                  name: 'Season 1',
                  episodes: [
                    const SeriesEpisode(title: 'Out already'),
                    SeriesEpisode(title: 'Not yet', releaseDate: future),
                  ],
                ),
              ],
            ),
          ),
        ]);

        await tester.pumpWidget(
          wrapApp(
            child: DetailPage(item: item),
            registry: registry,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.textContaining('Releases'), findsOneWidget);
        // Only the released episode gets a play button.
        expect(find.byIcon(Icons.play_circle_outline), findsOneWidget);
      },
    );

    testWidgets(
      'with no per-episode date, the last-aired bound marks the rest unreleased',
      (tester) async {
        final item = fakeItem(poster: const ImageRef('https://cdn/x.jpg'));
        final registry = ExtensionRegistry([
          FakeExtension(
            metaDetail: MediaDetail(
              item: item,
              seasons: [seasonNamed(1, 5)],
              lastAiredSeason: 1,
              lastAiredEpisode: 3,
            ),
          ),
        ]);

        await tester.pumpWidget(
          wrapApp(
            child: DetailPage(item: item),
            registry: registry,
          ),
        );
        await tester.pumpAndSettle();

        // Episodes 4 and 5 are past the bound — no date to name, just the
        // generic note — and 1 through 3 keep their play button.
        expect(find.text('Not yet released'), findsNWidgets(2));
        expect(find.byIcon(Icons.play_circle_outline), findsNWidgets(3));
      },
    );
  });
}
