import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_app/player/state/picture_in_picture_preference_controller.dart';
import 'package:fvcksubs_storage/fvcksubs_storage.dart';

void main() {
  test('defaults to enabled and persists changes', () async {
    final store = _Store();
    final controller = PictureInPicturePreferenceController(store: store);

    expect(controller.enabled, isTrue);

    controller.setEnabled(false);
    await Future<void>.delayed(Duration.zero);

    expect(controller.enabled, isFalse);
    expect(store.saved, isFalse);
  });
}

class _Store implements PictureInPicturePreferenceStore {
  bool saved = true;

  @override
  Future<bool> load() async => saved;

  @override
  Future<void> save(bool enabled) async => saved = enabled;
}
