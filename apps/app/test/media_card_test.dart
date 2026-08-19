import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_app/catalog/generated_banner.dart';
import 'package:fvcksubs_app/catalog/media_card.dart';
import 'package:fvcksubs_app/catalog/participant_avatar.dart';

import 'support/harness.dart';

void main() {
  group('event layout (no poster, not two-sided)', () {
    testWidgets(
      'an item without exactly two sides still shows its title normally',
      (tester) async {
        final item = fakeItem(title: 'Sports Channel', participants: const []);

        await tester.pumpWidget(
          MaterialApp(
            home: MediaCard(item: item, onTap: () {}),
          ),
        );
        await tester.pump();

        expect(find.text('Sports Channel'), findsOneWidget);
      },
    );

    testWidgets('shows the LIVE badge and statusLabel, no participants row '
        'for a single-sided item', (tester) async {
      final item = fakeItem(title: 'Sports Channel');

      await tester.pumpWidget(
        MaterialApp(
          home: MediaCard(item: item, onTap: () {}),
        ),
      );
      await tester.pump();

      expect(find.text('LIVE'), findsOneWidget);
      expect(find.text('vs'), findsNothing);
    });

    testWidgets('shows the UPCOMING badge for a scheduled single-sided item', (
      tester,
    ) async {
      final item = fakeItem(
        title: 'Sports Channel',
        status: LiveStatus.scheduled,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: MediaCard(item: item, onTap: () {}),
        ),
      );
      await tester.pump();

      expect(find.text('UPCOMING'), findsOneWidget);
      expect(find.text('LIVE'), findsNothing);
    });

    testWidgets('activating the card calls onTap', (tester) async {
      var tapped = false;
      final item = fakeItem();

      await tester.pumpWidget(
        MaterialApp(
          home: MediaCard(item: item, onTap: () => tapped = true),
        ),
      );
      await tester.tap(find.byType(MediaCard));

      expect(tapped, isTrue);
    });
  });

  group('generated banner (two-sided, no poster)', () {
    testWidgets(
      'the banner carries only crests and drawn artwork; every word the '
      'fixture has reads as card content below it',
      (tester) async {
        final item = fakeItem(
          title: 'Arsenal vs Chelsea',
          subtitle: 'Premier League',
          statusLabel: "63'",
          // Neither LIVE nor UPCOMING — the one status that puts no pill on
          // the artwork, so this test can isolate "is there any text here
          // at all" from the pill itself (covered separately below).
          status: LiveStatus.unknown,
          participants: const [
            Participant(name: 'Arsenal'),
            Participant(name: 'Chelsea'),
          ],
        );

        await tester.pumpWidget(
          MaterialApp(
            home: MediaCard(item: item, onTap: () {}),
          ),
        );
        await tester.pump();

        expect(find.byType(GeneratedBanner), findsOneWidget);

        // Artwork only — the split and sunburst are painted, so with no
        // status pill there is no text in the banner at all.
        expect(
          find.descendant(
            of: find.byType(GeneratedBanner),
            matching: find.byType(Text),
          ),
          findsNothing,
        );

        // Every word the fixture carries reads as card content below it.
        expect(find.text('Arsenal vs Chelsea'), findsOneWidget);
        expect(find.text("Premier League · 63'"), findsOneWidget);
      },
    );

    testWidgets('the LIVE pill sits on the artwork, not in the text', (
      tester,
    ) async {
      final item = fakeItem(
        participants: const [
          Participant(name: 'Arsenal'),
          Participant(name: 'Chelsea'),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: MediaCard(item: item, onTap: () {}),
        ),
      );
      await tester.pump();

      expect(
        find.descendant(
          of: find.byType(GeneratedBanner),
          matching: find.byType(LiveBadge),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a scheduled fixture gets the UPCOMING pill instead', (
      tester,
    ) async {
      final item = fakeItem(
        status: LiveStatus.scheduled,
        participants: const [
          Participant(name: 'Arsenal'),
          Participant(name: 'Chelsea'),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: MediaCard(item: item, onTap: () {}),
        ),
      );
      await tester.pump();

      expect(
        find.descendant(
          of: find.byType(GeneratedBanner),
          matching: find.byType(UpcomingBadge),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(GeneratedBanner),
          matching: find.byType(LiveBadge),
        ),
        findsNothing,
      );
    });

    testWidgets('a long pairing wraps rather than losing the opponent', (
      tester,
    ) async {
      // At grid width this used to ellipsize to "Seattle Sounders ...",
      // which hides who the match is even against.
      final item = fakeItem(
        title: 'Seattle Sounders FC vs Vancouver Whitecaps',
        participants: const [
          Participant(name: 'Seattle Sounders FC'),
          Participant(name: 'Vancouver Whitecaps'),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 180,
            height: 172,
            child: MediaCard(item: item, onTap: () {}),
          ),
        ),
      );
      await tester.pump();

      final title = tester.widget<Text>(
        find.text('Seattle Sounders FC vs Vancouver Whitecaps'),
      );
      expect(title.maxLines, 2);
      expect(tester.takeException(), isNull);
    });

    testWidgets('prefers the short names the catalog supplied', (tester) async {
      final item = fakeItem(
        title: 'Racing Santander vs Villarreal CF',
        participants: const [
          Participant(name: 'Racing Santander', shortName: 'Racing'),
          Participant(name: 'Villarreal CF', shortName: 'Villarreal'),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: MediaCard(item: item, onTap: () {}),
        ),
      );
      await tester.pump();

      expect(find.text('Racing vs Villarreal'), findsOneWidget);
      expect(find.text('Racing Santander vs Villarreal CF'), findsNothing);
    });

    testWidgets('falls back to the extension\'s own title wording', (
      tester,
    ) async {
      // With no short name anywhere, the app doesn't invent one — the
      // extension's title is printed as given.
      final item = fakeItem(
        title: 'Arsenal vs Chelsea',
        participants: const [
          Participant(name: 'Arsenal'),
          Participant(name: 'Chelsea'),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: MediaCard(item: item, onTap: () {}),
        ),
      );
      await tester.pump();

      expect(find.text('Arsenal vs Chelsea'), findsOneWidget);
    });

    testWidgets('never renders a score, even when the model carries one', (
      tester,
    ) async {
      final item = fakeItem(
        participants: const [
          Participant(name: 'Arsenal', score: '2'),
          Participant(name: 'Chelsea', score: '1'),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: MediaCard(item: item, onTap: () {}),
        ),
      );
      await tester.pump();

      expect(find.textContaining('2'), findsNothing);
      expect(find.textContaining('1'), findsNothing);
    });

    testWidgets(
      'under a section heading the competition drops but the clock stays',
      (tester) async {
        final item = fakeItem(
          subtitle: 'Premier League',
          statusLabel: "63'",
          participants: const [
            Participant(name: 'Arsenal'),
            Participant(name: 'Chelsea'),
          ],
        );

        await tester.pumpWidget(
          MaterialApp(
            home: MediaCard(item: item, onTap: () {}, showSubtitle: false),
          ),
        );
        await tester.pump();

        expect(find.textContaining('Premier League'), findsNothing);
        expect(find.text("63'"), findsOneWidget);
      },
    );

    testWidgets('shows a fallback avatar per side when no logo is given', (
      tester,
    ) async {
      final item = fakeItem(
        participants: const [
          Participant(name: 'Home'),
          Participant(name: 'Away'),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: MediaCard(item: item, onTap: () {}),
        ),
      );
      await tester.pump();

      // An outline per side, not a filled disc — nothing solid sits on the
      // artwork where a side has no crest.
      expect(find.byIcon(Icons.shield_outlined), findsNWidgets(2));
    });

    testWidgets('a side with a logo renders the image, not the fallback', (
      tester,
    ) async {
      final item = fakeItem(
        participants: const [
          Participant(
            name: 'Home',
            logo: ImageRef('https://cdn.example/home.png'),
          ),
          Participant(
            name: 'Away',
            logo: ImageRef('https://cdn.example/away.png'),
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: MediaCard(item: item, onTap: () {}),
        ),
      );
      await tester.pump();

      expect(find.byType(CachedNetworkImage), findsNWidgets(2));
      expect(find.byIcon(Icons.shield_outlined), findsNothing);
    });

    testWidgets('a crest is never cropped to a circle', (tester) async {
      // The crest keeps whatever shape the logo actually is — a shield stays
      // a shield. ParticipantAvatar (a circular plate) is for dense list
      // rows and the detail page, not for artwork.
      final item = fakeItem(
        participants: const [
          Participant(
            name: 'Home',
            logo: ImageRef('https://cdn.example/home.png'),
          ),
          Participant(name: 'Away'),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: MediaCard(item: item, onTap: () {}),
        ),
      );
      await tester.pump();

      expect(
        find.descendant(
          of: find.byType(GeneratedBanner),
          matching: find.byType(ParticipantAvatar),
        ),
        findsNothing,
      );
    });

    test("each half is filled with that side's own Participant.color", () {
      // Two sides whose colours differ only from each other — if the banner
      // ignored Participant.color and hashed the names instead, the fills
      // would not track the hues given here.
      final (home, away) = GeneratedBanner.fillsFor(const [
        Participant(name: 'Home', color: '#0000FF'),
        Participant(name: 'Away', color: '#00FF00'),
      ]);

      // Darkened for legibility (see _legibleFill), so assert the hue each
      // fill leans toward rather than an exact value.
      expect(home.b, greaterThan(home.g));
      expect(away.g, greaterThan(away.b));
    });

    test('a near-white kit is darkened enough to carry white marks', () {
      final (home, _) = GeneratedBanner.fillsFor(const [
        Participant(name: 'Real Madrid', color: '#FFFFFF'),
        Participant(name: 'Barcelona', color: '#A50044'),
      ]);

      // Used raw, white artwork on a white fill would be invisible.
      expect(home.computeLuminance(), lessThan(0.5));
    });

    test('a competition keeps one pattern, and leagues differ', () {
      // Same league, same texture — every fixture in it looks related.
      expect(
        BannerPattern.forKey('Premier League'),
        BannerPattern.forKey('Premier League'),
      );

      // And the set spreads across leagues rather than collapsing onto one,
      // which is the whole point of keying off the competition.
      final leagues = [
        'Premier League',
        'La Liga',
        'Serie A',
        'Bundesliga',
        'Ligue 1',
        'Eredivisie',
        'Major League Soccer',
        'Liga MX',
      ];
      final patterns = leagues.map(BannerPattern.forKey).toSet();
      expect(patterns.length, greaterThan(1));
    });

    test('a fixture with no competition still gets a pattern', () {
      expect(BannerPattern.forKey(null), BannerPattern.sunburst);
    });

    test('two near-identical kits are still pushed apart', () {
      // Observed live: Tijuana against Cruz Azul, two greys a hair apart.
      // Rendered as given, the split between them disappears.
      final (home, away) = GeneratedBanner.fillsFor(const [
        Participant(name: 'Tijuana', color: '#5C5C5C'),
        Participant(name: 'Cruz Azul', color: '#282828'),
      ]);

      final separation = math.sqrt(
        math.pow(home.r - away.r, 2) +
            math.pow(home.g - away.g, 2) +
            math.pow(home.b - away.b, 2),
      );
      expect(separation, greaterThanOrEqualTo(0.22));
    });

    test('a pair that already contrasts is left alone', () {
      // Only a collision should move a colour — a real kit that already
      // reads against its opponent keeps exactly the value it was given.
      const away = Participant(name: 'Chelsea', color: '#034694');
      final (_, adjusted) = GeneratedBanner.fillsFor(const [
        Participant(name: 'Arsenal', color: '#DA291C'),
        away,
      ]);
      final (_, alone) = GeneratedBanner.fillsFor(const [
        Participant(name: 'Whoever', color: '#FFD400'),
        away,
      ]);

      expect(adjusted, alone);
    });

    test('the separated side stays dark enough for white artwork', () {
      final (_, away) = GeneratedBanner.fillsFor(const [
        Participant(name: 'A', color: '#EFEFEF'),
        Participant(name: 'B', color: '#F4F4F4'),
      ]);

      expect(away.computeLuminance(), lessThan(0.5));
    });

    test('two sides with no colour still differ from each other', () {
      final (home, away) = GeneratedBanner.fillsFor(const [
        Participant(name: 'Home'),
        Participant(name: 'Away'),
      ]);

      expect(home, isNot(away));
    });

    testWidgets('a malformed colour falls back instead of throwing', (
      tester,
    ) async {
      final item = fakeItem(
        participants: const [
          Participant(name: 'Home', color: 'not-a-colour'),
          Participant(name: 'Away', color: '#GGG'),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: MediaCard(item: item, onTap: () {}),
        ),
      );
      await tester.pump();

      expect(find.byType(GeneratedBanner), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('poster layout', () {
    testWidgets('a poster takes priority over the event layout', (
      tester,
    ) async {
      final item = fakeItem(
        title: 'The Matrix',
        subtitle: '1999',
        poster: const ImageRef('https://cdn.example/matrix.jpg'),
        participants: const [
          Participant(name: 'Should not show'),
          Participant(name: 'Either'),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: MediaCard(item: item, onTap: () {}),
        ),
      );
      await tester.pump();

      expect(find.text('The Matrix'), findsOneWidget);
      expect(find.text('1999'), findsOneWidget);
      // Real artwork wins: a poster item is never given a generated banner,
      // even though its data would otherwise qualify for one.
      expect(find.byType(GeneratedBanner), findsNothing);
      expect(find.byType(ParticipantAvatar), findsNothing);
    });

    testWidgets('a missing subtitle is simply omitted', (tester) async {
      final item = fakeItem(
        title: 'Untitled',
        poster: const ImageRef('https://cdn.example/x.jpg'),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: MediaCard(item: item, onTap: () {}),
        ),
      );
      await tester.pump();

      expect(find.text('Untitled'), findsOneWidget);
    });
  });
}
