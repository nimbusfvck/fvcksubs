import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_app/detail/episode_target.dart';
import 'package:fvcksubs_storage/fvcksubs_storage.dart';

/// Where a series' Play button picks up.
void main() {
  SeriesSeason season(int number, int episodes) => SeriesSeason(
    number: number,
    name: 'Season $number',
    episodes: [
      for (var i = 1; i <= episodes; i++) SeriesEpisode(title: 'Ep $i'),
    ],
  );

  const seriesRef = MediaRef(
    extensionId: 'example_extension',
    providerId: 'example_extension.media',
    id: 'tv:1399',
  );
  const series = MediaItem(
    ref: seriesRef,
    kind: MediaKind.series,
    title: 'Some Show',
    extra: {'tmdb': '1399'},
  );

  /// A library record standing for "this episode was the last one played".
  LegacyUserMediaState watched(int s, int e) => LegacyUserMediaState(
    ref: seriesRef,
    item: MediaItem(
      ref: seriesRef,
      kind: MediaKind.episode,
      title: 'whatever',
      extra: {'season': s, 'episode': e},
    ),
    lastWatched: DateTime(2026, 8, 17),
  );

  test('nothing watched starts at the latest episode of the latest season', () {
    final target = episodeTargetFor([season(1, 10), season(2, 8)], null);

    expect(target!.season, 2);
    expect(target.episode, 8);
    expect(target.resuming, isFalse);
    expect(target.label, 'S2E8');
  });

  test('a specials season does not become the latest episode', () {
    // Specials are conventionally season 0 and often lead the list; "Play"
    // on a series means start the show, not its extras.
    final target = episodeTargetFor([season(0, 3), season(1, 10)], null);

    expect(target!.season, 1);
    expect(target.episode, 10);
  });

  test('resumes the episode last watched', () {
    final target = episodeTargetFor([
      season(1, 10),
      season(2, 8),
    ], watched(2, 3));

    expect(target!.season, 2);
    expect(target.episode, 3);
    expect(target.resuming, isTrue);
    expect(target.label, 'S2E3');
    expect(target.title, 'Ep 3');
  });

  test('a remembered episode that no longer exists starts over instead', () {
    // Seasons get re-cut and withdrawn upstream between sessions; resuming
    // onto a gone episode would fail where the viewer can least act on it.
    final target = episodeTargetFor([season(1, 10)], watched(4, 2));
    expect(target!.season, 1);
    expect(target.episode, 10);
    expect(target.resuming, isFalse);

    final past = episodeTargetFor([season(1, 10)], watched(1, 99));
    expect(past!.episode, 10);
    expect(past.resuming, isFalse);
  });

  test('a record with no episode coordinates is not a resume point', () {
    // What a *movie* record looks like — nothing about episodes in it.
    final target = episodeTargetFor(
      [season(1, 10)],
      LegacyUserMediaState(
        ref: seriesRef,
        item: series,
        lastWatched: DateTime(2026, 8, 17),
      ),
    );

    expect(target!.resuming, isFalse);
    expect(target.episode, 10);
  });

  test(
    'nothing watched but a last-aired hint starts there instead of S1E1',
    () {
      final target = episodeTargetFor(
        [season(1, 10), season(2, 8)],
        null,
        lastAiredSeason: 2,
        lastAiredEpisode: 5,
      );

      expect(target!.season, 2);
      expect(target.episode, 5);
      expect(target.title, 'Ep 5');
      // Not a resume — the viewer never actually watched anything, so the
      // button still just says "Play", not "Continue S2E5".
      expect(target.resuming, isFalse);
    },
  );

  test('a watched record still wins over the last-aired hint', () {
    final target = episodeTargetFor(
      [season(1, 10), season(2, 8)],
      watched(1, 3),
      lastAiredSeason: 2,
      lastAiredEpisode: 5,
    );

    expect(target!.season, 1);
    expect(target.episode, 3);
    expect(target.resuming, isTrue);
  });

  test(
    'a last-aired hint pointing past what seasons actually holds falls back to the latest episode',
    () {
      // TMDB can say more has aired than this app's own seasons list carries
      // yet (a stale fetch, a mid-air-date race) — don't point Play at
      // something that isn't there.
      final target = episodeTargetFor(
        [season(1, 10)],
        null,
        lastAiredSeason: 2,
        lastAiredEpisode: 1,
      );

      expect(target!.season, 1);
      expect(target.episode, 10);
    },
  );

  test('no seasons at all means no target — the item plays itself', () {
    expect(episodeTargetFor(const [], null), isNull);
    // Declared but empty counts as nothing playable, not as "season 1".
    expect(episodeTargetFor([season(1, 0)], null), isNull);
  });

  test('the item handed to the player carries the episode coordinates', () {
    final target = episodeTargetFor([
      season(1, 10),
      season(2, 8),
    ], watched(2, 3));
    final item = target!.itemFor(series);

    // Episodes have no ref of their own — they are the series plus `extra`,
    // which is what the stream providers read.
    expect(item.ref, seriesRef);
    expect(item.kind, MediaKind.episode);
    expect(item.extra['season'], 2);
    expect(item.extra['episode'], 3);
    // The series' own extra survives alongside them.
    expect(item.extra['tmdb'], '1399');
    expect(item.title, 'Ep 3 (S2E3)');
    // The episode's title replaces the series' one, so the series title has
    // to travel separately for providers that search by name.
    expect(item.extra['seriesTitle'], 'Some Show');
  });

  group('defaultSeasonIndex', () {
    test('picks the season matching the last-aired hint', () {
      final seasons = [season(1, 10), season(2, 8), season(3, 4)];
      expect(defaultSeasonIndex(seasons, 2), 1);
    });

    test('falls back to the highest-numbered season with no hint', () {
      final seasons = [season(1, 10), season(3, 4), season(2, 8)];
      expect(defaultSeasonIndex(seasons, null), 1);
    });

    test('a hint for a season that is not in the list is ignored', () {
      final seasons = [season(1, 10), season(2, 8)];
      expect(defaultSeasonIndex(seasons, 99), 1);
    });

    test(
      'a specials season never wins on number alone unless it is all there is',
      () {
        expect(defaultSeasonIndex([season(0, 3)], null), 0);
      },
    );

    test('no seasons at all defaults to index 0', () {
      expect(defaultSeasonIndex(const [], null), 0);
    });
  });

  group('isUnreleased', () {
    final now = DateTime.utc(2026, 6, 15);
    SeriesEpisode episodeWithDate(DateTime? date) =>
        SeriesEpisode(title: 'Ep', releaseDate: date);

    test('a future release date is unreleased', () {
      expect(
        isUnreleased(
          episodeWithDate(DateTime.utc(2026, 7, 1)),
          seasonNumber: 1,
          episodeNum: 1,
          now: now,
        ),
        isTrue,
      );
    });

    test('a past or today release date is released', () {
      expect(
        isUnreleased(
          episodeWithDate(DateTime.utc(2026, 6, 1)),
          seasonNumber: 1,
          episodeNum: 1,
          now: now,
        ),
        isFalse,
      );
    });

    test('with no release date, falls back to the last-aired bound', () {
      final episode = episodeWithDate(null);
      expect(
        isUnreleased(
          episode,
          seasonNumber: 2,
          episodeNum: 5,
          lastAiredSeason: 2,
          lastAiredEpisode: 4,
          now: now,
        ),
        isTrue,
      );
      expect(
        isUnreleased(
          episode,
          seasonNumber: 2,
          episodeNum: 4,
          lastAiredSeason: 2,
          lastAiredEpisode: 4,
          now: now,
        ),
        isFalse,
      );
      expect(
        isUnreleased(
          episode,
          seasonNumber: 1,
          episodeNum: 99,
          lastAiredSeason: 2,
          lastAiredEpisode: 4,
          now: now,
        ),
        isFalse,
      );
    });

    test(
      'with neither a release date nor a last-aired bound, nothing is unreleased',
      () {
        expect(
          isUnreleased(
            episodeWithDate(null),
            seasonNumber: 5,
            episodeNum: 1,
            now: now,
          ),
          isFalse,
        );
      },
    );

    test(
      'the release date wins even if it disagrees with the last-aired bound',
      () {
        // Shouldn't normally happen, but the per-episode fact is the more
        // specific one when both are present.
        expect(
          isUnreleased(
            episodeWithDate(DateTime.utc(2026, 5, 1)),
            seasonNumber: 9,
            episodeNum: 9,
            lastAiredSeason: 1,
            lastAiredEpisode: 1,
            now: now,
          ),
          isFalse,
        );
      },
    );
  });

  group('nextEpisodeTarget', () {
    test('the next episode within the same season', () {
      final next = nextEpisodeTarget([season(1, 10), season(2, 8)], 1, 3);

      expect(next!.season, 1);
      expect(next.episode, 4);
      expect(next.title, 'Ep 4');
      expect(next.resuming, isFalse);
    });

    test('the last episode of a season rolls into the next season', () {
      final next = nextEpisodeTarget([season(1, 3), season(2, 5)], 1, 3);

      expect(next!.season, 2);
      expect(next.episode, 1);
      expect(next.title, 'Ep 1');
    });

    test('rolling forward never lands on a specials season', () {
      // Season 0 sits before season 1 numerically, but "next" always means
      // forward — a viewer finishing season 1 should not be dropped into
      // Specials.
      final next = nextEpisodeTarget([season(0, 3), season(1, 2)], 1, 2);

      expect(next, isNull);
    });

    test('the series finale has no next episode', () {
      expect(nextEpisodeTarget([season(1, 10)], 1, 10), isNull);
    });

    test('an unrecognized current season has no next episode', () {
      expect(nextEpisodeTarget([season(1, 10)], 99, 1), isNull);
    });

    test('an empty later season is skipped in favor of the one after it', () {
      final next = nextEpisodeTarget(
        [season(1, 3), season(2, 0), season(3, 5)],
        1,
        3,
      );

      expect(next!.season, 3);
      expect(next.episode, 1);
    });
  });

  group('nextEpisodeOf', () {
    MediaItem episodeItem(int s, int e, {String title = 'whatever'}) =>
        EpisodeTarget(
          season: s,
          episode: e,
          title: title,
          resuming: false,
        ).itemFor(series);

    test('builds the next episode, carrying the series identity forward', () {
      final seasons = [season(1, 3), season(2, 5)];
      final next = nextEpisodeOf(episodeItem(1, 2), seasons);

      expect(next, isNotNull);
      expect(next!.item.ref, seriesRef);
      expect(next.item.kind, MediaKind.episode);
      expect(next.season, 1);
      expect(next.episode, 3);
      expect(next.episodeTitle, 'Ep 3');
      expect(next.seriesTitle, 'Some Show');
      // The series' own extra survives the hop too, on the playable item.
      expect(next.item.extra['tmdb'], '1399');
      expect(next.item.extra['seriesTitle'], 'Some Show');
    });

    test('rolls into the next season across the hop', () {
      final seasons = [season(1, 1), season(2, 5)];
      final next = nextEpisodeOf(episodeItem(1, 1), seasons);

      expect(next!.season, 2);
      expect(next.episode, 1);
    });

    test('null for an item with no episode coordinates', () {
      expect(nextEpisodeOf(series, [season(1, 10)]), isNull);
    });

    test('null past the series finale', () {
      final seasons = [season(1, 2)];

      expect(nextEpisodeOf(episodeItem(1, 2), seasons), isNull);
    });
  });
}
