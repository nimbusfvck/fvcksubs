import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:fvcksubs_app/catalog/media_card_actions.dart';
import 'package:fvcksubs_app/catalog/media_card_v2.dart';
import 'package:fvcksubs_app/catalog/generated_banner.dart';
import 'package:fvcksubs_app/library/library_controller.dart';
import 'package:fvcksubs_app/theme/tokens.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';
import 'package:fvcksubs_storage/fvcksubs_storage.dart';

import 'support/harness.dart';

void main() {
  const ref = MediaRef(
    extensionId: 'example',
    providerId: 'example.catalog',
    id: 'item',
  );

  testWidgets('video renders without event-specific data', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 172,
            child: MediaCardV2(
              item: VideoItemV2(
                ref: ref,
                title: 'Standalone video',
                artwork: Artwork(
                  portrait: ImageRef('https://cdn.example/video.jpg'),
                ),
              ),
              onTap: _noop,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Standalone video'), findsOneWidget);
    expect(find.text('LIVE'), findsNothing);
    expect(find.byType(Hero), findsOneWidget);
  });

  testWidgets('poster decode size follows the rendered card size', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(devicePixelRatio: 2),
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 172,
              child: MediaCardV2(
                item: VideoItemV2(
                  ref: ref,
                  title: 'Sized poster',
                  artwork: Artwork(
                    portrait: ImageRef('https://cdn.example/sized.jpg'),
                  ),
                ),
                onTap: _noop,
              ),
            ),
          ),
        ),
      ),
    );

    final image = tester.widget<CachedNetworkImage>(
      find.byType(CachedNetworkImage),
    );
    expect(image.memCacheWidth, 600);
    expect(image.memCacheHeight, isNotNull);
  });

  testWidgets('long press opens the favorite action without tapping', (
    tester,
  ) async {
    const item = VideoItemV2(ref: ref, title: 'Long-press video');
    final library = LibraryController(store: _MemoryLibraryStore());
    var tapped = false;
    var detailsOpened = false;

    await tester.pumpWidget(
      wrapApp(
        registry: ExtensionRegistry([]),
        libraryController: library,
        child: Builder(
          builder: (context) => SizedBox(
            width: 300,
            height: 172,
            child: MediaCardV2(
              item: item,
              onTap: () => tapped = true,
              onLongPress: () => showMediaCardActions(
                context,
                item,
                onViewDetails: () => detailsOpened = true,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.longPress(find.byType(MediaCardV2));
    await tester.pumpAndSettle();

    expect(tapped, isFalse);
    expect(find.text('Add to favorites'), findsOneWidget);

    await tester.tap(find.text('Add to favorites'));
    await tester.pumpAndSettle();

    expect(library.isFavorite(item.ref), isTrue);

    await tester.longPress(find.byType(MediaCardV2));
    await tester.pumpAndSettle();
    expect(find.text('View details'), findsOneWidget);

    await tester.tap(find.text('View details'));
    await tester.pumpAndSettle();

    expect(detailsOpened, isTrue);
  });

  testWidgets('an unreleased movie shows its release date over the poster', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 172,
            child: MediaCardV2(
              item: VideoItemV2(
                ref: ref,
                title: 'Future movie',
                releaseDate: DateTime.utc(2099, 1, 15),
              ),
              onTap: _noop,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Jan 15'), findsOneWidget);
  });

  testWidgets('rounds a rating in the card metadata', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 172,
            child: MediaCardV2(
              item: VideoItemV2(ref: ref, title: 'Rated video', rating: 8.76),
              onTap: _noop,
            ),
          ),
        ),
      ),
    );

    expect(find.text('★ 8.8'), findsOneWidget);
    final metadata = tester.widget<RichText>(
      find.byWidgetPredicate(
        (widget) => widget is RichText && widget.text.toPlainText() == '★ 8.8',
      ),
    );
    TextSpan? star;
    void findStar(InlineSpan span) {
      if (span is TextSpan) {
        if (span.text == '★') star = span;
        for (final child in span.children ?? const <InlineSpan>[]) {
          findStar(child);
        }
      }
    }

    findStar(metadata.text);
    expect(star?.style?.color, AppColors.ratingAccent);
  });

  testWidgets('video without artwork shows the shared placeholder', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 172,
            child: MediaCardV2(
              item: VideoItemV2(ref: ref, title: 'Text-only video'),
              onTap: _noop,
            ),
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.movie_outlined), findsOneWidget);
    expect(find.text('Text-only video'), findsOneWidget);
  });

  testWidgets('event renders schedule and participants', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 260,
            child: MediaCardV2(
              item: EventItemV2(
                ref: ref,
                title: 'Main event',
                schedule: Schedule(
                  startsAt: DateTime.utc(2026, 8, 20),
                  state: ScheduleState.live,
                  label: 'In progress',
                ),
                participants: const [
                  Participant(name: 'Side A'),
                  Participant(name: 'Side B'),
                ],
              ),
              onTap: _noop,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Main event'), findsOneWidget);
    expect(find.text('In progress'), findsOneWidget);
    expect(find.text('LIVE'), findsOneWidget);
  });

  testWidgets('event branding reaches the generated match banner', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 260,
            child: MediaCardV2(
              item: EventItemV2(
                ref: ref,
                title: 'Branded match',
                schedule: Schedule(startsAt: DateTime.utc(2026, 8, 20)),
                participants: const [
                  Participant(name: 'Side A'),
                  Participant(name: 'Side B'),
                ],
                branding: const EventBranding(
                  logo: ImageRef('https://cdn.example/league.svg'),
                  primaryColor: '#37003C',
                  secondaryColor: '#00FF87',
                ),
              ),
              onTap: _noop,
            ),
          ),
        ),
      ),
    );

    expect(find.byType(GeneratedBanner), findsOneWidget);
    expect(find.byType(CachedNetworkImage), findsOneWidget);
    expect(find.text('SIDE A'), findsOneWidget);
    expect(find.text('VS'), findsOneWidget);
    expect(find.text('SIDE B'), findsOneWidget);
  });

  testWidgets('two-participant event uses a banner over portrait artwork', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 260,
            child: MediaCardV2(
              item: EventItemV2(
                ref: ref,
                title: 'Sport match with poster',
                schedule: Schedule(startsAt: DateTime.utc(2026, 8, 20)),
                artwork: const Artwork(
                  portrait: ImageRef('https://cdn.example/poster.jpg'),
                ),
                participants: const [
                  Participant(name: 'Side A'),
                  Participant(name: 'Side B'),
                ],
              ),
              onTap: _noop,
            ),
          ),
        ),
      ),
    );

    expect(find.byType(GeneratedBanner), findsOneWidget);
    expect(find.byType(Hero), findsNothing);
  });

  testWidgets('narrow match banners scale their content without overflow', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 152,
            height: 86,
            child: GeneratedBanner(
              participants: [
                Participant(name: 'A very long home participant'),
                Participant(name: 'A very long away participant'),
              ],
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'an unbranded event derives a mark and does not show crest placeholders',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 260,
              child: MediaCardV2(
                item: EventItemV2(
                  ref: ref,
                  title: 'Fighter A vs Fighter B',
                  subtitle: 'Mixed Martial Arts',
                  schedule: Schedule(startsAt: DateTime.utc(2026, 8, 20)),
                  participants: const [
                    Participant(name: 'Fighter A'),
                    Participant(name: 'Fighter B'),
                  ],
                ),
                onTap: _noop,
              ),
            ),
          ),
        ),
      );

      expect(find.text('MMA'), findsOneWidget);
      expect(find.text('Mixed Martial Arts'), findsNothing);
      expect(find.byIcon(Icons.shield_outlined), findsNothing);
    },
  );

  testWidgets('single-sided event renders its landscape artwork', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 172,
            child: MediaCardV2(
              item: EventItemV2(
                ref: ref,
                title: 'Single-sided broadcast',
                schedule: Schedule(
                  startsAt: DateTime.utc(2026, 8, 20),
                  state: ScheduleState.scheduled,
                  label: '20 Aug 21:00',
                ),
                artwork: const Artwork(
                  landscape: ImageRef('https://cdn.example/event.jpg'),
                ),
              ),
              onTap: _noop,
            ),
          ),
        ),
      ),
    );

    expect(find.byType(CachedNetworkImage), findsOneWidget);
    expect(find.text('Single-sided broadcast'), findsOneWidget);
    expect(find.text('20 Aug 21:00'), findsOneWidget);
    expect(find.text('UPCOMING'), findsOneWidget);
  });

  testWidgets('single participant logo uses generated event artwork', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 172,
            child: MediaCardV2(
              item: EventItemV2(
                ref: ref,
                title: 'Single team event',
                schedule: Schedule(startsAt: DateTime.utc(2026, 8, 20)),
                participants: const [
                  Participant(
                    name: 'Single team',
                    logo: ImageRef('https://cdn.example/team.png'),
                  ),
                ],
              ),
              onTap: _noop,
            ),
          ),
        ),
      ),
    );

    expect(find.byType(GeneratedLiveArtwork), findsOneWidget);
    expect(find.byType(CachedNetworkImage), findsOneWidget);
  });
}

void _noop() {}

class _MemoryLibraryStore implements LibraryStore {
  Map<String, UserMediaState> records = {};

  @override
  Future<Map<String, UserMediaState>> load() async => records;

  @override
  Future<void> save(Map<String, UserMediaState> next) async => records = next;
}
