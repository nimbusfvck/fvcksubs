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

    test('maps macOS to its native MediaKit target', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      expect(PlaybackTarget.detect(), PlaybackTarget.macos);
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

  group('PlaybackTarget.canPlay — iOS (libmpv, clear containers)', () {
    const target = PlaybackTarget.ios;

    test('plain HLS plays', () {
      expect(
        target.canPlay(
          const PlayableStream(url: 'x', format: StreamFormat.hls),
        ),
        isTrue,
      );
    });

    // iOS moved off AVPlayer, which refused DASH outright and trusted a
    // segment's declared MIME type. libmpv reads both containers.
    test('clear DASH plays now that iOS runs on libmpv', () {
      expect(
        target.canPlay(
          const PlayableStream(url: 'x', format: StreamFormat.dash),
        ),
        isTrue,
      );
    });

    test('any DRM at all is refused, regardless of scheme or container', () {
      for (final scheme in [
        DrmScheme.clearKey,
        DrmScheme.widevine,
        DrmScheme.unsupported,
      ]) {
        for (final format in [StreamFormat.hls, StreamFormat.dash]) {
          expect(
            target.canPlay(
              PlayableStream(url: 'x', format: format, drm: DrmConfig(scheme: scheme)),
            ),
            isFalse,
            reason: 'DRM scheme $scheme should never play on iOS — no CDM',
          );
        }
      }
    });

    test('matches macOS exactly — both run the same player', () {
      for (final stream in [
        const PlayableStream(url: 'x', format: StreamFormat.hls),
        const PlayableStream(url: 'x', format: StreamFormat.dash),
        const PlayableStream(url: 'x', format: StreamFormat.other),
        const PlayableStream(
          url: 'x',
          format: StreamFormat.hls,
          drm: DrmConfig(scheme: DrmScheme.clearKey),
        ),
      ]) {
        expect(
          target.canPlay(stream),
          PlaybackTarget.macos.canPlay(stream),
          reason: 'iOS and macOS share a backend, so they must agree',
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

  group('PlaybackTarget.canPlay — macOS (MediaKit)', () {
    const target = PlaybackTarget.macos;

    test('clear HLS and DASH play, while DRM is refused', () {
      expect(
        target.canPlay(
          const PlayableStream(url: 'x', format: StreamFormat.hls),
        ),
        isTrue,
      );
      expect(
        target.canPlay(
          const PlayableStream(url: 'x', format: StreamFormat.dash),
        ),
        isTrue,
      );
      expect(
        target.canPlay(
          const PlayableStream(
            url: 'x',
            format: StreamFormat.dash,
            drm: DrmConfig(scheme: DrmScheme.widevine),
          ),
        ),
        isFalse,
      );
    });
  });
}
