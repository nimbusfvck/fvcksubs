import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_app/player/state/picture_in_picture_session.dart';

void main() {
  testWidgets('a modal sheet opened by the player stays above its host', (
    tester,
  ) async {
    final session = PictureInPictureSession();
    final navigatorKey = GlobalKey<NavigatorState>();

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        navigatorObservers: [
          PictureInPictureNavigatorObserver(session: session),
        ],
        home: const Scaffold(body: Text('Detail')),
      ),
    );

    session.attach(
      Material(
        color: Colors.black,
        child: Center(
          child: FilledButton(
            onPressed: () => showModalBottomSheet<void>(
              context: navigatorKey.currentContext!,
              builder: (_) => const SizedBox(
                height: 160,
                child: Center(child: Text('Source actions')),
              ),
            ),
            child: const Text('Open actions'),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Open actions'));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Source actions'), findsOneWidget);
  });

  testWidgets('a modal sheet receives taps above the persistent player', (
    tester,
  ) async {
    final session = PictureInPictureSession();
    final navigatorKey = GlobalKey<NavigatorState>();
    var sheetActionPressed = false;
    var playerTapCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        navigatorObservers: [
          PictureInPictureNavigatorObserver(session: session),
        ],
        home: const Scaffold(body: Text('Detail')),
      ),
    );

    session.attach(
      Material(
        color: Colors.black,
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => playerTapCount++,
              ),
            ),
            Align(
              alignment: Alignment.topCenter,
              child: FilledButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: navigatorKey.currentContext!,
                  useRootNavigator: true,
                  builder: (sheetContext) => SizedBox(
                    height: 160,
                    child: Center(
                      child: FilledButton(
                        onPressed: () {
                          sheetActionPressed = true;
                          Navigator.of(sheetContext).pop();
                        },
                        child: const Text('Sheet action'),
                      ),
                    ),
                  ),
                ),
                child: const Text('Open actions'),
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Open actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Sheet action'));
    await tester.pumpAndSettle();

    expect(sheetActionPressed, isTrue);
    expect(playerTapCount, 0);
  });

  testWidgets('a player-owned sheet stays inside the persistent host', (
    tester,
  ) async {
    final session = PictureInPictureSession();
    final navigatorKey = GlobalKey<NavigatorState>();

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        navigatorObservers: [
          PictureInPictureNavigatorObserver(session: session),
        ],
        home: const Scaffold(body: Text('Detail')),
      ),
    );

    session.attach(
      Material(
        color: Colors.black,
        child: Center(
          child: FilledButton(
            onPressed: () => showModalBottomSheet<void>(
              context: session.modalNavigatorKey.currentContext!,
              builder: (_) => const SizedBox(
                height: 160,
                child: Center(child: Text('Player actions')),
              ),
            ),
            child: const Text('Open player actions'),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Open player actions'));
    await tester.pumpAndSettle();

    expect(find.text('Player actions'), findsOneWidget);
  });
}
