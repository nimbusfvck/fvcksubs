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
    expect(find.text('Episode 2'), findsNWidgets(2));
    expect(find.text('Episode 1'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Continue S2E2'), findsOneWidget);
  });
}

class _MemoryLibraryStore implements LibraryStore {
  @override
  Future<Map<String, UserMediaState>> load() async => {};

  @override
  Future<void> save(Map<String, UserMediaState> records) async {}
}
