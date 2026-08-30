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
}
