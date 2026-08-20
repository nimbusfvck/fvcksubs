import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_app/home/featured_controller.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';

void main() {
  test('keeps the highest-ranked item from each media kind', () {
    final items = [
      _video('movie-low', 'Movie low', rating: 4),
      _video('movie-top', 'Movie top', rating: 9),
      _series('series', 'Series', rating: 7),
      _channel('channel', 'Channel', rating: 1),
      _event('event-upcoming', 'Upcoming', ScheduleState.scheduled),
      _event('event-live', 'Live now', ScheduleState.live),
    ];

    final featured = FeaturedAlgorithm.select(items, maxItems: 4);

    expect(
      featured.map((item) => item.item.title),
      containsAll(<String>['Movie top', 'Series', 'Channel', 'Live now']),
    );
    expect(
      featured.map((item) => item.item.title),
      isNot(contains('Movie low')),
    );
  });

  test('deduplicates by opaque media reference', () {
    final item = _video('same', 'First', rating: 5);
    final duplicate = _video('same', 'Second', rating: 10);

    final featured = FeaturedAlgorithm.select([item, duplicate]);

    expect(featured, hasLength(1));
    expect(featured.single.item.title, 'Second');
  });
}

const _artwork = Artwork(
  portrait: ImageRef('https://cdn.example/poster.jpg'),
  landscape: ImageRef('https://cdn.example/backdrop.jpg'),
);

VersionedMediaItem _video(String id, String title, {required double rating}) =>
    VersionedMediaItem(
      item: VideoItemV2(
        ref: MediaRef(extensionId: 'test', providerId: 'test.p', id: id),
        title: title,
        rating: rating,
        artwork: _artwork,
      ),
    );

VersionedMediaItem _series(String id, String title, {required double rating}) =>
    VersionedMediaItem(
      item: SeriesItemV2(
        ref: MediaRef(extensionId: 'test', providerId: 'test.p', id: id),
        title: title,
        rating: rating,
        artwork: _artwork,
      ),
    );

VersionedMediaItem _channel(
  String id,
  String title, {
  required double rating,
}) => VersionedMediaItem(
  item: ChannelItemV2(
    ref: MediaRef(extensionId: 'test', providerId: 'test.p', id: id),
    title: title,
    rating: rating,
    artwork: _artwork,
  ),
);

VersionedMediaItem _event(String id, String title, ScheduleState state) =>
    VersionedMediaItem(
      item: EventItemV2(
        ref: MediaRef(extensionId: 'test', providerId: 'test.p', id: id),
        title: title,
        schedule: Schedule(startsAt: DateTime.utc(2026), state: state),
        artwork: _artwork,
      ),
    );
