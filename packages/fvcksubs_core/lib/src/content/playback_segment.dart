import 'package:equatable/equatable.dart';

import '../json_util.dart';

/// A skip-able interval in an episodic video.
///
/// Times cross the extension boundary as integer milliseconds so providers do
/// not lose precision while the app converts them to [Duration] values.
enum PlaybackSegmentType {
  /// Opening sequence.
  intro,

  /// Previously shown story recap.
  recap,

  /// Closing sequence.
  outro,

  /// A provider type this app does not currently expose as an action.
  unknown,
}

/// One provider-supplied playback interval.
class PlaybackSegment extends Equatable {
  /// Creates a playback segment.
  const PlaybackSegment({
    required this.type,
    required this.startMs,
    required this.endMs,
  });

  /// Decodes and validates a segment returned by an extension.
  factory PlaybackSegment.fromJson(Map<String, Object?> json) {
    final start = json['startMs'];
    final end = json['endMs'];
    if (start is! num || start.toInt() != start || start < 0) {
      throw const FormatException(
        'segment.startMs must be a non-negative integer',
      );
    }
    if (end is! num || end.toInt() != end || end <= start) {
      throw const FormatException(
        'segment.endMs must be an integer greater than startMs',
      );
    }
    return PlaybackSegment(
      type: enumByName(
        PlaybackSegmentType.values,
        json['type'],
        orElse: PlaybackSegmentType.unknown,
      ),
      startMs: start.toInt(),
      endMs: end.toInt(),
    );
  }

  /// Segment category.
  final PlaybackSegmentType type;

  /// Inclusive start time in milliseconds.
  final int startMs;

  /// Exclusive end time in milliseconds.
  final int endMs;

  /// Encodes this segment for the extension boundary.
  Map<String, Object?> toJson() => {
    'type': type.name,
    'startMs': startMs,
    'endMs': endMs,
  };

  @override
  List<Object?> get props => [type, startMs, endMs];
}
