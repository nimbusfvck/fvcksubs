import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_app/catalog/media_card_v2.dart';
import 'package:fvcksubs_app/catalog/media_grid_v2.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';

void main() {
  VersionedMediaItem item(String id) => VersionedMediaItem(
    item: VideoItemV2(
      ref: MediaRef(
        extensionId: 'example',
        providerId: 'example.catalog',
        id: id,
      ),
      title: id,
    ),
  );

  testWidgets('renders explicit section headings and routes the envelope', (
    tester,
  ) async {
    VersionedMediaItem? tapped;
    final first = item('First');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaGridV2(
            sections: [
              CatalogSectionV2(
                id: 'featured',
                title: 'Featured',
                items: [first, item('Second')],
              ),
            ],
            showSectionHeaders: true,
            onTap: (value) => tapped = value,
          ),
        ),
      ),
    );

    expect(find.text('Featured'), findsOneWidget);
    expect(find.text('First'), findsNWidgets(2));
    await tester.tap(find.byType(MediaCardV2).first);
    expect(tapped, same(first));
  });

  testWidgets('flat catalog cards keep year and rating metadata', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 390,
            child: MediaGridV2(
              sections: [
                const CatalogSectionV2(
                  id: 'movies',
                  title: 'Movies',
                  items: [
                    VersionedMediaItem(
                      item: VideoItemV2(
                        ref: MediaRef(
                          extensionId: 'example',
                          providerId: 'example.catalog',
                          id: 'rated',
                        ),
                        title: 'Rated movie',
                        releaseYear: 2026,
                        rating: 8.4,
                      ),
                    ),
                  ],
                ),
              ],
              onTap: (_) {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('Movies'), findsNothing);
    expect(find.textContaining('2026'), findsOneWidget);
    expect(find.textContaining('8.4'), findsOneWidget);
  });

  testWidgets('poster cards show a title below the 2:3 image', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 390,
            child: MediaGridV2(
              sections: [
                const CatalogSectionV2(
                  id: 'movies',
                  items: [
                    VersionedMediaItem(
                      item: VideoItemV2(
                        ref: MediaRef(
                          extensionId: 'example',
                          providerId: 'example.catalog',
                          id: 'poster',
                        ),
                        title: 'Poster title',
                        artwork: Artwork(
                          portrait: ImageRef('https://cdn.example/poster.jpg'),
                        ),
                        releaseYear: 2026,
                        rating: 8.4,
                      ),
                    ),
                  ],
                ),
              ],
              onTap: (_) {},
            ),
          ),
        ),
      ),
    );

    final card = find.byType(MediaCardV2);
    final frame = tester.getSize(find.byType(Hero));
    expect(frame.width / frame.height, closeTo(2 / 3, 0.001));
    expect(tester.getSize(card).height, greaterThan(frame.height));
    expect(find.text('Poster title'), findsNWidgets(2));
    expect(find.text('2026'), findsOneWidget);
    expect(find.text('★ 8.4'), findsOneWidget);
    final yearTopLeft = tester.getTopLeft(find.text('2026'));
    final posterBottom = tester.getBottomLeft(find.byType(Hero)).dy;
    expect(yearTopLeft.dy, greaterThan(posterBottom));
  });

  testWidgets(
    'two-participant event with portrait artwork keeps banner ratio',
    (tester) async {
      final event = VersionedMediaItem(
        item: EventItemV2(
          ref: const MediaRef(
            extensionId: 'football',
            providerId: 'football.catalog',
            id: 'match',
          ),
          title: 'Football match',
          schedule: Schedule(startsAt: DateTime.utc(2026, 8, 20)),
          artwork: const Artwork(
            portrait: ImageRef('https://cdn.example/football-poster.jpg'),
          ),
          participants: const [
            Participant(name: 'Home'),
            Participant(name: 'Away'),
          ],
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 640,
              height: 400,
              child: MediaGridV2(
                sections: [
                  CatalogSectionV2(id: 'football', items: [event]),
                ],
                onTap: (_) {},
              ),
            ),
          ),
        ),
      );

      expect(tester.getSize(find.byType(MediaCardV2)).height, 172);
    },
  );
}
