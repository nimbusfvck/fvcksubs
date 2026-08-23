import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_app/player/diagnostics/player_diagnostics.dart';

void main() {
  test('safe playback url removes query tokens and fragments', () {
    expect(
      safePlaybackUrlForLog(
        'https://edge.example/live.m3u8?token=secret#fragment',
      ),
      'https://edge.example/live.m3u8',
    );
  });

  test('diagnostic text redacts tokens embedded in native errors', () {
    expect(
      redactPlaybackLogText(
        'HTTP 403: https://edge.example/segment.ts?token=secret, retry failed',
      ),
      'HTTP 403: https://edge.example/segment.ts, retry failed',
    );
  });

  test('invalid playback url is never printed verbatim', () {
    expect(safePlaybackUrlForLog('not a URL?token=secret'), '<invalid-url>');
  });

  group('isFatalPlayerError', () {
    // Captured from the iOS Simulator, which has no audio device for mpv.
    // Video kept decoding the whole time this line was being emitted.
    const audioDevice = 'Could not open/initialize audio device -> no sound.';

    test('losing audio is never fatal — video still plays without it', () {
      expect(
        isFatalPlayerError(audioDevice, playbackStarted: false),
        isFalse,
        reason: 'sound is not playback; the source is still watchable',
      );
      expect(isFatalPlayerError(audioDevice, playbackStarted: true), isFalse);
    });

    test('an error before playback starts is fatal — nothing ever played', () {
      expect(
        isFatalPlayerError('tcp: connection refused', playbackStarted: false),
        isTrue,
      );
    });

    test('the same error after frames flow is a hiccup, not a verdict', () {
      expect(
        isFatalPlayerError('tcp: connection refused', playbackStarted: true),
        isFalse,
      );
    });

    test('a null or empty error is treated like any other unstarted one', () {
      expect(isFatalPlayerError(null, playbackStarted: false), isTrue);
      expect(isFatalPlayerError('', playbackStarted: true), isFalse);
    });

    test('matching is case-insensitive — mpv casing is not a contract', () {
      expect(
        isFatalPlayerError(
          'COULD NOT OPEN/INITIALIZE AUDIO DEVICE',
          playbackStarted: false,
        ),
        isFalse,
      );
    });
  });
}
