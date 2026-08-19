import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:test/test.dart';

import '../support/round_trip.dart';

void main() {
  const ref = MediaRef(
    extensionId: 'cricfy',
    providerId: 'cricfy.events',
    id: 'evt-42',
  );

  group('MediaItem round-trips', () {
    test('a two-sided live event with scores', () {
      final item = MediaItem(
        ref: ref,
        kind: MediaKind.liveEvent,
        title: 'Manchester United vs Liverpool',
        subtitle: 'Premier League',
        thumbnail: const ImageRef('https://cdn.example.com/mu-liv.jpg'),
        startsAt: DateTime.utc(2026, 8, 16, 14, 30),
        status: LiveStatus.live,
        statusLabel: "62'",
        participants: const [
          Participant(
            name: 'Manchester United',
            shortName: 'Man Utd',
            logo: ImageRef('https://cdn.example.com/mu.png'),
            score: '2',
          ),
          Participant(name: 'Liverpool', score: '1'),
        ],
        badges: const ['4K', 'ID Comm'],
        extra: const {'cricfyChannel': 'sports-hd-1'},
      );

      expectRoundTrips(
        item,
        toJson: (m) => m.toJson(),
        fromJson: MediaItem.fromJson,
      );
    });

    test('a bare film (no participants, poster only)', () {
      const item = MediaItem(
        ref: MediaRef(
          extensionId: 'tmdb',
          providerId: 'tmdb.movies',
          id: '603',
        ),
        kind: MediaKind.movie,
        title: 'The Matrix',
        subtitle: '1999',
        poster: ImageRef('https://cdn.example.com/matrix.jpg'),
      );

      expectRoundTrips(
        item,
        toJson: (m) => m.toJson(),
        fromJson: MediaItem.fromJson,
      );
    });

    test('a race (many participants, string lap times)', () {
      const item = MediaItem(
        ref: MediaRef(
          extensionId: 'cricfy',
          providerId: 'cricfy.events',
          id: 'motogp-qat',
        ),
        kind: MediaKind.liveEvent,
        title: 'MotoGP Grand Prix of Qatar — Race',
        status: LiveStatus.scheduled,
        participants: [
          Participant(name: 'Marc Marquez', score: "1'23.456"),
          Participant(name: 'Francesco Bagnaia', score: "1'23.501"),
          Participant(name: 'Jorge Martin', score: "1'23.780"),
        ],
      );

      expectRoundTrips(
        item,
        toJson: (m) => m.toJson(),
        fromJson: MediaItem.fromJson,
      );
    });
  });

  test('MediaDetail round-trips', () {
    const detail = MediaDetail(
      item: MediaItem(ref: ref, kind: MediaKind.liveEvent, title: 'Some Event'),
      description: 'A longer synopsis that the hero shows.',
    );

    expectRoundTrips(
      detail,
      toJson: (d) => d.toJson(),
      fromJson: MediaDetail.fromJson,
    );
  });

  test('MediaDetail with tagline/genres/runtimeMinutes round-trips', () {
    const detail = MediaDetail(
      item: MediaItem(ref: ref, kind: MediaKind.movie, title: 'A Film'),
      description: 'A longer synopsis.',
      tagline: 'Every act of vengeance has a cost.',
      genres: ['Action', 'Sci-Fi'],
      runtimeMinutes: 128,
    );

    expectRoundTrips(
      detail,
      toJson: (d) => d.toJson(),
      fromJson: MediaDetail.fromJson,
    );
  });

  test('MediaDetail with none of the optional fields omits them entirely', () {
    const detail = MediaDetail(
      item: MediaItem(ref: ref, kind: MediaKind.liveEvent, title: 'Some Event'),
    );

    final json = detail.toJson();
    expect(json.containsKey('description'), isFalse);
    expect(json.containsKey('tagline'), isFalse);
    expect(json.containsKey('genres'), isFalse);
    expect(json.containsKey('runtimeMinutes'), isFalse);
    expect(json.containsKey('certification'), isFalse);
    expect(json.containsKey('networks'), isFalse);
    expect(json.containsKey('cast'), isFalse);
    expect(json.containsKey('seasons'), isFalse);
  });

  test('CastMember round-trips', () {
    const member = CastMember(
      name: 'Kyle Chandler',
      character: 'Hal Jordan',
      photoUrl: 'https://image.tmdb.org/t/p/w200/x.jpg',
    );
    expectRoundTrips(
      member,
      toJson: (m) => m.toJson(),
      fromJson: CastMember.fromJson,
    );
  });

  test('CastMember with no character/photo omits both', () {
    const member = CastMember(name: 'Kyle Chandler');
    final json = member.toJson();
    expect(json, {'name': 'Kyle Chandler'});
  });

  test('SeriesSeason with episodes round-trips', () {
    const season = SeriesSeason(
      number: 1,
      name: 'Season 1',
      episodes: [
        SeriesEpisode(
          title: 'Pilot',
          description: 'After a fatal shooting...',
          thumbnailUrl: 'https://image.tmdb.org/t/p/w500/ep1.jpg',
          duration: '57m',
        ),
        SeriesEpisode(title: 'Episode 2'),
      ],
    );
    expectRoundTrips(
      season,
      toJson: (s) => s.toJson(),
      fromJson: SeriesSeason.fromJson,
    );
  });

  test('MediaDetail with cast/seasons/networks/certification round-trips', () {
    const detail = MediaDetail(
      item: MediaItem(ref: ref, kind: MediaKind.series, title: 'Lanterns'),
      certification: 'TV-MA',
      networks: ['HBO'],
      cast: [CastMember(name: 'Kyle Chandler', character: 'Hal Jordan')],
      seasons: [
        SeriesSeason(
          number: 1,
          name: 'Season 1',
          episodes: [SeriesEpisode(title: 'Pilot', duration: '57m')],
        ),
      ],
    );
    expectRoundTrips(
      detail,
      toJson: (d) => d.toJson(),
      fromJson: MediaDetail.fromJson,
    );
  });

  test('a movie has no seasons even when MediaDetail carries other fields', () {
    const detail = MediaDetail(
      item: MediaItem(ref: ref, kind: MediaKind.movie, title: 'A Film'),
      cast: [CastMember(name: 'Someone')],
    );
    expect(detail.seasons, isEmpty);
  });

  test('unknown status decodes to LiveStatus.unknown, not a throw', () {
    final decoded = MediaItem.fromJson({
      'ref': ref.toJson(),
      'kind': 'liveEvent',
      'title': 'x',
      'status': 'someFutureStatus',
    });
    expect(decoded.status, LiveStatus.unknown);
  });

  test('unknown kind throws — apiVersion is meant to catch this', () {
    expect(
      () => MediaItem.fromJson({
        'ref': ref.toJson(),
        'kind': 'hologram',
        'title': 'x',
      }),
      throwsFormatException,
    );
  });
}
