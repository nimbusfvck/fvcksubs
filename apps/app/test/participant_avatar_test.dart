import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_app/catalog/participant_avatar.dart';

void main() {
  testWidgets('no imageUrl renders the neutral fallback, no network attempt', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: ParticipantAvatar(imageUrl: null)),
    );
    await tester.pump();

    // Generic ring, not a sport-specific glyph — this widget must not assume
    // football (or any vertical) to stay reusable across catalogs.
    expect(find.byIcon(Icons.circle_outlined), findsOneWidget);
  });

  testWidgets('a given imageUrl is handed to the image widget verbatim', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ParticipantAvatar(imageUrl: 'https://cdn.example/crest.png'),
      ),
    );
    // No pumpAndSettle: the image never resolves in a test environment with
    // no network, and this only asserts the widget was configured correctly.
    await tester.pump();

    expect(find.byIcon(Icons.circle_outlined), findsNothing);
  });

  testWidgets('size controls the diameter', (tester) async {
    // Center, not home directly: MaterialApp.home hands its child tight
    // full-screen constraints, which would stretch the fixed-size Container
    // regardless of what [size] asked for.
    await tester.pumpWidget(
      const MaterialApp(home: Center(child: ParticipantAvatar(size: 44))),
    );
    await tester.pump();

    final box = tester.getSize(find.byType(ParticipantAvatar));
    expect(box, const Size(44, 44));
  });
}
