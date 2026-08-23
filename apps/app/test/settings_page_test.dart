import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_app/player/state/subtitle_preference_controller.dart';
import 'package:fvcksubs_app/settings/settings_page.dart';
import 'package:fvcksubs_app/settings/nsfw_controller.dart';
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';

import 'support/harness.dart';

void main() {
  testWidgets('subtitle preference is selected and persisted from Settings', (
    tester,
  ) async {
    final store = FakeSubtitlePreferenceStore();
    final controller = SubtitlePreferenceController(
      store: store,
      initial: null,
    );

    await tester.pumpWidget(
      wrapApp(
        child: const SettingsPage(),
        registry: ExtensionRegistry([]),
        subtitlePreferenceController: controller,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Indonesia'));
    await tester.pumpAndSettle();

    expect(controller.languageCode, 'id');
    expect(store.saved, 'id');
  });

  testWidgets('source priority opens a ranked provider list', (tester) async {
    final registry = ExtensionRegistry([
      FakeExtension(id: 'first', name: 'Nimora', providerName: 'Atlas'),
      FakeExtension(id: 'second', name: 'Another', providerName: 'Boreal'),
    ]);

    await tester.pumpWidget(
      wrapApp(child: const SettingsPage(), registry: registry),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Source priority'));
    await tester.pumpAndSettle();

    expect(find.text('Atlas'), findsOneWidget);
    expect(find.text('Boreal'), findsOneWidget);
    expect(find.text('Nimora'), findsOneWidget);
    expect(find.byIcon(Icons.drag_handle), findsNWidgets(2));
  });

  testWidgets('NSFW toggle changes the saved content preference', (
    tester,
  ) async {
    final registry = ExtensionRegistry([]);
    final store = FakeNsfwSettingsStore();
    final controller = NsfwController(
      registry: registry,
      store: store,
      showNsfw: false,
    );

    await tester.pumpWidget(
      wrapApp(
        child: const SettingsPage(),
        registry: registry,
        nsfwController: controller,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Switch));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Enable'));
    await tester.pumpAndSettle();

    expect(controller.state.showNsfw, isTrue);
    expect(store.saved.showNsfw, isTrue);
  });

  testWidgets('cancelling the NSFW confirmation keeps it disabled', (
    tester,
  ) async {
    final registry = ExtensionRegistry([]);
    final store = FakeNsfwSettingsStore();
    final controller = NsfwController(
      registry: registry,
      store: store,
      showNsfw: false,
    );

    await tester.pumpWidget(
      wrapApp(
        child: const SettingsPage(),
        registry: registry,
        nsfwController: controller,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.text('Show NSFW content?'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(controller.state.showNsfw, isFalse);
    expect(store.saved.showNsfw, isFalse);
  });
}
