import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_app/player/widgets/player_overlays.dart';

void main() {
  testWidgets('up-next card keeps close beside the title on the left', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: PlayerUpNextCard(
              seriesTitle: 'Example Series',
              subtitle: 'Season 2 · Episode 3',
              countdown: const Duration(seconds: 5),
              paused: false,
              onPlayNext: () {},
              onCancel: () {},
            ),
          ),
        ),
      ),
    );

    final title = tester.getTopLeft(find.text('Example Series'));
    final subtitle = tester.getTopLeft(find.text('Season 2 · Episode 3'));
    final close = tester.getCenter(find.byTooltip('Close next episode'));
    final play = tester.getCenter(find.byIcon(Icons.play_arrow_rounded));

    // Close on the left, then the text block, then the play control.
    expect(close.dx, lessThan(title.dx));
    expect(play.dx, greaterThan(title.dx));
    // The two lines read as one block: they share a left edge rather than
    // each floating on its own width.
    expect(subtitle.dx, title.dx);
  });

  testWidgets('up-next countdown does not resume after an outside-tap pause', (
    tester,
  ) async {
    var playCalls = 0;

    Widget card({required bool paused}) => MaterialApp(
      home: Scaffold(
        body: PlayerUpNextCard(
          seriesTitle: 'Example Series',
          subtitle: 'Season 2 · Episode 3',
          countdown: const Duration(seconds: 5),
          paused: paused,
          onPlayNext: () => playCalls++,
          onCancel: () {},
        ),
      ),
    );

    await tester.pumpWidget(card(paused: false));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpWidget(card(paused: true));
    await tester.pump(const Duration(seconds: 4));
    expect(playCalls, 0);

    await tester.pumpWidget(card(paused: false));
    await tester.pump(const Duration(seconds: 4));
    expect(playCalls, 0);
  });

  testWidgets('top-edge swipe does not dismiss the player', (tester) async {
    var dismissals = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerDragToClose(
          onDismiss: () => dismissals++,
          child: const SizedBox.expand(),
        ),
      ),
    );

    await tester.dragFrom(const Offset(200, 8), const Offset(200, 320));
    await tester.pumpAndSettle();
    expect(dismissals, 0);

    await tester.dragFrom(const Offset(200, 96), const Offset(200, 420));
    expect(dismissals, 1);
  });
}
