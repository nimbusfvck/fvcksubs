import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_app/catalog/catalog_cache.dart';
import 'package:fvcksubs_app/home/featured_controller.dart';
import 'package:fvcksubs_app/catalog/plugin_controller.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';

import 'support/harness.dart';

void main() {
  final now = DateTime.utc(2026, 8, 20, 12);

  test('keeps editorial items ahead of one top-rated event from today', () {
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
        rating: 8,
      ),
      _event(
        'live',
        'Live now',
        ScheduleState.live,
        startsAt: now.subtract(const Duration(minutes: 10)),
        rating: 10,
      ),
    ];

    final featured = FeaturedAlgorithm.select(items, maxItems: 6, now: now);

    expect(featured.map((item) => item.item.title), <String>[
      'Editorial video',
      'Editorial series',
      'Live now',
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

  test(
    'selects the highest-rated event from today, whether live or scheduled',
    () {
      final featured = FeaturedAlgorithm.select(
        [
          _event(
            'tomorrow',
            'Tomorrow',
            ScheduleState.scheduled,
            startsAt: now.add(const Duration(days: 1)),
            rating: 10,
          ),
          _event(
            'today',
            'Today',
            ScheduleState.scheduled,
            startsAt: now.add(const Duration(hours: 1)),
            rating: 8,
          ),
        ],
        maxItems: 1,
        now: now,
      );

      expect(featured.single.item.title, 'Today');
    },
  );

  test('top-rated live event outranks an unrated event from today', () {
    final featured = FeaturedAlgorithm.select(
      [
        _event(
          'ordinary-live',
          'Ordinary live',
          ScheduleState.scheduled,
          startsAt: now.add(const Duration(hours: 1)),
        ),
        _event(
          'top-live',
          'Top club live',
          ScheduleState.live,
          startsAt: now.subtract(const Duration(minutes: 20)),
          rating: 10,
        ),
      ],
      maxItems: 1,
      now: now,
    );

    expect(featured.single.item.title, 'Top club live');
  });

  test('top-rated upcoming event outranks an earlier unrated event', () {
    final featured = FeaturedAlgorithm.select(
      [
        _event(
          'ordinary-upcoming',
          'Ordinary upcoming',
          ScheduleState.scheduled,
          startsAt: now.add(const Duration(hours: 1)),
        ),
        _event(
          'top-upcoming',
          'Top club upcoming',
          ScheduleState.scheduled,
          startsAt: now.add(const Duration(hours: 2)),
          rating: 10,
        ),
      ],
      maxItems: 1,
      now: now,
    );

    expect(featured.single.item.title, 'Top club upcoming');
  });

  test('category surfaces can feature multiple events from today', () {
    final featured = FeaturedAlgorithm.select(
      [
        _event(
          'first',
          'First match',
          ScheduleState.scheduled,
          startsAt: now.add(const Duration(hours: 1)),
          rating: 8,
        ),
        _event(
          'second',
          'Second match',
          ScheduleState.live,
          startsAt: now.subtract(const Duration(minutes: 10)),
          rating: 10,
        ),
        _event(
          'third',
          'Third match',
          ScheduleState.scheduled,
          startsAt: now.add(const Duration(hours: 2)),
          rating: 7,
        ),
      ],
      maxItems: 3,
      now: now,
      allowMultipleEvents: true,
    );

    expect(featured, hasLength(3));
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

  test('keeps today events that can use generated artwork', () {
    final featured = FeaturedAlgorithm.select([
      _event(
        'live-no-artwork',
        'Live without artwork',
        ScheduleState.live,
        startsAt: now.subtract(const Duration(minutes: 5)),
        artwork: null,
      ),
    ], now: now);

    expect(featured.single.item.title, 'Live without artwork');
  });

  test('does not feature channels', () {
    const channel = VersionedMediaItem(
      item: ChannelItemV2(
        ref: MediaRef(
          extensionId: 'test',
          providerId: 'test.p',
          id: 'channel-no-artwork',
        ),
        title: 'Channel without artwork',
      ),
    );

    final featured = FeaturedAlgorithm.select([channel], now: now);

    expect(featured, isEmpty);
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

  test(
    'loads only Home all catalogs and waits before publishing the Hero',
    () async {
      final home = FakeExtension(
        id: 'home',
        categories: const ['all'],
        catalogDelay: const Duration(milliseconds: 40),
        items: [_video('home-item', 'Home item', rating: 8).item],
      );
      final movies = FakeExtension(
        id: 'movies',
        categories: const ['movie'],
        items: [_video('movie-item', 'Movie item', rating: 8).item],
      );
      final controller = FeaturedController(
        registry: ExtensionRegistry([home, movies]),
        catalogCache: CatalogCache(),
        pluginController: PluginController(store: FakePluginSelectionStore()),
      );

      final loading = controller.stream.firstWhere(
        (state) => state.status == FeaturedStatus.loading,
      );
      final load = controller.load(homeCategory: 'all');
      await loading;
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(controller.state.items, isEmpty);
      expect(controller.state.status, FeaturedStatus.loading);

      await load;
      expect(controller.state.status, FeaturedStatus.success);
      expect(controller.state.items, hasLength(1));
      expect(home.catalogCalls, 1);
      expect(movies.catalogCalls, 0);

      await controller.load(refresh: true, homeCategory: 'all');
      expect(home.catalogCalls, 2);
      expect(movies.catalogCalls, 0);
      await controller.close();
    },
  );

  test('keeps the current hero stable while a refresh is running', () async {
    final home = FakeExtension(
      id: 'home',
      categories: const ['all'],
      catalogDelay: const Duration(milliseconds: 100),
      items: [_video('home-item', 'Home item', rating: 8).item],
    );
    final controller = FeaturedController(
      registry: ExtensionRegistry([home]),
      catalogCache: CatalogCache(),
      pluginController: PluginController(store: FakePluginSelectionStore()),
    );
    addTearDown(controller.close);

    await controller.load(homeCategory: 'all');
    expect(controller.state.items, hasLength(1));

    final refreshStates = <FeaturedState>[];
    final refreshCompleted = Completer<void>();
    final subscription = controller.stream.listen((state) {
      refreshStates.add(state);
      if (state.status == FeaturedStatus.success &&
          !refreshCompleted.isCompleted) {
        refreshCompleted.complete();
      }
    });
    addTearDown(subscription.cancel);

    await controller.load(refresh: true, homeCategory: 'all');
    await refreshCompleted.future.timeout(const Duration(seconds: 1));

    expect(refreshStates, hasLength(1));
    expect(refreshStates.single.status, FeaturedStatus.success);
    expect(refreshStates.single.items, hasLength(1));
    expect(controller.state.items, hasLength(1));
  });

  test('queues a refresh instead of overlapping an active load', () async {
    final extension = FakeExtension(
      id: 'slow',
      categories: const ['all'],
      catalogDelay: const Duration(milliseconds: 40),
      items: [_video('item', 'Item', rating: 8).item],
    );
    final controller = FeaturedController(
      registry: ExtensionRegistry([extension]),
      catalogCache: CatalogCache(),
      pluginController: PluginController(store: FakePluginSelectionStore()),
    );
    addTearDown(controller.close);

    final secondSuccess = Completer<void>();
    var successCount = 0;
    final subscription = controller.stream.listen((state) {
      if (state.status != FeaturedStatus.success) return;
      successCount++;
      if (successCount == 2 && !secondSuccess.isCompleted) {
        secondSuccess.complete();
      }
    });
    addTearDown(subscription.cancel);

    final initial = controller.load(homeCategory: 'all');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    final refresh = controller.load(refresh: true, homeCategory: 'all');

    await Future.wait([initial, refresh]);
    await secondSuccess.future.timeout(const Duration(seconds: 1));

    expect(extension.catalogCalls, 2);
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
  double? rating,
  Artwork? artwork = _artwork,
}) => VersionedMediaItem(
  item: EventItemV2(
    ref: MediaRef(extensionId: 'test', providerId: 'test.p', id: id),
    title: title,
    schedule: Schedule(startsAt: startsAt, state: state),
    rating: rating,
    artwork: artwork,
  ),
);
