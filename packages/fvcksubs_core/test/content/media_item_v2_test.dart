import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:test/test.dart';

void main() {
  const ref = MediaRef(
    extensionId: 'example',
    providerId: 'example.catalog',
    id: 'item-1',
  );

  test('video round-trips structured display metadata and artwork', () {
    const item = VideoItemV2(
      ref: ref,
      title: 'Standalone video',
      subtitle: 'Drama',
      tags: ['dracin', 'dramaverse'],
      releaseYear: 2026,
      rating: 8.7,
      imdbId: 'tt1234567',
      ratings: [
        const MediaRating(
          source: 'imdb',
          score: 8.7,
          scale: 10,
          votes: 1234,
          icon: ImageRef('https://cdn.example/imdb.svg'),
        ),
      ],
      artwork: Artwork(
        portrait: ImageRef('https://cdn.example/poster.jpg'),
        landscape: ImageRef('https://cdn.example/backdrop.jpg'),
        backdrops: [
          ImageRef('https://cdn.example/backdrop-2.jpg'),
          ImageRef('https://cdn.example/backdrop-3.jpg'),
        ],
      ),
    );

    expect(MediaItemV2.fromJson(item.toJson()), item);
  });

  test('rating contract validates score, scale, votes, and icon', () {
    final rating = MediaRating.fromJson({
      'source': 'rottenTomatoes',
      'score': 86,
      'scale': 100,
      'kind': 'critic',
      'icon': {'url': 'https://cdn.example/rt.svg'},
    });

    expect(rating.score, 86);
    expect(rating.scale, 100);
    expect(rating.kind, 'critic');
    expect(rating.icon, const ImageRef('https://cdn.example/rt.svg'));
    expect(
      () => MediaRating.fromJson({'source': 'imdb', 'score': 11, 'scale': 10}),
      throwsFormatException,
    );
  });

  test('IMDb identity rejects malformed identifiers', () {
    expect(
      () => MediaItemV2.fromJson({
        'ref': ref.toJson(),
        'kind': 'video',
        'title': 'Invalid IMDb id',
        'imdbId': 'movie-1',
      }),
      throwsFormatException,
    );
  });

  test('item tags require non-empty strings', () {
    final item = MediaItemV2.fromJson({
      'ref': ref.toJson(),
      'kind': 'video',
      'title': 'Tagged video',
      'tags': [' dracin ', 'storyreel'],
    });

    expect(item.tags, ['dracin', 'storyreel']);
    expect(item.toJson()['tags'], ['dracin', 'storyreel']);
    expect(
      () => MediaItemV2.fromJson({
        'ref': ref.toJson(),
        'kind': 'video',
        'title': 'Invalid tags',
        'tags': [''],
      }),
      throwsFormatException,
    );
  });

  test('common display metadata rejects invalid values', () {
    expect(
      () => MediaItemV2.fromJson({
        'ref': ref.toJson(),
        'kind': 'video',
        'title': 'Invalid year',
        'releaseYear': 0,
      }),
      throwsFormatException,
    );
    expect(
      () => MediaItemV2.fromJson({
        'ref': ref.toJson(),
        'kind': 'video',
        'title': 'Invalid rating',
        'rating': -1,
      }),
      throwsFormatException,
    );
  });

  test('event requires a UTC schedule and accepts participants', () {
    final item = MediaItemV2.fromJson({
      'ref': ref.toJson(),
      'kind': 'event',
      'title': 'Main event',
      'schedule': {'startsAt': '2026-08-19T12:30:00Z', 'state': 'scheduled'},
      'participants': [
        {'name': 'Side A'},
        {'name': 'Side B'},
      ],
    });

    expect(item, isA<EventItemV2>());
    expect((item as EventItemV2).participants, hasLength(2));
    expect(item.schedule.startsAt, DateTime.utc(2026, 8, 19, 12, 30));
  });

  test('event schedule round-trips an endsAt timestamp', () {
    final item =
        MediaItemV2.fromJson({
              'ref': ref.toJson(),
              'kind': 'event',
              'title': 'Timed event',
              'schedule': {
                'startsAt': '2026-08-19T12:30:00Z',
                'endsAt': '2026-08-19T14:45:00Z',
                'state': 'scheduled',
              },
            })
            as EventItemV2;

    expect(item.schedule.endsAt, DateTime.utc(2026, 8, 19, 14, 45));
    expect(MediaItemV2.fromJson(item.toJson()), item);
  });

  test('event schedule rejects an end that is not after its start', () {
    expect(
      () => MediaItemV2.fromJson({
        'ref': ref.toJson(),
        'kind': 'event',
        'title': 'Invalid timed event',
        'schedule': {
          'startsAt': '2026-08-19T12:30:00Z',
          'endsAt': '2026-08-19T12:30:00Z',
        },
      }),
      throwsFormatException,
    );
  });

  test('event branding round-trips with a logo and competition colors', () {
    final item = EventItemV2(
      ref: ref,
      title: 'Branded event',
      schedule: Schedule(startsAt: DateTime.utc(2026, 8, 19, 12, 30)),
      branding: EventBranding(
        logo: ImageRef('https://cdn.example/competition.svg'),
        primaryColor: '#37003C',
        secondaryColor: '#00FF87',
      ),
    );

    expect(MediaItemV2.fromJson(item.toJson()), item);
  });

  test('event branding validates colors and requires useful data', () {
    final base = {
      'ref': ref.toJson(),
      'kind': 'event',
      'title': 'Invalid branding',
      'schedule': {'startsAt': '2026-08-19T12:30:00Z'},
    };

    expect(
      () => MediaItemV2.fromJson({
        ...base,
        'branding': {'primaryColor': 'purple'},
      }),
      throwsFormatException,
    );
    expect(
      () => MediaItemV2.fromJson({...base, 'branding': {}}),
      throwsFormatException,
    );
  });

  test('video rejects event-only fields', () {
    expect(
      () => MediaItemV2.fromJson({
        'ref': ref.toJson(),
        'kind': 'video',
        'title': 'Invalid video',
        'schedule': {'startsAt': '2026-08-19T12:30:00Z'},
      }),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('unsupported field "schedule"'),
        ),
      ),
    );
  });

  test('event rejects a non-UTC timestamp', () {
    expect(
      () => MediaItemV2.fromJson({
        'ref': ref.toJson(),
        'kind': 'event',
        'title': 'Invalid event',
        'schedule': {'startsAt': '2026-08-19T19:30:00+07:00'},
      }),
      throwsFormatException,
    );
  });

  test('episode has its own ref and typed parent context', () {
    const item = EpisodeItemV2(
      ref: MediaRef(
        extensionId: 'example',
        providerId: 'example.catalog',
        id: 'episode-4',
      ),
      title: 'Episode four',
      episode: EpisodeIdentity(
        parentRef: ref,
        groupId: 'volume-a',
        position: 4,
        absoluteEpisode: 62,
      ),
    );

    final decoded = MediaItemV2.fromJson(item.toJson()) as EpisodeItemV2;
    expect(decoded, item);
    expect(decoded.ref, isNot(decoded.episode.parentRef));
  });

  test('episode position must be positive', () {
    expect(
      () => MediaItemV2.fromJson({
        'ref': ref.toJson(),
        'kind': 'episode',
        'title': 'Invalid episode',
        'episode': {
          'parentRef': ref.toJson(),
          'groupId': 'group-a',
          'position': 0,
        },
      }),
      throwsFormatException,
    );
  });

  test('an episode carries the air date the guide gave it', () {
    // The stream role matches long-running series on this: the guide is not
    // reachable from inside sources(), so the date has to ride the item.
    final item = EpisodeItemV2(
      ref: ref,
      title: 'Episode 5',
      subtitle: 'A Series',
      episode: const EpisodeIdentity(
        parentRef: MediaRef(
          extensionId: 'example',
          providerId: 'example.catalog',
          id: 'series-1',
        ),
        groupId: 'season:1',
        position: 5,
      ),
      availableAt: DateTime.utc(2026, 8, 22, 16, 10),
    );

    final decoded = MediaItemV2.fromJson(item.toJson()) as EpisodeItemV2;
    expect(decoded, item);
    expect(decoded.availableAt, DateTime.utc(2026, 8, 22, 16, 10));
    expect(item.toJson()['availableAt'], '2026-08-22T16:10:00.000Z');
  });

  test('an episode air date must be a UTC timestamp', () {
    Object? decode(Object? availableAt) => MediaItemV2.fromJson({
      'ref': ref.toJson(),
      'kind': 'episode',
      'title': 'Episode 5',
      'episode': {
        'parentRef': ref.toJson(),
        'groupId': 'season:1',
        'position': 5,
      },
      'availableAt': availableAt,
    });

    // A local-offset timestamp would land on the wrong day for anyone east
    // or west of the extension that wrote it.
    expect(() => decode('2026-08-22T16:10:00+07:00'), throwsFormatException);
    expect(() => decode('not a date'), throwsFormatException);
    expect((decode(null) as EpisodeItemV2).availableAt, isNull);
  });

  test('artwork rejects relative URLs and empty objects', () {
    expect(() => Artwork.fromJson(const {}), throwsFormatException);
    expect(
      () => Artwork.fromJson(const {
        'portrait': {'url': '/poster.jpg'},
      }),
      throwsFormatException,
    );
  });
}
