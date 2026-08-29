import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_app/catalog/generated_banner.dart';
import 'package:fvcksubs_app/home/featured_hero.dart';
import 'package:fvcksubs_app/player/widgets/stream_player.dart';
import 'package:fvcksubs_app/theme/tokens.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';

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
      const Size(50, 50),
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

    await tester.drag(find.byType(PageView), const Offset(-300, 0));
    await tester.pumpAndSettle();

    expect(find.text('Second event'), findsOneWidget);
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
    expect(find.byType(BetterPlayerView), findsOneWidget);

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

    expect(find.byType(BetterPlayerView), findsNothing);
    expect(find.byKey(const Key('featured-title-text')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
