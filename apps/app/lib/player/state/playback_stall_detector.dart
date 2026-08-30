/// Notices playback that has stopped moving without reporting a failure.
///
/// A dead signed URL does not surface as an error on either backend. libmpv
/// keeps the file open and flips to `paused-for-cache`; ExoPlayer retries the
/// load. Both leave the app watching a spinner with no event to react to, so
/// the only reliable signal is the one the user sees: buffering, and a
/// position that has stopped advancing.
library;

/// Confirms a stall once [threshold] passes with playback wanted but frozen.
///
/// Fed samples on a timer rather than on value changes — a frozen player is
/// precisely the case that emits no changes.
class PlaybackStallDetector {
  PlaybackStallDetector({this.threshold = const Duration(seconds: 15)});

  /// How long a frozen position must persist before it counts as a stall.
  ///
  /// Comfortably past one aborted request and its retry — libmpv is given an
  /// eight-second network timeout — so an ordinary hiccup resolves itself
  /// rather than costing a re-resolve, while a dead URL is caught quickly.
  final Duration threshold;

  Duration? _lastPosition;
  Duration? _lastBufferedPosition;
  DateTime? _movingAt;
  bool _reported = false;

  /// Records one sample and returns whether this sample confirms a stall.
  ///
  /// Returns `true` exactly once per stall; further samples return `false`
  /// until playback makes progress again, so a caller can act without
  /// debouncing.
  ///
  /// A rebuffer is progress. libmpv holds the picture until it has rebuilt
  /// its cushion, and on a live stream that cushion only refills as the
  /// broadcast produces it — the position is frozen for as long as it takes,
  /// while [bufferedPosition] climbs the whole time. Re-resolving there
  /// destroys a stream that was seconds from resuming and starts the wait
  /// over. Only a player fetching nothing *and* showing nothing has stalled.
  bool sample({
    required Duration position,
    required Duration bufferedPosition,
    required bool isBuffering,
    required bool isPlaying,
    required DateTime now,
  }) {
    if (position != _lastPosition ||
        bufferedPosition != _lastBufferedPosition) {
      _lastPosition = position;
      _lastBufferedPosition = bufferedPosition;
      _movingAt = now;
      _reported = false;
      return false;
    }

    // A deliberate pause freezes the position too. Only a player that is
    // trying to make progress and failing counts, so a pause keeps the clock
    // at the present and the stall is measured from the resume.
    if (!isBuffering && !isPlaying) {
      _movingAt = now;
      return false;
    }

    final movingAt = _movingAt ??= now;
    if (_reported || now.difference(movingAt) < threshold) return false;
    _reported = true;
    return true;
  }

  /// Forgets the current stall, for a swap that restarts playback.
  void reset() {
    _lastPosition = null;
    _lastBufferedPosition = null;
    _movingAt = null;
    _reported = false;
  }
}
