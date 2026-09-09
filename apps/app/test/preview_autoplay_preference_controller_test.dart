import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_app/settings/preview_autoplay_preference_controller.dart';

import 'support/harness.dart';

void main() {
  test('defaults to enabled and persists changes', () async {
    final store = FakePreviewAutoplayPreferenceStore();
    final controller = PreviewAutoplayPreferenceController(store: store);

    expect(controller.enabled, isTrue);

    controller.setEnabled(false);
    await Future<void>.delayed(Duration.zero);

    expect(controller.enabled, isFalse);
    expect(store.saved, isFalse);
  });
}
