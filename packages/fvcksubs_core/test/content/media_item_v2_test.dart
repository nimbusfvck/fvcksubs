import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:test/test.dart';

void main() {
  const ref = MediaRef(
    extensionId: 'example',
    providerId: 'example.catalog',
    id: 'item-1',
  );

  test('video round-trips with orientation-aware artwork', () {
    const item = VideoItemV2(
      ref: ref,
      title: 'Standalone video',
      artwork: Artwork(
        portrait: ImageRef('https://cdn.example/poster.jpg'),
        landscape: ImageRef('https://cdn.example/backdrop.jpg'),
      ),
    );

    expect(MediaItemV2.fromJson(item.toJson()), item);
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
