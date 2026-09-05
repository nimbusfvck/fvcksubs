import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_app/player/widgets/platform_player_builder.dart';

void main() {
  test('all supported playback routes use video_player', () {
    expect(usesVideoPlayer(), isTrue);
  });
}
