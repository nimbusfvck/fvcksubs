import '../models/app_player_controller.dart';

const Duration liveEdgeSnapThreshold = Duration(seconds: 2);
const Duration liveEdgeSeekBackoff = Duration(seconds: 2);
const Duration liveEdgeSyncTolerance = Duration(seconds: 5);

Duration liveSeekEdge(AppPlayerValue? value) {
  if (value == null) return Duration.zero;
  var edge = value.duration;
  if (value.position > edge) edge = value.position;
  if (value.bufferedPosition > edge) edge = value.bufferedPosition;
  return edge;
}

/// The furthest buffered point used for the seekbar's secondary track.
Duration bufferedSeekEdge(AppPlayerValue? value) {
  if (value == null) return Duration.zero;
  return value.bufferedPosition > value.position
      ? value.bufferedPosition
      : value.position;
}

/// Converts a rightmost live scrub into a safe seek near the live edge.
///
/// Seeking to the exact end of a dynamic DASH window can flush the decoder at
/// a position whose segment is not available yet. If playback is already live,
/// avoid that redundant flush entirely. Otherwise stay one small segment
/// behind the edge while remaining inside the LIVE indicator tolerance.
Duration? liveSeekTarget(
  Duration target,
  Duration edge, {
  required Duration currentPosition,
}) {
  if (edge <= Duration.zero) return target;
  final snapStart = edge - liveEdgeSnapThreshold;
  if (target < snapStart) return target;
  if (isAtLiveEdge(currentPosition, edge)) return null;

  final safeEdge = edge - liveEdgeSeekBackoff;
  return safeEdge > Duration.zero ? safeEdge : Duration.zero;
}

/// Whether playback is close enough to the current live edge to be in sync.
bool isAtLiveEdge(Duration position, Duration edge) {
  if (edge <= Duration.zero) return true;
  return position >= edge - liveEdgeSyncTolerance;
}

/// Advances a live timeline while playback is intentionally paused.
Duration liveEdgeAfterPause(Duration edge, Duration pausedFor) =>
    pausedFor > Duration.zero ? edge + pausedFor : edge;
