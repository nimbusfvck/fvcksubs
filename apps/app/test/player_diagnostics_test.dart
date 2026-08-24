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

    test('a failed external subtitle is not a video failure', () {
      expect(
        isFatalPlayerError(
          'Can not open external file https:subtitles.shegu.st',
          playbackStarted: false,
          subtitleUrl: 'https://subtitles.shegu.st/episode.vtt',
        ),
        isFalse,
      );
    });

    test('an external file error for another host remains fatal', () {
      expect(
        isFatalPlayerError(
          'Can not open external file https:video.example/episode.m3u8',
          playbackStarted: false,
          subtitleUrl: 'https://subtitles.shegu.st/episode.vtt',
        ),
        isTrue,
      );
    });

    test('a failed external audio track is not a video failure', () {
      expect(
        isFatalPlayerError(
          'Can not open external file https:audio.example/track.aac',
          playbackStarted: false,
          audioUrl: 'https://audio.example/track.aac',
        ),
        isFalse,
      );
    });

    test('a known hardware warning is not a video failure', () {
      expect(
        isFatalPlayerError(
          'decoder warning: no hardware device',
          playbackStarted: false,
        ),
        isFalse,
      );
    });

    test('generic codec and format failures are fatal before playback', () {
      expect(
        isFatalPlayerError(
          'Failed to recognize file format.',
          playbackStarted: false,
        ),
        isTrue,
      );
      expect(
        isFatalPlayerError('Could not open codec.', playbackStarted: false),
        isTrue,
      );
    });

    test('same-host audio failure is ignored only when its path matches', () {
      expect(
        isFatalPlayerError(
          'Can not open external file https:media.example/audio.aac',
          playbackStarted: false,
          audioUrl: 'https://media.example/audio.aac',
        ),
        isFalse,
      );
      expect(
        isFatalPlayerError(
          'HTTP 403 https:media.example/video.m3u8',
          playbackStarted: false,
          audioUrl: 'https://media.example/audio.m3u8',
        ),
        isTrue,
      );
    });

    test('a pre-start error tied to the video remains fatal', () {
      expect(
        isFatalPlayerError(
          'Could not open https:video.example/main.m3u8',
          playbackStarted: false,
        ),
        isTrue,
      );
    });
  });
}
