import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_app/player/state/playback_stall_detector.dart';

void main() {
  final start = DateTime.utc(2026, 8, 29, 12, 0, 0);

  PlaybackStallDetector detector() =>
      PlaybackStallDetector(threshold: const Duration(seconds: 15));

  // A frozen buffered position by default: the fetch has stopped too, which
  // is what every case here except the rebuffer means by "not moving".
  bool feed(
    PlaybackStallDetector subject, {
    required int atSecond,
    required int positionSeconds,
    int bufferedSeconds = 0,
    bool isBuffering = true,
    bool isPlaying = false,
  }) => subject.sample(
    position: Duration(seconds: positionSeconds),
    bufferedPosition: Duration(seconds: bufferedSeconds),
    isBuffering: isBuffering,
    isPlaying: isPlaying,
    now: start.add(Duration(seconds: atSecond)),
  );

  test('advancing playback never stalls', () {
    final subject = detector();
    for (var second = 0; second < 120; second += 2) {
      expect(
        feed(
          subject,
          atSecond: second,
          positionSeconds: second,
          isBuffering: false,
          isPlaying: true,
        ),
        isFalse,
      );
    }
  });

  test('a frozen buffering position stalls once the threshold passes', () {
    final subject = detector();
    expect(feed(subject, atSecond: 0, positionSeconds: 100), isFalse);
    expect(feed(subject, atSecond: 10, positionSeconds: 100), isFalse);
    expect(feed(subject, atSecond: 14, positionSeconds: 100), isFalse);
    expect(feed(subject, atSecond: 15, positionSeconds: 100), isTrue);
  });

  test('a confirmed stall is reported exactly once', () {
    final subject = detector();
    feed(subject, atSecond: 0, positionSeconds: 100);
    expect(feed(subject, atSecond: 20, positionSeconds: 100), isTrue);
    expect(feed(subject, atSecond: 40, positionSeconds: 100), isFalse);
    expect(feed(subject, atSecond: 90, positionSeconds: 100), isFalse);
  });

  test('recovering playback re-arms the detector', () {
    final subject = detector();
    feed(subject, atSecond: 0, positionSeconds: 100);
    expect(feed(subject, atSecond: 20, positionSeconds: 100), isTrue);
    expect(feed(subject, atSecond: 22, positionSeconds: 101), isFalse);
    expect(feed(subject, atSecond: 40, positionSeconds: 101), isTrue);
  });

  test('a deliberate pause is not a stall, however long it lasts', () {
    final subject = detector();
    for (var second = 0; second < 600; second += 5) {
      expect(
        feed(
          subject,
          atSecond: second,
          positionSeconds: 100,
          isBuffering: false,
          isPlaying: false,
        ),
        isFalse,
      );
    }
  });

  test('resuming after a long pause does not count the paused time', () {
    final subject = detector();
    feed(
      subject,
      atSecond: 0,
      positionSeconds: 100,
      isBuffering: false,
      isPlaying: false,
    );
    feed(
      subject,
      atSecond: 300,
      positionSeconds: 100,
      isBuffering: false,
      isPlaying: false,
    );
    // Buffering starts only now; the clock starts here too.
    expect(feed(subject, atSecond: 301, positionSeconds: 100), isFalse);
    expect(feed(subject, atSecond: 310, positionSeconds: 100), isFalse);
    expect(feed(subject, atSecond: 316, positionSeconds: 100), isTrue);
  });

  test('a rebuffer that keeps filling is not a stall', () {
    final subject = detector();
    // libmpv holds the frame while the cushion refills. The position is
    // frozen throughout; only the buffered end moves.
    for (var second = 0; second < 60; second += 2) {
      expect(
        feed(
          subject,
          atSecond: second,
          positionSeconds: 100,
          bufferedSeconds: 100 + second,
        ),
        isFalse,
      );
    }
  });

  test('a rebuffer that stops filling stalls from the moment it stops', () {
    final subject = detector();
    feed(subject, atSecond: 0, positionSeconds: 100, bufferedSeconds: 100);
    feed(subject, atSecond: 10, positionSeconds: 100, bufferedSeconds: 110);
    // The fetch dies here; the threshold is measured from this sample.
    expect(
      feed(subject, atSecond: 20, positionSeconds: 100, bufferedSeconds: 110),
      isFalse,
    );
    expect(
      feed(subject, atSecond: 24, positionSeconds: 100, bufferedSeconds: 110),
      isFalse,
    );
    expect(
      feed(subject, atSecond: 26, positionSeconds: 100, bufferedSeconds: 110),
      isTrue,
    );
  });

  test('reset forgets an in-progress stall', () {
    final subject = detector();
    feed(subject, atSecond: 0, positionSeconds: 100);
    subject.reset();
    expect(feed(subject, atSecond: 20, positionSeconds: 100), isFalse);
    expect(feed(subject, atSecond: 40, positionSeconds: 100), isTrue);
  });

  test('a playing-but-frozen position stalls without a buffering flag', () {
    final subject = detector();
    feed(
      subject,
      atSecond: 0,
      positionSeconds: 100,
      isBuffering: false,
      isPlaying: true,
    );
    expect(
      feed(
        subject,
        atSecond: 20,
        positionSeconds: 100,
        isBuffering: false,
        isPlaying: true,
      ),
      isTrue,
    );
  });

  test('a deliberate interruption is given room before it counts', () {
    final detector = PlaybackStallDetector();
    final start = DateTime(2026);
    // The viewer swapped the audio track: libmpv refills from the new point
    // and the position sits still while it does.
    detector.defer(const Duration(seconds: 20), now: start);

    bool sampleAt(Duration elapsed) => detector.sample(
      position: const Duration(seconds: 30),
      bufferedPosition: const Duration(seconds: 30),
      isBuffering: true,
      isPlaying: false,
      now: start.add(elapsed),
    );

    // Well past the bare threshold, but inside the grace.
    expect(sampleAt(const Duration(seconds: 18)), isFalse);
    // The grace has run out; the threshold is then measured from the last
    // sample rather than firing the moment it lapses.
    expect(sampleAt(const Duration(seconds: 21)), isFalse);
    // A source that really did die is still caught, just later.
    expect(sampleAt(const Duration(seconds: 33)), isTrue);
  });

  test('a seek that only fills the buffer still counts as stalled', () {
    final detector = PlaybackStallDetector();
    final start = DateTime(2026);
    detector.defer(const Duration(seconds: 8), now: start);

    // The demuxer is downloading hard — the buffer climbs every sample — but
    // the picture never reaches the position that was asked for.
    bool sampleAt(Duration elapsed, {required int bufferedSeconds}) =>
        detector.sample(
          position: const Duration(minutes: 3),
          bufferedPosition: Duration(seconds: bufferedSeconds),
          isBuffering: true,
          isPlaying: false,
          now: start.add(elapsed),
        );

    expect(sampleAt(const Duration(seconds: 6), bufferedSeconds: 200), isFalse);
    expect(sampleAt(const Duration(seconds: 10), bufferedSeconds: 260), isFalse);
    expect(sampleAt(const Duration(seconds: 20), bufferedSeconds: 400), isFalse);
    expect(sampleAt(const Duration(seconds: 26), bufferedSeconds: 500), isTrue);
  });

  test('an ordinary rebuffer is still progress', () {
    final detector = PlaybackStallDetector();
    final start = DateTime(2026);
    // No deliberate interruption: libmpv is rebuilding its cushion, which the
    // watchdog must keep waiting through.
    bool sampleAt(Duration elapsed, {required int bufferedSeconds}) =>
        detector.sample(
          position: const Duration(minutes: 3),
          bufferedPosition: Duration(seconds: bufferedSeconds),
          isBuffering: true,
          isPlaying: false,
          now: start.add(elapsed),
        );

    expect(sampleAt(Duration.zero, bufferedSeconds: 200), isFalse);
    expect(sampleAt(const Duration(seconds: 20), bufferedSeconds: 260), isFalse);
    expect(sampleAt(const Duration(seconds: 40), bufferedSeconds: 320), isFalse);
  });
}
