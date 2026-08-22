import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_app/player/widgets/player_overlays.dart';

void main() {
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
