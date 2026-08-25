import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_app/detail/episode_target_v2.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';

void main() {
  const seriesRef = MediaRef(
    extensionId: 'test',
    providerId: 'test.provider',
    id: 'series-1',
  );
  const episodeRef = MediaRef(
    extensionId: 'test',
    providerId: 'test.provider',
    id: 'episode-1',
  );
  const episode = EpisodeItemV2(
    ref: episodeRef,
    title: 'Episode title',
    subtitle: 'Example Series',
    episode: EpisodeIdentity(
      parentRef: seriesRef,
      groupId: 'opaque-group-2',
      position: 3,
    ),
  );

  test('episode display helpers use guide titles and opaque-safe fallback', () {
    const guide = EpisodeGuide(
      groups: [
        EpisodeGroup(id: 'opaque-group-2', title: 'Season 2', episodes: []),
      ],
    );

    expect(episodeSeriesTitle(episode), 'Example Series');
    expect(currentEpisodeContextLabel(episode, guide), 'Season 2 · Episode 3');
    expect(currentEpisodeContextLabel(episode, null), 'Episode 3');
  });

  test('the next episode keeps the air date the guide gave it', () {
    // Playing on from one episode to the next must not drop what the stream
    // role matches on: a provider that indexes by broadcast date would stop
    // finding sources partway through a binge.
    final guide = EpisodeGuide(
      groups: [
        EpisodeGroup(
          id: 'opaque-group-2',
          title: 'Season 2',
          episodes: [
            const EpisodeSummary(
              ref: episodeRef,
              title: 'Episode title',
              position: 3,
            ),
            EpisodeSummary(
              ref: const MediaRef(
                extensionId: 'test',
                providerId: 'test.provider',
                id: 'episode-2',
              ),
              title: 'Next title',
              position: 4,
              availableAt: DateTime.utc(2026, 8, 22),
            ),
          ],
        ),
      ],
    );

    final next = nextEpisodeOfV2(
      episode,
      guide,
      now: DateTime.utc(2026, 8, 25),
    );

    expect(next, isNotNull);
    expect(next!.item.availableAt, DateTime.utc(2026, 8, 22));
  });

  test('a lone unnumbered group is left out of the context label', () {
    // "Episodes · Episode 3" says the same word twice. A numbered season is
    // kept even when it is the only group, because it still places the episode.
    const guide = EpisodeGuide(
      groups: [
        EpisodeGroup(id: 'opaque-group-2', title: 'Episodes', episodes: []),
      ],
    );

    expect(currentEpisodeContextLabel(episode, guide), 'Episode 3');
  });

  test('series title falls back to episode title when subtitle is absent', () {
    const item = EpisodeItemV2(
      ref: episodeRef,
      title: 'Episode title',
      episode: EpisodeIdentity(
        parentRef: seriesRef,
        groupId: 'opaque-group-2',
        position: 3,
      ),
    );

    expect(episodeSeriesTitle(item), 'Episode title');
    expect(currentEpisodeContextLabel(item, null), 'Episode 3');
  });
}
