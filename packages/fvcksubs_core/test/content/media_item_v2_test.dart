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
      releaseYear: 2026,
      rating: 8.7,
      artwork: Artwork(
        portrait: ImageRef('https://cdn.example/poster.jpg'),
        landscape: ImageRef('https://cdn.example/backdrop.jpg'),
      ),
    );

    expect(MediaItemV2.fromJson(item.toJson()), item);
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
