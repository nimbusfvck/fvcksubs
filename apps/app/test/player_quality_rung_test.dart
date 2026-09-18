import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_app/player/models/app_player_controller.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';

void main() {
  test('an ultrawide 1080 frame is not mislabeled as 1440p', () {
    expect(qualityRungLabel(width: 2580, height: 1080), '1080p');
  });

  test('canonical heights name ultrawide renditions', () {
    expect(qualityRungLabel(width: 3440, height: 1440), '1440p');
    expect(qualityRungLabel(width: 3840, height: 1600), '4K');
  });

  test(
    'letterboxed frames still use width when height is not a named rung',
    () {
      expect(qualityRungLabel(width: 1920, height: 800), '1080p');
      expect(qualityRungLabel(width: 1280, height: 534), '720p');
    },
  );

  test('keeps the selected provider variant over a native duplicate', () {
    const native = AppQualityTrack(
      id: 'native-360',
      height: 360,
      bitrate: 660249,
    );
    const variant = AppQualityTrack(
      id: 'quality-360p-0',
      height: 360,
      variant: StreamVariant(
        id: 'quality-360p-0',
        url: 'https://stream.example/360.m3u8',
        height: 360,
      ),
    );

    final tracks = dedupedQualityTracks([
      native,
      variant,
    ], preferredId: variant.id);

    expect(tracks.single.id, variant.id);
    expect(tracks.single.variant, isNotNull);
  });
}
