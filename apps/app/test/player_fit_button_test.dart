import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_app/player/models/app_player_controller.dart';
import 'package:fvcksubs_app/player/widgets/player_fit_button.dart';

void main() {
  testWidgets('fit button reports the next viewport mode', (tester) async {
    var toggled = false;

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerFitButton(
          mode: PlayerFitMode.contain,
          onToggle: () => toggled = true,
        ),
      ),
    );

    expect(find.byIcon(Icons.fit_screen_rounded), findsOneWidget);
    expect(find.byTooltip('Fit screen'), findsOneWidget);

    await tester.tap(find.byTooltip('Fit screen'));
    expect(toggled, isTrue);
  });
}
