import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_app/player/subtitle_preference_controller.dart';
import 'package:fvcksubs_app/settings/settings_page.dart';
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
}
