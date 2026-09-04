import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_app/library/library_controller.dart';
import 'package:fvcksubs_app/player/workflow/primary_episode_target.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_storage/fvcksubs_storage.dart';

const _seriesRef = MediaRef(
  extensionId: 'fake',
  providerId: 'fake.p',
  id: 'series',
);
const _s1e1 = MediaRef(extensionId: 'fake', providerId: 'fake.p', id: 's1e1');
const _s1e2 = MediaRef(extensionId: 'fake', providerId: 'fake.p', id: 's1e2');
const _s2e1 = MediaRef(extensionId: 'fake', providerId: 'fake.p', id: 's2e1');

const _season1 = EpisodeGroup(
  id: 'season-1',
  title: 'Season 1',
  episodes: [
    EpisodeSummary(ref: _s1e1, title: 'Episode 1', position: 1),
    EpisodeSummary(ref: _s1e2, title: 'Episode 2', position: 2),
  ],
);
const _season2 = EpisodeGroup(
  id: 'season-2',
  title: 'Season 2',
  episodes: [EpisodeSummary(ref: _s2e1, title: 'Episode 1', position: 1)],
);
const _guide = EpisodeGuide(groups: [_season1, _season2]);

LibraryState _libraryWithProgress(MediaRef ref, {required DateTime lastWatched}) {
  final item = EpisodeItemV2(
    ref: ref,
    title: 'watched',
    episode: const EpisodeIdentity(parentRef: _seriesRef, groupId: 'x', position: 1),
  );
  return LibraryState(
    records: {
      UserMediaState.keyFor(ref): UserMediaState(
        item: item,
        progress: const Duration(minutes: 1),
        lastWatched: lastWatched,
      ),
    },
  );
}

void main() {
  group('primaryEpisodeTarget', () {
    test('a null or empty guide resolves to nothing', () {
      expect(primaryEpisodeTarget(null, _seriesRef, LibraryState()), isNull);
      expect(
        primaryEpisodeTarget(
          const EpisodeGuide(groups: []),
          _seriesRef,
          LibraryState(),
        ),
        isNull,
      );
    });

    test('a resume episode wins over the guide default', () {
      final library = _libraryWithProgress(_s1e2, lastWatched: DateTime.utc(2026, 1, 1));
      final guide = _guide.copyWithDefault(_s2e1);

      final target = primaryEpisodeTarget(guide, _seriesRef, library);

      expect(target?.group.id, 'season-1');
      expect(target?.index, 1);
      expect(target?.resuming, isTrue);
    });

    test('the guide default wins when nothing is in progress', () {
      final guide = _guide.copyWithDefault(_s2e1);

      final target = primaryEpisodeTarget(guide, _seriesRef, LibraryState());

      expect(target?.group.id, 'season-2');
      expect(target?.index, 0);
      expect(target?.resuming, isFalse);
    });

    test('falls back to the last available episode with no default and nothing watched', () {
      final target = primaryEpisodeTarget(_guide, _seriesRef, LibraryState());

      expect(target?.group.id, 'season-2');
      expect(target?.index, 0);
      expect(target?.resuming, isFalse);
    });

    test('an unavailable (unreleased) episode is skipped as the resume target', () {
      final futureGuide = EpisodeGuide(
        groups: [
          EpisodeGroup(
            id: 'season-1',
            title: 'Season 1',
            episodes: [
              const EpisodeSummary(ref: _s1e1, title: 'Episode 1', position: 1),
              EpisodeSummary(
                ref: _s1e2,
                title: 'Episode 2',
                position: 2,
                availableAt: DateTime.utc(2099),
              ),
            ],
          ),
        ],
      );

      final target = primaryEpisodeTarget(futureGuide, _seriesRef, LibraryState());

      expect(target?.index, 0);
    });

    test('the more recently watched resume episode wins across seasons', () {
      final library = LibraryState(
        records: {
          UserMediaState.keyFor(_s1e1): UserMediaState(
            item: const EpisodeItemV2(
              ref: _s1e1,
              title: 'e',
              episode: EpisodeIdentity(
                parentRef: _seriesRef,
                groupId: 'season-1',
                position: 1,
              ),
            ),
            progress: const Duration(minutes: 1),
            lastWatched: DateTime.utc(2026, 1, 1),
          ),
          UserMediaState.keyFor(_s2e1): UserMediaState(
            item: const EpisodeItemV2(
              ref: _s2e1,
              title: 'e',
              episode: EpisodeIdentity(
                parentRef: _seriesRef,
                groupId: 'season-2',
                position: 1,
              ),
            ),
            progress: const Duration(minutes: 1),
            lastWatched: DateTime.utc(2026, 6, 1),
          ),
        },
      );

      final target = primaryEpisodeTarget(_guide, _seriesRef, library);

      expect(target?.group.id, 'season-2');
    });
  });

  group('hasEpisodes / isEpisodeAvailable', () {
    test('hasEpisodes is false for a null or empty guide', () {
      expect(hasEpisodes(null), isFalse);
      expect(hasEpisodes(const EpisodeGuide(groups: [])), isFalse);
      expect(
        hasEpisodes(const EpisodeGuide(groups: [EpisodeGroup(id: 'x', title: 'x', episodes: [])])),
        isFalse,
      );
      expect(hasEpisodes(_guide), isTrue);
    });

    test('isEpisodeAvailable reflects availableAt', () {
      expect(
        isEpisodeAvailable(const EpisodeSummary(ref: _s1e1, title: 't', position: 1)),
        isTrue,
      );
      expect(
        isEpisodeAvailable(
          EpisodeSummary(ref: _s1e1, title: 't', position: 1, availableAt: DateTime.utc(2099)),
        ),
        isFalse,
      );
    });
  });

  group('primaryPlaybackTarget', () {
    test('a non-episodic item returns itself when there is no target', () {
      const video = VideoItemV2(ref: _seriesRef, title: 'Movie');
      const detail = MediaDetailV2(item: video);

      expect(primaryPlaybackTarget(detail, null), video);
    });

    test('an episodic item with episodes but no available target returns null', () {
      const detail = MediaDetailV2(
        item: SeriesItemV2(ref: _seriesRef, title: 'Series'),
        episodeGuide: _guide,
      );

      expect(primaryPlaybackTarget(detail, null), isNull);
    });

    test('a resolved target is converted into a real EpisodeItemV2', () {
      const detail = MediaDetailV2(
        item: SeriesItemV2(ref: _seriesRef, title: 'Series'),
        episodeGuide: _guide,
      );

      final item = primaryPlaybackTarget(detail, (group: _season2, index: 0, resuming: false));

      expect(item, isA<EpisodeItemV2>());
      expect((item! as EpisodeItemV2).episode.position, 1);
      expect((item as EpisodeItemV2).episode.groupId, 'season-2');
      expect(item.subtitle, 'Series');
    });

    test('an episode parent keeps its series ref for rail playback', () {
      const current = EpisodeItemV2(
        ref: _s1e1,
        title: 'Episode 1',
        subtitle: 'Series',
        episode: EpisodeIdentity(
          parentRef: _seriesRef,
          groupId: 'season-1',
          position: 1,
        ),
      );

      final item = episodeItemFrom(current, _season1, 1);

      expect(item.ref, _s1e2);
      expect(item.episode.parentRef, _seriesRef);
      expect(item.episode.groupId, 'season-1');
      expect(item.subtitle, 'Series');
    });
  });
}

extension on EpisodeGuide {
  EpisodeGuide copyWithDefault(MediaRef ref) =>
      EpisodeGuide(groups: groups, defaultEpisodeRef: ref);
}
