import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_app/platform/playback_capability.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  group('PlaybackTarget.detect', () {
    test('maps Android and iOS to their own target', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(PlaybackTarget.detect(), PlaybackTarget.android);

      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(PlaybackTarget.detect(), PlaybackTarget.ios);
    });

    test('anything else (desktop, web) is unsupported', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      expect(PlaybackTarget.detect(), PlaybackTarget.unsupported);
    });
  });

  group('PlaybackTarget.canPlay — android (ExoPlayer)', () {
    const target = PlaybackTarget.android;

    test('plain HLS plays', () {
      expect(
        target.canPlay(
          const PlayableStream(url: 'x', format: StreamFormat.hls),
        ),
        isTrue,
      );
    });

    test('plain DASH plays — Android has no iOS-style format gate', () {
      expect(
        target.canPlay(
          const PlayableStream(url: 'x', format: StreamFormat.dash),
        ),
        isTrue,
      );
    });

    test('ClearKey and Widevine both play', () {
      for (final scheme in [DrmScheme.clearKey, DrmScheme.widevine]) {
        expect(
          target.canPlay(
            PlayableStream(
              url: 'x',
              format: StreamFormat.dash,
              drm: DrmConfig(scheme: scheme),
            ),
          ),
          isTrue,
          reason: '$scheme should play on Android',
        );
      }
    });

    test('an unsupported DRM scheme is refused', () {
      expect(
        target.canPlay(
          const PlayableStream(
            url: 'x',
            format: StreamFormat.dash,
            drm: DrmConfig(scheme: DrmScheme.unsupported),
          ),
        ),
        isFalse,
      );
    });
  });

  group('PlaybackTarget.canPlay — iOS (AVPlayer, clear HLS only)', () {
    const target = PlaybackTarget.ios;

    test('plain HLS plays', () {
      expect(
        target.canPlay(
          const PlayableStream(url: 'x', format: StreamFormat.hls),
        ),
        isTrue,
      );
    });

    test('DASH is refused even with no DRM — this integration sets none on iOS', () {
      expect(
        target.canPlay(
          const PlayableStream(url: 'x', format: StreamFormat.dash),
        ),
        isFalse,
      );
    });

    test('any DRM at all is refused, regardless of scheme or container', () {
      for (final scheme in [
        DrmScheme.clearKey,
        DrmScheme.widevine,
        DrmScheme.unsupported,
      ]) {
        expect(
          target.canPlay(
            PlayableStream(
              url: 'x',
              format: StreamFormat.hls,
              drm: DrmConfig(scheme: scheme),
            ),
          ),
          isFalse,
          reason: 'DRM scheme $scheme should never play on iOS here',
        );
      }
    });
  });

  group('PlaybackTarget.canPlay — unsupported (desktop/web)', () {
    test('refuses every stream — playback is not wired up at all', () {
      const target = PlaybackTarget.unsupported;
      expect(
        target.canPlay(
          const PlayableStream(url: 'x', format: StreamFormat.hls),
        ),
        isFalse,
      );
      expect(
        target.canPlay(
          const PlayableStream(url: 'x', format: StreamFormat.dash),
        ),
        isFalse,
      );
    });
  });
}
