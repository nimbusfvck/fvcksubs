import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_app/player/state/source_priority_controller.dart';
import 'package:fvcksubs_app/player/state/picture_in_picture_preference_controller.dart';
import 'package:fvcksubs_app/player/state/subtitle_preference_controller.dart';
import 'package:fvcksubs_app/settings/settings_page.dart';
import 'package:fvcksubs_app/settings/nsfw_controller.dart';
import 'package:fvcksubs_app/settings/preview_autoplay_preference_controller.dart';
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';
import 'package:fvcksubs_storage/fvcksubs_storage.dart';

import 'support/harness.dart';

void main() {
  testWidgets('preview autoplay toggle changes and persists the preference', (
    tester,
  ) async {
    final store = FakePreviewAutoplayPreferenceStore();
    final controller = PreviewAutoplayPreferenceController(store: store);

    await tester.pumpWidget(
      wrapApp(
        child: const SettingsPage(),
        registry: ExtensionRegistry([]),
        previewAutoplayPreferenceController: controller,
      ),
    );
    await tester.pumpAndSettle();

    final tile = find.widgetWithText(SwitchListTile, 'Autoplay previews');
    await tester.ensureVisible(tile);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(tile).value, isTrue);

    await tester.tap(tile);
    await tester.pump();

    expect(controller.enabled, isFalse);
    expect(store.saved, isFalse);
    expect(tester.widget<SwitchListTile>(tile).value, isFalse);
  });

  testWidgets('Picture in Picture toggle changes and persists the preference', (
    tester,
  ) async {
    final store = FakePictureInPicturePreferenceStore();
    final controller = PictureInPicturePreferenceController(store: store);

    await tester.pumpWidget(
      wrapApp(
        child: const SettingsPage(),
        registry: ExtensionRegistry([]),
        pictureInPicturePreferenceController: controller,
      ),
    );
    await tester.pumpAndSettle();

    final tile = find.widgetWithText(SwitchListTile, 'Picture in Picture');
    expect(tester.widget<SwitchListTile>(tile).value, isTrue);

    await tester.tap(tile);
    await tester.pump();

    expect(controller.enabled, isFalse);
    expect(store.saved, isFalse);
    expect(tester.widget<SwitchListTile>(tile).value, isFalse);
  });

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

    final indonesia = find.widgetWithText(RadioListTile<String?>, 'Indonesia');
    await tester.drag(find.byType(ListView).first, const Offset(0, -600));
    await tester.pumpAndSettle();
    await tester.tap(indonesia);
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
    await tester.drag(find.byType(ListView).first, const Offset(0, -600));
    await tester.pumpAndSettle();
    final subtitleAppearance = find.ancestor(
      of: find.text('Subtitle appearance'),
      matching: find.byType(ListTile),
    );
    await tester.ensureVisible(subtitleAppearance);
    tester.widget<ListTile>(subtitleAppearance).onTap!();
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
    await tester.tap(find.widgetWithText(SwitchListTile, 'Text outline'));
    await tester.pump();

    expect(controller.appearance.fontSize, 36);
    expect(controller.appearance.textColor, const Color(0xffffeb3b));
    expect(controller.appearance.backgroundColor, const Color(0xbb10243d));
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

  testWidgets('source region override is selected and persisted', (
    tester,
  ) async {
    final localeStore = FakeSourceLocalePreferenceStore();
    final controller = SourcePriorityController(
      registry: ExtensionRegistry([]),
      store: FakeSourcePriorityStore(),
      localeStore: localeStore,
    );

    await tester.pumpWidget(
      wrapApp(
        child: const SettingsPage(),
        registry: ExtensionRegistry([]),
        sourcePriorityController: controller,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Preferred source locale'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Prefer Indonesian providers'));
    await tester.pumpAndSettle();

    expect(controller.sourceLocale, SourceLocalePreference.indonesia);
    expect(localeStore.saved, SourceLocalePreference.indonesia);
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

    await tester.drag(find.byType(ListView).first, const Offset(0, -600));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(SwitchListTile, 'Show NSFW content'));
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

    await tester.drag(find.byType(ListView).first, const Offset(0, -600));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(SwitchListTile, 'Show NSFW content'));
    await tester.pumpAndSettle();
    expect(find.text('Show NSFW content?'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(controller.state.showNsfw, isFalse);
    expect(store.saved.showNsfw, isFalse);
  });
}
