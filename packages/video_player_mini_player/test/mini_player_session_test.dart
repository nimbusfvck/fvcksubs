import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_mini_player/video_player_mini_player.dart';

void main() {
  test('session transitions between full-screen and minimized', () {
    final session = MiniPlayerSession();
    final player = const SizedBox();

    session.attach(player);
    expect(session.mode, MiniPlayerMode.fullScreen);
    expect(session.presentation.value.showControls, isTrue);
    expect(session.presentation.value.showBackground, isTrue);

    session.updateDrag(0.4);
    expect(session.mode, MiniPlayerMode.dragging);
    expect(session.dragProgress, 0.4);
    expect(session.presentation.value.showControls, isFalse);
    expect(session.presentation.value.showBackground, isFalse);

    session.minimize();
    expect(session.isMinimized, isTrue);
    expect(session.dragProgress, 1);

    session.restore();
    expect(session.mode, MiniPlayerMode.fullScreen);
    expect(session.dragProgress, 0);

    session.dispose();
  });

  testWidgets('dragging the host docks the same player widget', (tester) async {
    final session = MiniPlayerSession();
    final playerKey = GlobalKey();
    var playbackToggleRequested = 0;
    session.attach(
      ColoredBox(key: playerKey, color: Colors.black),
      onPlaybackToggleRequested: () => playbackToggleRequested++,
    );
    session.setPlaybackState(isPlaying: true, isBuffering: false);

    await tester.pumpWidget(
      MaterialApp(home: MiniPlayerHost(session: session)),
    );
    await tester.pump();

    await tester.dragFrom(const Offset(180, 160), const Offset(180, 330));
    await tester.pumpAndSettle();

    expect(session.mode, MiniPlayerMode.minimized);
    expect(find.byKey(playerKey), findsOneWidget);
    expect(find.byTooltip('Pause player'), findsOneWidget);
    expect(find.byTooltip('Close player'), findsOneWidget);
    expect(tester.getSize(find.byTooltip('Pause player')), const Size(24, 24));

    await tester.tap(find.byTooltip('Pause player'));
    expect(playbackToggleRequested, 1);
    expect(session.mode, MiniPlayerMode.minimized);

    session.setPlaybackState(isPlaying: false, isBuffering: false);
    await tester.pump();
    expect(find.byTooltip('Play player'), findsOneWidget);

    session.setPlaybackState(isPlaying: false, isBuffering: true);
    await tester.pump();
    expect(find.byTooltip('Loading player'), findsOneWidget);

    await tester.tapAt(const Offset(700, 550));
    await tester.pumpAndSettle();
    expect(session.mode, MiniPlayerMode.fullScreen);

    session.dispose();
  });

  testWidgets(
    'navigator observer keeps one host when attaching a keyed player',
    (tester) async {
      final session = MiniPlayerSession();
      final observer = MiniPlayerNavigatorObserver(session: session);
      final firstPlayerKey = GlobalKey();
      final secondPlayerKey = GlobalKey();

      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [observer],
          home: const SizedBox.shrink(),
        ),
      );
      await tester.pump();

      session.attach(SizedBox(key: firstPlayerKey));
      await tester.pump();

      expect(find.byKey(firstPlayerKey), findsOneWidget);
      expect(tester.takeException(), isNull);

      session.detach(session.player!);
      await tester.pump();
      expect(find.byKey(firstPlayerKey), findsNothing);

      session.attach(SizedBox(key: secondPlayerKey));
      await tester.pump();
      expect(find.byKey(secondPlayerKey), findsOneWidget);
      session.dispose();
    },
  );

  testWidgets('drag moves and snaps the minimized player', (tester) async {
    final session = MiniPlayerSession();
    final playerKey = GlobalKey();
    session.attach(SizedBox(key: playerKey));
    session.setPlaybackState(isPlaying: true, isBuffering: false);

    await tester.pumpWidget(
      MaterialApp(home: MiniPlayerHost(session: session)),
    );
    await tester.pump();
    session.minimize();
    await tester.pump();

    await tester.dragFrom(const Offset(700, 550), const Offset(-560, 0));
    await tester.pumpAndSettle();
    expect(session.value.dock, MiniPlayerDock.bottomLeft);

    final miniTopBeforeDrag = tester.getTopLeft(find.byKey(playerKey)).dy;
    final gesture = await tester.startGesture(const Offset(100, 550));
    await gesture.moveBy(const Offset(0, -300));
    await tester.pump();
    expect(
      tester.getTopLeft(find.byKey(playerKey)).dy,
      lessThan(miniTopBeforeDrag),
    );
    await gesture.up();
    await tester.pumpAndSettle();
    expect(session.value.dock, MiniPlayerDock.topLeft);

    session.dispose();
  });
}
