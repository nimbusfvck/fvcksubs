import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_app/player/multi_view_page.dart';
import 'package:fvcksubs_app/player/player_page.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';

import 'support/harness.dart';

void main() {
  final event = EventItemV2(
    ref: const MediaRef(
      extensionId: 'sports',
      providerId: 'sports.live',
      id: 'match-1',
    ),
    title: 'Match 1',
    schedule: Schedule(
      startsAt: DateTime.utc(2026, 1, 1),
      state: ScheduleState.live,
    ),
    participants: const [
      Participant(name: 'Home'),
      Participant(name: 'Away'),
    ],
  );
  const source = ResolvedSource(
    source: StreamSource(id: 'source-1', label: 'Source 1'),
    stream: PlayableStream(
      url: 'https://stream.example/match-1.m3u8',
      format: StreamFormat.hls,
    ),
  );

  testWidgets('live player opens Multi-view from the top control', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrapApp(
        child: PlayerPage(item: event, resolvedSources: [source]),
        registry: ExtensionRegistry([]),
        player: RecordingPlayer(),
      ),
    );
    await tester.pump();

    expect(find.byTooltip('Multi-view'), findsOneWidget);
    await tester.tap(find.byTooltip('Multi-view'));
    // The multi-view tile intentionally keeps a buffering spinner alive until
    // the injected player reports initialized, so settle is not appropriate.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Multi-view'), findsOneWidget);
  });

  testWidgets('sports multi-view starts with one event and an add slot', (
    tester,
  ) async {
    EventItemV2? selectedEvent;
    ResolvedSource? selectedSource;
    EventItemV2? miniEvent;
    ResolvedSource? miniSource;
    await tester.pumpWidget(
      wrapApp(
        child: MultiViewPage(
          initialEvent: event,
          initialSource: source,
          onOpenSinglePlayer: (nextEvent, nextSource) {
            selectedEvent = nextEvent;
            selectedSource = nextSource;
          },
          onExitToMiniPlayer: (nextEvent, nextSource) {
            miniEvent = nextEvent;
            miniSource = nextSource;
          },
        ),
        registry: ExtensionRegistry([]),
        player: RecordingPlayer(),
      ),
    );
    await tester.pump();

    expect(find.text('Home vs Away'), findsOneWidget);
    expect(find.text('Add live event'), findsOneWidget);
    expect(find.byTooltip('Remove event'), findsOneWidget);
    expect(find.byTooltip('Change source'), findsOneWidget);
    expect(find.byTooltip('Pin player'), findsOneWidget);
    expect(find.byTooltip('Single player'), findsOneWidget);

    await tester.tap(find.byTooltip('Pin player'));
    await tester.pump();
    expect(find.byTooltip('Unpin player'), findsOneWidget);

    await tester.tap(find.byTooltip('Single player'));
    expect(selectedEvent, event);
    expect(selectedSource, source);

    await tester.tap(find.byTooltip('Remove event'));
    expect(miniEvent, event);
    expect(miniSource, source);
  });
}
