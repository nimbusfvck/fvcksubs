import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_app/player/widgets/player_orientation_button.dart';

void main() {
  testWidgets('requests landscape when the control is inactive', (
    tester,
  ) async {
    var toggles = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlayerOrientationButton(
            landscapeLocked: false,
            onToggle: () => toggles++,
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.screen_rotation_alt_rounded), findsOneWidget);
    expect(find.byTooltip('Landscape player'), findsOneWidget);

    await tester.tap(find.byTooltip('Landscape player'));

    expect(toggles, 1);
  });

  testWidgets('offers device orientation when landscape is active', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PlayerOrientationButton(landscapeLocked: true, onToggle: _noop),
        ),
      ),
    );

    expect(find.byIcon(Icons.screen_lock_landscape_rounded), findsOneWidget);
    expect(find.byTooltip('Use device orientation'), findsOneWidget);
  });
}

void _noop() {}
