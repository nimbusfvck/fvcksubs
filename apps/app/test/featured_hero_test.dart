import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_app/home/featured_hero.dart';
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
    expect(title.style?.fontSize, 18);
    expect(tester.takeException(), isNull);
  });
}
