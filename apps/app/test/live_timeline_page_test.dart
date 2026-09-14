import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_app/catalog/live_timeline_page.dart';
import 'package:fvcksubs_app/home/live_now_shelf.dart';
import 'package:fvcksubs_app/catalog/participant_avatar.dart';
import 'package:fvcksubs_app/home/home_page.dart';
import 'package:fvcksubs_app/widgets/app_page_bar.dart';
import 'package:fvcksubs_app/theme/tokens.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';

import 'support/harness.dart';

void main() {
  test('Live Now uses the event schedule window', () {
    final startsAt = DateTime.utc(2026, 9, 13, 10);
    final event = EventItemV2(
      ref: const MediaRef(
        extensionId: 'fake',
        providerId: 'fake.p',
        id: 'event',
      ),
      title: 'Event',
      schedule: Schedule(
        startsAt: startsAt,
        endsAt: startsAt.add(const Duration(hours: 2)),
      ),
    );

    expect(
      isEventLiveNow(event, startsAt.add(const Duration(minutes: 1))),
      isTrue,
    );
    expect(
      isEventLiveNow(event, startsAt.subtract(const Duration(minutes: 1))),
      isFalse,
    );
    expect(
      isEventLiveNow(event, startsAt.add(const Duration(hours: 2))),
      isFalse,
    );
  });

  testWidgets('Home derives Live Now from the live schedule', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final now = DateTime.now().toUtc();
    await tester.pumpWidget(
      wrapApp(
        child: const HomePage(),
        registry: ExtensionRegistry([
          FakeExtension(
            categories: ['all', 'live'],
            catalogs: [
              const FakeCatalog(
                id: 'home',
                name: 'Home',
                categories: ['all'],
                items: [],
              ),
              FakeCatalog(
                id: 'sports-schedule',
                name: 'Sports Schedule',
                categories: const ['live'],
                items: [
                  fakeItem(
                    id: 'arsenal-chelsea',
                    title: 'Arsenal vs Chelsea',
                    subtitle: 'Premier League',
                    startsAt: now.subtract(const Duration(minutes: 10)),
                    status: ScheduleState.live,
                  ),
                ],
                display: CatalogDisplay.timeline,
              ),
            ],
          ),
        ]),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Live Now'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('home-live-now-shelf')),
        matching: find.text('Arsenal vs Chelsea'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('Live opens the timeline and keeps schedule category available', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final now = DateTime.now().toUtc();
    await tester.pumpWidget(
      wrapApp(
        child: const HomePage(),
        registry: ExtensionRegistry([
          FakeExtension(
            categories: ['all', 'live', 'schedule'],
            catalogs: [
              const FakeCatalog(
                id: 'live-now',
                name: 'Live Now',
                categories: ['all'],
                items: [],
                display: CatalogDisplay.row,
              ),
              FakeCatalog(
                id: 'sports-schedule',
                name: 'Sports Schedule',
                categories: const ['live', 'schedule'],
                items: [
                  fakeItem(
                    id: 'arsenal-chelsea',
                    title: 'Arsenal vs Chelsea',
                    subtitle: 'Premier League',
                    status: ScheduleState.scheduled,
                    startsAt: now.add(const Duration(minutes: 30)),
                  ),
                ],
                display: CatalogDisplay.timeline,
              ),
            ],
          ),
        ]),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Schedule'), findsOneWidget);
    await tester.tap(find.text('Live'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(CatalogTimelinePage), findsOneWidget);
    expect(find.widgetWithText(AppPageBar, 'Live'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('catalog-timeline')),
        matching: find.text('Arsenal vs Chelsea'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('catalog-timeline')),
        matching: find.text('Premier League'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('catalog-now-line')), findsOneWidget);
    expect(find.byKey(const Key('catalog-mobile-timeline')), findsOneWidget);
    final eventTitle = find.descendant(
      of: find.byKey(const Key('catalog-mobile-timeline')),
      matching: find.text('Arsenal vs Chelsea'),
    );
    expect(tester.getSize(eventTitle).width, greaterThan(200));
  });

  testWidgets('timeline date selector stays pinned and uses readable text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 12).toUtc();
    final tomorrow = DateTime(now.year, now.month, now.day + 1, 12).toUtc();
    await tester.pumpWidget(
      wrapApp(
        child: const CatalogTimelinePage(category: 'live'),
        registry: ExtensionRegistry([
          FakeExtension(
            categories: ['live'],
            catalogs: [
              FakeCatalog(
                id: 'sports-schedule',
                name: 'Sports Schedule',
                categories: const ['live'],
                items: [
                  fakeItem(
                    id: 'today-event',
                    title: 'Today Event',
                    startsAt: today,
                  ),
                  fakeItem(
                    id: 'tomorrow-event',
                    title: 'Tomorrow Event',
                    startsAt: tomorrow,
                  ),
                ],
                display: CatalogDisplay.timeline,
              ),
            ],
          ),
        ]),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final header = tester.widget<SliverPersistentHeader>(
      find.byType(SliverPersistentHeader),
    );
    expect(header.pinned, isTrue);
    expect(tester.widget<Text>(find.text('Today')).style?.fontSize, 14);

    await tester.drag(
      find.byKey(const Key('catalog-timeline-scroll')),
      const Offset(0, -500),
    );
    await tester.pump();
    expect(find.text('Today'), findsOneWidget);
  });

  testWidgets('large screens render a horizontally scrolling timeline', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final now = DateTime.now().toUtc();
    await tester.pumpWidget(
      wrapApp(
        child: const CatalogTimelinePage(category: 'live'),
        registry: ExtensionRegistry([
          FakeExtension(
            categories: ['live'],
            catalogs: [
              FakeCatalog(
                id: 'sports-schedule',
                name: 'Sports Schedule',
                categories: const ['live'],
                items: [
                  fakeItem(
                    id: 'arsenal-chelsea',
                    title: 'Arsenal vs Chelsea',
                    status: ScheduleState.scheduled,
                    startsAt: now.add(const Duration(minutes: 30)),
                  ),
                ],
                display: CatalogDisplay.timeline,
              ),
            ],
          ),
        ]),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byKey(const Key('catalog-wide-timeline')), findsOneWidget);
    expect(find.byKey(const Key('catalog-mobile-timeline')), findsNothing);
    expect(find.byKey(const Key('catalog-now-line')), findsOneWidget);
    expect(find.text('Arsenal vs Chelsea'), findsOneWidget);
  });

  testWidgets('toolbar switches to a league-grouped list view', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final now = DateTime.now().toUtc();
    await tester.pumpWidget(
      wrapApp(
        child: const CatalogTimelinePage(category: 'live'),
        registry: ExtensionRegistry([
          FakeExtension(
            categories: ['live'],
            catalogs: [
              FakeCatalog(
                id: 'sports-schedule',
                name: 'Sports Schedule',
                categories: const ['live'],
                items: [
                  fakeItem(
                    id: 'arsenal-chelsea',
                    title: 'Arsenal vs Chelsea',
                    subtitle: 'Premier League',
                    startsAt: now.add(const Duration(minutes: 30)),
                    participants: const [
                      Participant(
                        name: 'Arsenal',
                        logo: ImageRef('https://cdn.example/arsenal.png'),
                      ),
                      Participant(
                        name: 'Chelsea',
                        logo: ImageRef('https://cdn.example/chelsea.png'),
                      ),
                    ],
                  ),
                  fakeItem(
                    id: 'liverpool-city',
                    title: 'Liverpool vs City',
                    subtitle: 'Premier League',
                    startsAt: now.add(const Duration(minutes: 30)),
                    participants: const [
                      Participant(
                        name: 'Liverpool',
                        logo: ImageRef('https://cdn.example/liverpool.png'),
                      ),
                      Participant(
                        name: 'City',
                        logo: ImageRef('https://cdn.example/city.png'),
                      ),
                    ],
                  ),
                  fakeItem(
                    id: 'motogp-sprint',
                    title: 'Sprint Race',
                    subtitle: 'MotoGP',
                    startsAt: now.add(const Duration(minutes: 45)),
                  ),
                  fakeItem(
                    id: 'unknown-match',
                    title: 'Rangers vs Celtic',
                    startsAt: now.add(const Duration(minutes: 60)),
                    participants: const [
                      Participant(name: 'Rangers'),
                      Participant(name: 'Celtic'),
                    ],
                  ),
                ],
                display: CatalogDisplay.timeline,
              ),
            ],
          ),
        ]),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byKey(const Key('catalog-display-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('List'));
    await tester.pump();

    expect(find.byKey(const Key('catalog-list-view')), findsOneWidget);
    expect(find.byKey(const Key('catalog-mobile-timeline')), findsNothing);
    expect(find.text('Premier League'), findsOneWidget);
    expect(find.text('2 events'), findsNothing);
    expect(find.text('Arsenal'), findsOneWidget);
    expect(find.text('Chelsea'), findsOneWidget);
    expect(find.text('Liverpool'), findsOneWidget);
    expect(find.text('City'), findsOneWidget);
    expect(find.text('MotoGP'), findsOneWidget);
    expect(find.text('Sprint Race'), findsOneWidget);
    expect(find.text('Other'), findsOneWidget);
    expect(find.text('Rangers'), findsOneWidget);
    expect(find.text('Celtic'), findsOneWidget);
    expect(find.text('VS'), findsNothing);
  });

  testWidgets('timeline cards use the league primary color when available', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final now = DateTime.now().toUtc();
    await tester.pumpWidget(
      wrapApp(
        child: const CatalogTimelinePage(category: 'live'),
        registry: ExtensionRegistry([
          FakeExtension(
            categories: ['live'],
            catalogs: [
              FakeCatalog(
                id: 'sports-schedule',
                name: 'Sports Schedule',
                categories: const ['live'],
                items: [
                  fakeItem(
                    id: 'branded-event',
                    title: 'Branded event',
                    subtitle: 'Premier League',
                    startsAt: now.add(const Duration(minutes: 30)),
                    participants: [
                      const Participant(
                        name: 'Home',
                        logo: ImageRef('https://cdn.example/home.png'),
                      ),
                      const Participant(
                        name: 'Away',
                        logo: ImageRef('https://cdn.example/away.png'),
                      ),
                    ],
                    branding: const EventBranding(
                      logo: ImageRef('https://cdn.example/league.png'),
                      primaryColor: '#37003C',
                    ),
                  ),
                ],
                display: CatalogDisplay.timeline,
              ),
            ],
          ),
        ]),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final material = find
        .ancestor(of: find.text('Home'), matching: find.byType(Material))
        .first;
    final cardColor = tester.widget<Material>(material).color;
    expect(cardColor, isNot(AppColors.surfaceDarkElevated));
    expect(find.text('Premier League'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Away'), findsOneWidget);
    expect(find.byType(ParticipantAvatar), findsNWidgets(2));
  });

  testWidgets('events with the same start time open an event picker', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final now = DateTime.now().toUtc();
    final start = now.add(const Duration(minutes: 30));
    await tester.pumpWidget(
      wrapApp(
        child: const CatalogTimelinePage(category: 'live'),
        registry: ExtensionRegistry([
          FakeExtension(
            categories: ['live'],
            catalogs: [
              FakeCatalog(
                id: 'sports-schedule',
                name: 'Sports Schedule',
                categories: const ['live'],
                items: [
                  fakeItem(
                    id: 'arsenal-chelsea',
                    title: 'Arsenal vs Chelsea',
                    subtitle: 'Premier League',
                    status: ScheduleState.scheduled,
                    startsAt: start,
                  ),
                  fakeItem(
                    id: 'madrid-barcelona',
                    title: 'Madrid vs Barcelona',
                    subtitle: 'Premier League',
                    status: ScheduleState.scheduled,
                    startsAt: start,
                  ),
                  fakeItem(
                    id: 'milan-inter',
                    title: 'Milan vs Inter',
                    subtitle: 'Serie A',
                    status: ScheduleState.scheduled,
                    startsAt: start,
                  ),
                ],
                display: CatalogDisplay.timeline,
              ),
            ],
          ),
        ]),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('2 events'), findsOneWidget);
    expect(find.text('Milan vs Inter'), findsOneWidget);
    await tester.ensureVisible(find.text('2 events'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2 events'));
    await tester.pumpAndSettle();

    expect(find.text('Choose an event'), findsOneWidget);
    expect(find.text('Arsenal vs Chelsea'), findsWidgets);
    expect(find.text('Madrid vs Barcelona'), findsWidgets);
  });
}
