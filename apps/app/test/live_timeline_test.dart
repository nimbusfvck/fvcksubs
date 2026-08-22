import 'package:better_player_plus/better_player_plus.dart';
import 'package:better_player_plus/src/video_player/video_player_platform_interface.dart'
    show DurationRange;
import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_app/player/live_timeline.dart';

void main() {
  test('uses the furthest known live point for the timeline extent', () {
    final value = VideoPlayerValue(
      duration: const Duration(seconds: 20),
      position: const Duration(seconds: 25),
      buffered: const [
        DurationRange(Duration(seconds: 4), Duration(seconds: 32)),
      ],
    );

    expect(liveSeekEdge(value), const Duration(seconds: 32));
    expect(bufferedSeekEdge(value), const Duration(seconds: 32));
  });

  test('moves the live edge forward while playback remains paused', () {
    expect(
      liveEdgeAfterPause(
        const Duration(minutes: 4),
        const Duration(seconds: 7),
      ),
      const Duration(minutes: 4, seconds: 7),
    );
  });

  test('snaps a rightmost live scrub safely behind the edge', () {
    expect(
      liveSeekTarget(
        const Duration(seconds: 60),
        const Duration(seconds: 60),
        currentPosition: const Duration(seconds: 42),
      ),
      const Duration(seconds: 58),
    );
  });

  test('does not flush the decoder when an already-live user scrubs right', () {
    expect(
      liveSeekTarget(
        const Duration(seconds: 60),
        const Duration(seconds: 60),
        currentPosition: const Duration(seconds: 58),
      ),
      isNull,
    );
  });
}
