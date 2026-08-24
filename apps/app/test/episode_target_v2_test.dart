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
