import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_app/player/models/app_player_controller.dart';
import 'package:fvcksubs_app/player/state/quality_preference_controller.dart';
import 'package:fvcksubs_storage/fvcksubs_storage.dart';

void main() {
  test('normalizes unsupported stored qualities to Auto', () {
    final controller = QualityPreferenceController(
      store: _Store(),
      initial: 999,
    );

    expect(controller.maxHeight, isNull);
  });

  test('selects and persists a supported maximum quality', () async {
    final store = _Store();
    final controller = QualityPreferenceController(store: store);

    controller.select(720);
    await Future<void>.delayed(Duration.zero);

    expect(controller.maxHeight, 720);
    expect(store.saved, 720);
  });

  test('chooses the highest bitrate when a height repeats', () {
    const tracks = [
      AppQualityTrack(id: 'low', height: 720, bitrate: 1000),
      AppQualityTrack(id: 'high', height: 720, bitrate: 2500),
      AppQualityTrack(id: 'sd', height: 480, bitrate: 800),
    ];

    expect(preferredQualityTrack(tracks: tracks, maxHeight: 720)?.id, 'high');
  });
}

class _Store implements QualityPreferenceStore {
  int? saved;

  @override
  Future<int?> load() async => saved;

  @override
  Future<void> save(int? maxHeight) async => saved = maxHeight;
}
