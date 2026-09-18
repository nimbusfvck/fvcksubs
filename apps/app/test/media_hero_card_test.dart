import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_app/widgets/media_hero_card.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';

void main() {
  const item = VideoItemV2(
    ref: MediaRef(extensionId: 'movies', providerId: 'catalog', id: 'hero'),
    title: 'Hero',
    artwork: Artwork(
      portrait: ImageRef('https://image.example/poster.jpg'),
      landscape: ImageRef('https://image.example/backdrop.jpg'),
    ),
  );

  Future<void> pumpHero(
    WidgetTester tester,
    Size size, {
    bool rotateBackdrops = true,
    Object? heroTag,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: size),
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: MediaHeroCard(
              item: item,
              rotateBackdrops: rotateBackdrops,
              heroTag: heroTag,
              foreground: SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('large-screen heroes prefer landscape artwork', (tester) async {
    await pumpHero(tester, const Size(1000, 600));

    expect(
      tester
          .widget<CachedNetworkImage>(find.byType(CachedNetworkImage))
          .imageUrl,
      'https://image.example/backdrop.jpg',
    );
  });

  testWidgets('shared heroes participate in iOS back-swipe transitions', (
    tester,
  ) async {
    await pumpHero(tester, const Size(390, 844), heroTag: 'hero');

    final hero = tester.widget<Hero>(find.byType(Hero));
    expect(hero.transitionOnUserGestures, isTrue);
    expect(hero.flightShuttleBuilder, isNotNull);
  });

  testWidgets('large-screen heroes keep landscape artwork when fixed', (
    tester,
  ) async {
    await pumpHero(tester, const Size(1000, 600), rotateBackdrops: false);

    expect(
      tester
          .widget<CachedNetworkImage>(find.byType(CachedNetworkImage))
          .imageUrl,
      'https://image.example/backdrop.jpg',
    );
  });

  testWidgets('narrow heroes prefer portrait artwork', (tester) async {
    await pumpHero(tester, const Size(390, 844));

    expect(
      tester
          .widget<CachedNetworkImage>(find.byType(CachedNetworkImage))
          .imageUrl,
      'https://image.example/poster.jpg',
    );
  });
}
