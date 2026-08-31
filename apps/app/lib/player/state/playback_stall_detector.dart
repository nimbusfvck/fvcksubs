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
  DateTime? _quietUntil;
  bool _awaitingPosition = false;
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
    final quietUntil = _quietUntil;
    if (quietUntil != null) {
      if (now.isBefore(quietUntil)) {
        _lastPosition = position;
        _lastBufferedPosition = bufferedPosition;
        _movingAt = now;
        _reported = false;
        return false;
      }
      _quietUntil = null;
    }

    // A rebuffer counts as progress, except while a deliberate interruption
    // is still owed a picture. A seek that FFmpeg lands short of turns into a
    // download that fetches segment after segment without ever reaching the
    // position asked for: the buffer climbs the whole time, so treating that
    // as progress leaves the watchdog asleep and the viewer on a spinner that
    // never ends. Until the position itself moves, only the position counts.
    final positionMoved = position != _lastPosition;
    final progressed =
        positionMoved ||
        (!_awaitingPosition && bufferedPosition != _lastBufferedPosition);
    _lastPosition = position;
    _lastBufferedPosition = bufferedPosition;
    if (progressed) {
      if (positionMoved) _awaitingPosition = false;
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
    _quietUntil = null;
    _awaitingPosition = false;
    _reported = false;
  }

  /// Holds the watchdog off for [grace] after a deliberate interruption.
  ///
  /// A seek and an audio-track switch both freeze the position on purpose:
  /// libmpv throws its cushion away and refills from the new point, and on a
  /// slow upstream that takes longer than [threshold]. Nothing in the signals
  /// available tells that apart from a source that died, so the viewer's own
  /// action is what says so — without it, asking for another audio track
  /// re-resolves the source, restarts playback and drops the track that was
  /// chosen, which is the "stuck" the viewer sees.
  void defer(Duration grace, {required DateTime now}) {
    reset();
    _quietUntil = now.add(grace);
    _awaitingPosition = true;
  }
}
