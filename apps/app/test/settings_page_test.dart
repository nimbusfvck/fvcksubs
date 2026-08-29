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

  testWidgets('subtitle appearance can be changed and persisted', (
    tester,
  ) async {
    final store = FakeSubtitlePreferenceStore();
    final controller = SubtitlePreferenceController(store: store);

    await tester.pumpWidget(
      wrapApp(
        child: const SettingsPage(),
        registry: ExtensionRegistry([]),
        subtitlePreferenceController: controller,
      ),
    );
    await tester.pumpAndSettle();

    // The new Addons entry at the top of Settings pushes this tile below
    // the test viewport's fold.
    await tester.drag(find.byType(ListView).first, const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Subtitle appearance'));
    await tester.pumpAndSettle();

    final slider = tester.widget<Slider>(find.byType(Slider));
    slider.onChanged!(36);
    await tester.pump();
    await tester.tap(find.text('Yellow'));
    await tester.drag(find.byType(ListView).first, const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Blue'));
    await tester.drag(find.byType(ListView).first, const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch));
    await tester.pump();

    expect(controller.appearance.fontSize, 36);
    expect(controller.appearance.textColor, const Color(0xffffeb3b));
    expect(controller.appearance.backgroundColor, const Color(0xdd10243d));
    expect(controller.appearance.outline, isTrue);
    expect(store.appearanceSaved.fontSize, 36);
    expect(store.appearanceSaved.outline, isTrue);
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

    await tester.drag(find.byType(ListView).first, const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch));
    await tester.pump();
    final enableButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Enable'),
    );
    expect(enableButton.onPressed, isNull);
    await tester.tap(find.byType(Checkbox));
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

    await tester.drag(find.byType(ListView).first, const Offset(0, -300));
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
