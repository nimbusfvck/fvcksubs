import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_app/home/featured_controller.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';

void main() {
  final now = DateTime.utc(2026, 8, 20, 12);

  test('fills featured slots with live, editorial, new, and top items', () {
    final items = [
      _video('editorial-video', 'Editorial video', rating: 6),
      _series('editorial-series', 'Editorial series', rating: 6),
      _video('new-video', 'New video', rating: 7, releaseYear: 2026),
      _series('top-series', 'Top series', rating: 9),
      _event(
        'upcoming',
        'Upcoming',
        ScheduleState.scheduled,
        startsAt: now.add(const Duration(hours: 2)),
      ),
      _event(
        'live',
        'Live now',
        ScheduleState.live,
        startsAt: now.subtract(const Duration(minutes: 10)),
      ),
    ];

    final featured = FeaturedAlgorithm.select(items, maxItems: 6, now: now);

    expect(featured.map((item) => item.item.title), <String>[
      'Live now',
      'Editorial video',
      'Editorial series',
      'Upcoming',
      'New video',
      'Top series',
    ]);
  });

  test('uses extension display order as the editorial signal', () {
    final editorial = _video('editorial', 'Editorial', rating: 7);
    final higherRated = _video('higher', 'Higher rated', rating: 9);

    final featured = FeaturedAlgorithm.select(
      [editorial, higherRated],
      maxItems: 1,
      now: now,
    );

    expect(featured.single.item.title, 'Editorial');
  });

  test('keeps section order when selecting from catalog pages', () {
    final page = VersionedCatalogPage(
      sections: [
        CatalogSectionV2(
          id: 'primary',
          items: [_video('primary', 'Primary', rating: 7)],
        ),
        CatalogSectionV2(
          id: 'secondary',
          items: [_video('secondary', 'Secondary', rating: 10)],
        ),
      ],
    );

    final featured = FeaturedAlgorithm.selectPages(
      [page],
      maxItems: 1,
      now: now,
    );

    expect(featured.single.item.title, 'Primary');
  });

  test('selects the nearest event within the upcoming window', () {
    final featured = FeaturedAlgorithm.select(
      [
        _event(
          'later',
          'Later',
          ScheduleState.scheduled,
          startsAt: now.add(const Duration(hours: 20)),
        ),
        _event(
          'next',
          'Next',
          ScheduleState.scheduled,
          startsAt: now.add(const Duration(hours: 1)),
        ),
      ],
      maxItems: 1,
      now: now,
    );

    expect(featured.single.item.title, 'Next');
  });

  test('excludes ended events and items without usable hero artwork', () {
    final featured = FeaturedAlgorithm.select([
      _event(
        'ended',
        'Ended',
        ScheduleState.ended,
        startsAt: now.subtract(const Duration(hours: 1)),
      ),
      _video('no-artwork', 'No artwork', rating: 10, artwork: null),
      _video('eligible', 'Eligible', rating: 1),
    ], now: now);

    expect(featured.map((item) => item.item.title), ['Eligible']);
  });

  test('relaxes kind limits when only one kind is available', () {
    final featured = FeaturedAlgorithm.select(
      [
        _video('one', 'One', rating: 8),
        _video('two', 'Two', rating: 7),
        _video('three', 'Three', rating: 6),
      ],
      maxItems: 3,
      now: now,
    );

    expect(featured, hasLength(3));
  });

  test('deduplicates by opaque media reference', () {
    final item = _video('same', 'First', rating: 5);
    final duplicate = _video('same', 'Second', rating: 10);

    final featured = FeaturedAlgorithm.select([item, duplicate], now: now);

    expect(featured, hasLength(1));
    expect(featured.single.item.title, 'Second');
  });
}

const _artwork = Artwork(
  portrait: ImageRef('https://cdn.example/poster.jpg'),
  landscape: ImageRef('https://cdn.example/backdrop.jpg'),
);

VersionedMediaItem _video(
  String id,
  String title, {
  required double rating,
  int? releaseYear,
  Artwork? artwork = _artwork,
}) => VersionedMediaItem(
  item: VideoItemV2(
    ref: MediaRef(extensionId: 'test', providerId: 'test.p', id: id),
    title: title,
    rating: rating,
    releaseYear: releaseYear,
    artwork: artwork,
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

VersionedMediaItem _event(
  String id,
  String title,
  ScheduleState state, {
  required DateTime startsAt,
}) => VersionedMediaItem(
  item: EventItemV2(
    ref: MediaRef(extensionId: 'test', providerId: 'test.p', id: id),
    title: title,
    schedule: Schedule(startsAt: startsAt, state: state),
    artwork: _artwork,
  ),
);
