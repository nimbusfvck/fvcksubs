import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_app/catalog/generated_banner.dart';
import 'package:fvcksubs_app/home/featured_hero.dart';
import 'package:fvcksubs_app/library/library_controller.dart';
import 'package:fvcksubs_app/player/state/picture_in_picture_session.dart';
import 'package:fvcksubs_app/player/widgets/video_player_view.dart';
import 'package:fvcksubs_app/theme/tokens.dart';
import 'package:fvcksubs_app/widgets/media_hero_flexible_space.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';
import 'package:fvcksubs_storage/fvcksubs_storage.dart';

import 'support/harness.dart';

void main() {
  testWidgets('video artwork logo replaces the featured text title', (
    tester,
  ) async {
    const logoUrl = 'https://image.example/title-logo.png';
    const item = VersionedMediaItem(
      item: VideoItemV2(
        ref: MediaRef(
          extensionId: 'movie',
          providerId: 'movie.catalog',
          id: 'with-logo',
        ),
        title: 'Movie title',
        artwork: Artwork(
          portrait: ImageRef('https://image.example/poster.jpg'),
          logo: ImageRef(logoUrl),
        ),
      ),
    );

    await tester.pumpWidget(
      wrapApp(
        child: const SizedBox(
          width: 390,
          height: 560,
          child: FeaturedHero(items: [item]),
        ),
        registry: ExtensionRegistry([]),
      ),
    );
    await tester.pump();

    final logo = tester.widget<CachedNetworkImage>(
      find.byKey(const Key('featured-title-logo')),
    );
    expect(logo.imageUrl, logoUrl);
    expect(logo.fit, BoxFit.contain);
    expect(logo.fadeInDuration, const Duration(milliseconds: 320));
    expect(tester.takeException(), isNull);
  });

  testWidgets('text title stays on one line at narrow width', (tester) async {
    final item = VersionedMediaItem(
      item: EventItemV2(
        ref: const MediaRef(
          extensionId: 'live',
          providerId: 'live.catalog',
          id: 'long-title',
        ),
        title: 'A very long live event title that must not wrap',
        schedule: Schedule(
          startsAt: DateTime.utc(2026, 8, 20),
          state: ScheduleState.live,
        ),
      ),
    );

    await tester.pumpWidget(
      wrapApp(
        child: SizedBox(
          width: 240,
          height: 560,
          child: FeaturedHero(items: [item]),
        ),
        registry: ExtensionRegistry([]),
      ),
    );
    await tester.pump();

    final title = tester.widget<Text>(
      find.byKey(const Key('featured-title-text')),
    );
    expect(title.maxLines, 1);
    expect(title.overflow, TextOverflow.ellipsis);
    expect(title.style?.fontSize, 22);
    expect(tester.takeException(), isNull);
  });

  testWidgets('large featured summary and actions align to the left', (
    tester,
  ) async {
    const item = VersionedMediaItem(
      item: VideoItemV2(
        ref: MediaRef(
          extensionId: 'movie',
          providerId: 'movie.catalog',
          id: 'large-screen',
        ),
        title: 'Large screen movie',
      ),
    );

    await tester.pumpWidget(
      wrapApp(
        child: MediaQuery(
          data: const MediaQueryData(size: Size(1000, 560)),
          child: const SizedBox(
            width: 1000,
            height: 560,
            child: FeaturedHero(items: [item]),
          ),
        ),
        registry: ExtensionRegistry([]),
      ),
    );
    await tester.pump();

    expect(
      tester.getTopLeft(find.byKey(const Key('featured-title-text'))).dx,
      closeTo(24, 1),
    );
    expect(
      tester.getTopLeft(find.byKey(const Key('featured-play'))).dx,
      closeTo(24, 1),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('featured video with progress shows Continue Watching', (
    tester,
  ) async {
    const item = VersionedMediaItem(
      item: VideoItemV2(
        ref: MediaRef(
          extensionId: 'movie',
          providerId: 'movie.catalog',
          id: 'in-progress',
        ),
        title: 'In-progress movie',
      ),
    );
    final library = LibraryController(
      store: _MemoryLibraryStore(),
      initial: {
        UserMediaState.keyFor(item.item.ref): UserMediaState(
          item: item.item,
          progress: const Duration(minutes: 3),
        ),
      },
    );

    await tester.pumpWidget(
      wrapApp(
        child: const SizedBox(
          width: 390,
          height: 560,
          child: FeaturedHero(items: [item]),
        ),
        registry: ExtensionRegistry([]),
        libraryController: library,
      ),
    );
    await tester.pump();

    expect(find.text('Continue Watching'), findsOneWidget);
    expect(find.text('Watch Now'), findsNothing);
  });

  testWidgets('featured event uses the shared banner layout', (tester) async {
    final item = VersionedMediaItem(
      item: EventItemV2(
        ref: const MediaRef(
          extensionId: 'live',
          providerId: 'live.catalog',
          id: 'two-logos',
        ),
        title: 'Two-logo event',
        schedule: Schedule(
          startsAt: DateTime.utc(2026, 8, 20),
          state: ScheduleState.live,
        ),
        participants: const [
          Participant(
            name: 'Home',
            logo: ImageRef('https://image.example/home.png'),
          ),
          Participant(
            name: 'Away',
            logo: ImageRef('https://image.example/away.png'),
          ),
        ],
        branding: const EventBranding(
          logo: ImageRef('https://image.example/league.png'),
        ),
      ),
    );

    await tester.pumpWidget(
      wrapApp(
        child: SizedBox(
          width: 390,
          height: 560,
          child: FeaturedHero(items: [item]),
        ),
        registry: ExtensionRegistry([]),
      ),
    );
    await tester.pump();

    expect(find.byType(GeneratedBanner), findsOneWidget);
    expect(find.byKey(const ValueKey('live-identity-logo-0')), findsNothing);
    expect(find.byType(CachedNetworkImage), findsNWidgets(2));
    expect(
      tester.getSize(find.byType(CachedNetworkImage).first),
      const Size(64, 64),
    );
    for (final logo in tester.widgetList<CachedNetworkImage>(
      find.byType(CachedNetworkImage),
    )) {
      expect(logo.filterQuality, FilterQuality.high);
    }
    final title = tester.widget<Text>(
      find.byKey(const Key('featured-title-text')),
    );
    final titleSpan = title.textSpan! as TextSpan;
    expect(titleSpan.toPlainText(), 'HOME VS AWAY');
    expect(titleSpan.children, hasLength(3));
    expect(
      (titleSpan.children![1] as TextSpan).style?.color,
      isNot(AppColors.onDark),
    );
    expect(find.text('Two-logo event'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long featured event title breaks before VS', (tester) async {
    final item = VersionedMediaItem(
      item: EventItemV2(
        ref: const MediaRef(
          extensionId: 'live',
          providerId: 'live.catalog',
          id: 'long-matchup-title',
        ),
        title: 'Long matchup title',
        schedule: Schedule(
          startsAt: DateTime.utc(2026, 8, 20),
          state: ScheduleState.live,
        ),
        participants: const [
          Participant(name: 'Home Team With A Long Name'),
          Participant(name: 'Away Team With A Long Name'),
        ],
      ),
    );

    await tester.pumpWidget(
      wrapApp(
        child: SizedBox(
          width: 240,
          height: 560,
          child: FeaturedHero(items: [item]),
        ),
        registry: ExtensionRegistry([]),
      ),
    );
    await tester.pump();

    final title = tester.widget<Text>(
      find.byKey(const Key('featured-title-text')),
    );
    expect(title.maxLines, 2);
    expect(
      (title.textSpan! as TextSpan).toPlainText(),
      'HOME TEAM WITH A LONG NAME\nVS AWAY TEAM WITH A LONG NAME',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('page indicator is centered at the bottom', (tester) async {
    final items = [
      VersionedMediaItem(
        item: EventItemV2(
          ref: const MediaRef(
            extensionId: 'live',
            providerId: 'live.catalog',
            id: 'first',
          ),
          title: 'First event',
          schedule: Schedule(
            startsAt: DateTime.utc(2026, 8, 20),
            state: ScheduleState.live,
          ),
        ),
      ),
      VersionedMediaItem(
        item: EventItemV2(
          ref: const MediaRef(
            extensionId: 'live',
            providerId: 'live.catalog',
            id: 'second',
          ),
          title: 'Second event',
          schedule: Schedule(
            startsAt: DateTime.utc(2026, 8, 20),
            state: ScheduleState.live,
          ),
        ),
      ),
    ];

    await tester.pumpWidget(
      wrapApp(
        child: SizedBox(
          width: 390,
          height: 560,
          child: FeaturedHero(items: items),
        ),
        registry: ExtensionRegistry([]),
      ),
    );
    await tester.pump();

    final indicator = tester.widget<Positioned>(
      find.byKey(const Key('featured-page-indicator')),
    );
    expect(indicator.left, 0);
    expect(indicator.right, 0);
    expect(indicator.bottom, isNotNull);
    expect(find.byType(AnimatedContainer), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('items without trailers auto-advance after eight seconds', (
    tester,
  ) async {
    const items = [
      VersionedMediaItem(
        item: VideoItemV2(
          ref: MediaRef(extensionId: 'missing', providerId: 'catalog', id: '1'),
          title: 'First fallback item',
        ),
      ),
      VersionedMediaItem(
        item: VideoItemV2(
          ref: MediaRef(extensionId: 'missing', providerId: 'catalog', id: '2'),
          title: 'Second fallback item',
        ),
      ),
    ];
    await tester.pumpWidget(
      wrapApp(
        child: const SizedBox(
          width: 390,
          height: 560,
          child: FeaturedHero(items: items),
        ),
        registry: ExtensionRegistry([]),
      ),
    );
    await tester.pump();
    expect(find.text('First fallback item'), findsOneWidget);

    await tester.pump(const Duration(seconds: 8));
    // The active fallback progress animation intentionally never settles.
    for (var index = 0; index < 10; index++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('Second fallback item'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pauses auto-slide once less than half of the hero is visible', (
    tester,
  ) async {
    const items = [
      VersionedMediaItem(
        item: VideoItemV2(
          ref: MediaRef(extensionId: 'missing', providerId: 'catalog', id: '1'),
          title: 'First visibility item',
        ),
      ),
      VersionedMediaItem(
        item: VideoItemV2(
          ref: MediaRef(extensionId: 'missing', providerId: 'catalog', id: '2'),
          title: 'Second visibility item',
        ),
      ),
    ];

    Widget buildHero(double collapse) => wrapApp(
      child: MediaHeroCollapseScope(
        collapse: collapse,
        maxCollapse: 400,
        child: const SizedBox(
          width: 390,
          height: 560,
          child: FeaturedHero(items: items),
        ),
      ),
      registry: ExtensionRegistry([]),
    );

    await tester.pumpWidget(buildHero(201));
    await tester.pump();
    await tester.pump(const Duration(seconds: 9));

    expect(find.text('First visibility item'), findsOneWidget);
    expect(find.text('Second visibility item'), findsNothing);

    await tester.pumpWidget(buildHero(100));
    await tester.pump();
    await tester.pump(const Duration(seconds: 8));
    for (var index = 0; index < 10; index++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('Second visibility item'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an attached player pauses featured auto-slide', (tester) async {
    final items = [
      VersionedMediaItem(
        item: EventItemV2(
          ref: const MediaRef(
            extensionId: 'live',
            providerId: 'live.p',
            id: 'one',
          ),
          title: 'First live event',
          schedule: Schedule(
            startsAt: DateTime.utc(2026, 8, 20),
            state: ScheduleState.live,
          ),
        ),
      ),
      VersionedMediaItem(
        item: EventItemV2(
          ref: const MediaRef(
            extensionId: 'live',
            providerId: 'live.p',
            id: 'two',
          ),
          title: 'Second live event',
          schedule: Schedule(
            startsAt: DateTime.utc(2026, 8, 20),
            state: ScheduleState.live,
          ),
        ),
      ),
    ];
    final session = PictureInPictureSession();
    addTearDown(session.dispose);

    await tester.pumpWidget(
      wrapApp(
        child: SizedBox(
          width: 390,
          height: 560,
          child: FeaturedHero(items: items),
        ),
        registry: ExtensionRegistry([]),
        pictureInPictureSession: session,
      ),
    );
    await tester.pump();
    expect(find.text('First live event'), findsOneWidget);

    session.attach(const SizedBox());
    await tester.pump();
    await tester.pump(const Duration(seconds: 9));

    expect(find.text('First live event'), findsOneWidget);
    expect(find.text('Second live event'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('horizontal drag moves to the next featured item', (
    tester,
  ) async {
    final items = [
      VersionedMediaItem(
        item: EventItemV2(
          ref: const MediaRef(
            extensionId: 'live',
            providerId: 'live.catalog',
            id: 'first-drag',
          ),
          title: 'First event',
          schedule: Schedule(
            startsAt: DateTime.utc(2026, 8, 20),
            state: ScheduleState.live,
          ),
        ),
      ),
      VersionedMediaItem(
        item: EventItemV2(
          ref: const MediaRef(
            extensionId: 'live',
            providerId: 'live.catalog',
            id: 'second-drag',
          ),
          title: 'Second event',
          schedule: Schedule(
            startsAt: DateTime.utc(2026, 8, 20),
            state: ScheduleState.live,
          ),
        ),
      ),
    ];

    await tester.pumpWidget(
      wrapApp(
        child: SizedBox(
          width: 390,
          height: 560,
          child: FeaturedHero(items: items),
        ),
        registry: ExtensionRegistry([]),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(PageView)),
    );
    await gesture.moveBy(const Offset(-120, 0));
    await tester.pump();

    final parallaxTarget = tester.widget<Transform>(
      find.byKey(const Key('featured-parallax-target')),
    );
    final parallaxCurrent = tester.widget<Transform>(
      find.byKey(const Key('featured-parallax-current')),
    );
    expect(parallaxTarget.transform.getTranslation().x, greaterThan(0));
    expect(parallaxCurrent.transform.getTranslation().x, lessThan(0));
    expect(find.byKey(const Key('featured-edge-blur')), findsOneWidget);

    await gesture.moveBy(const Offset(-180, 0));
    await gesture.up();
    // The active fallback progress animation intentionally never settles.
    for (var index = 0; index < 10; index++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('Second event'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('swiping keeps the featured preview playing and mounted', (
    tester,
  ) async {
    const first = VersionedMediaItem(
      item: VideoItemV2(
        ref: MediaRef(extensionId: 'fake', providerId: 'fake.p', id: 'first'),
        title: 'First movie',
      ),
    );
    const second = VersionedMediaItem(
      item: VideoItemV2(
        ref: MediaRef(extensionId: 'fake', providerId: 'fake.p', id: 'second'),
        title: 'Second movie',
      ),
    );
    final extension = FakeExtension(
      metaDetail: const MediaDetailV2(
        item: VideoItemV2(
          ref: MediaRef(extensionId: 'fake', providerId: 'fake.p', id: 'first'),
          title: 'First movie',
        ),
        trailers: [
          MediaTrailer(
            title: 'Trailer',
            url: 'https://video.example/featured.mp4',
            mimeType: 'video/mp4',
          ),
        ],
      ),
    );
    await tester.pumpWidget(
      wrapApp(
        child: const SizedBox(
          width: 390,
          height: 560,
          child: FeaturedHero(items: [first, second]),
        ),
        registry: ExtensionRegistry([extension]),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(VideoPlayerView), findsOneWidget);
    expect(
      tester.widget<VideoPlayerView>(find.byType(VideoPlayerView)).playing,
      isTrue,
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(PageView)),
    );
    await gesture.moveBy(const Offset(-240, 0));
    await tester.pump();

    expect(find.text('Second movie'), findsOneWidget);
    expect(
      tester.widget<VideoPlayerView>(find.byType(VideoPlayerView)).playing,
      isTrue,
    );
    expect(find.byType(VideoPlayerView), findsOneWidget);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('Second movie'), findsOneWidget);
    expect(
      tester.widget<VideoPlayerView>(find.byType(VideoPlayerView)).playing,
      isFalse,
    );
    expect(find.byType(VideoPlayerView), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 1200));
    expect(
      tester.widget<VideoPlayerView>(find.byType(VideoPlayerView)).playing,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('progressive updates keep the active featured item visible', (
    tester,
  ) async {
    VersionedMediaItem event(String id, String title) => VersionedMediaItem(
      item: EventItemV2(
        ref: MediaRef(extensionId: 'live', providerId: 'live.catalog', id: id),
        title: title,
        schedule: Schedule(
          startsAt: DateTime.utc(2026, 8, 20),
          state: ScheduleState.live,
        ),
      ),
    );

    final first = event('first-update', 'First update');
    final second = event('second-update', 'Second update');
    final inserted = event('inserted-update', 'Inserted update');

    await tester.pumpWidget(
      wrapApp(
        child: SizedBox(
          width: 390,
          height: 560,
          child: FeaturedHero(items: [first, second]),
        ),
        registry: ExtensionRegistry([]),
      ),
    );
    await tester.drag(find.byType(PageView), const Offset(-300, 0));
    // The active fallback progress animation intentionally never settles.
    for (var index = 0; index < 10; index++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Second update'), findsOneWidget);

    await tester.pumpWidget(
      wrapApp(
        child: SizedBox(
          width: 390,
          height: 560,
          child: FeaturedHero(items: [inserted, first, second]),
        ),
        registry: ExtensionRegistry([]),
      ),
    );
    await tester.pump();

    expect(find.text('Second update'), findsOneWidget);
    expect(find.text('Inserted update'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('refreshing index zero disposes the previous trailer preview', (
    tester,
  ) async {
    const movie = VersionedMediaItem(
      item: VideoItemV2(
        ref: MediaRef(extensionId: 'fake', providerId: 'fake.p', id: 'movie'),
        title: 'Movie',
        artwork: Artwork(portrait: ImageRef('https://image.example/movie.jpg')),
      ),
    );
    final live = VersionedMediaItem(
      item: EventItemV2(
        ref: const MediaRef(
          extensionId: 'fake',
          providerId: 'fake.p',
          id: 'live',
        ),
        title: 'Live event',
        schedule: Schedule(
          startsAt: DateTime.utc(2026, 8, 26),
          state: ScheduleState.live,
        ),
      ),
    );
    final extension = FakeExtension(
      metaDetail: MediaDetailV2(
        item: movie.item,
        trailers: const [
          MediaTrailer(
            title: 'Trailer',
            url: 'https://video.example/trailer.mp4',
            mimeType: 'video/mp4',
          ),
        ],
      ),
    );
    final registry = ExtensionRegistry([extension]);
    final player = RecordingPlayer();

    await tester.pumpWidget(
      wrapApp(
        child: const SizedBox(
          width: 390,
          height: 560,
          child: FeaturedHero(items: [movie]),
        ),
        registry: registry,
        player: player,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(VideoPlayerView), findsOneWidget);

    await tester.pumpWidget(
      wrapApp(
        child: SizedBox(
          width: 390,
          height: 560,
          child: FeaturedHero(items: [live]),
        ),
        registry: registry,
        player: player,
      ),
    );
    await tester.pump();

    expect(find.byType(VideoPlayerView), findsNothing);
    expect(find.byKey(const Key('featured-title-text')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _MemoryLibraryStore implements LibraryStore {
  @override
  Future<Map<String, UserMediaState>> load() async => {};

  @override
  Future<void> save(Map<String, UserMediaState> records) async {}
}
