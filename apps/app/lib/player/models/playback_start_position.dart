/// A position applied after initialization and before the first play request.
class PlaybackStartPosition {
  const PlaybackStartPosition.resume(this.position) : resume = true;
  const PlaybackStartPosition.exact(this.position) : resume = false;

  final Duration position;
  final bool resume;

  Duration? target(Duration duration, {required bool isLive}) {
    if (isLive || position <= Duration.zero || duration <= Duration.zero) {
      return null;
    }
    if (resume &&
        (position < const Duration(seconds: 5) ||
            duration - position < const Duration(seconds: 30))) {
      return null;
    }
    return position > duration ? duration : position;
  }
}
