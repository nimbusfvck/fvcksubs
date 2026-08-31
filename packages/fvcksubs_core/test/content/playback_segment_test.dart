import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:test/test.dart';

void main() {
  test('playback segment round-trips in integer milliseconds', () {
    const segment = PlaybackSegment(
      type: PlaybackSegmentType.intro,
      startMs: 42_000,
      endMs: 128_500,
    );

    expect(PlaybackSegment.fromJson(segment.toJson()), segment);
  });

  test('unknown segment types remain non-actionable', () {
    final segment = PlaybackSegment.fromJson({
      'type': 'future-marker',
      'startMs': 100,
      'endMs': 200,
    });

    expect(segment.type, PlaybackSegmentType.unknown);
  });

  test('invalid ranges are rejected', () {
    expect(
      () => PlaybackSegment.fromJson({
        'type': 'intro',
        'startMs': 200,
        'endMs': 200,
      }),
      throwsFormatException,
    );
  });
}
