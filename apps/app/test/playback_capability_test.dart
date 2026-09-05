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

    test('maps macOS to its native target', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      expect(PlaybackTarget.detect(), PlaybackTarget.macos);
    });
  });

  group('PlaybackTarget.canPlay — Android', () {
    const target = PlaybackTarget.android;

    test('plain HLS plays', () {
      expect(
        target.canPlay(
          const PlayableStream(url: 'x', format: StreamFormat.hls),
        ),
        isTrue,
      );
    });

    test('plain DASH remains eligible for the native backend to try', () {
      expect(
        target.canPlay(
          const PlayableStream(url: 'x', format: StreamFormat.dash),
        ),
        isTrue,
      );
    });

    test('all DRM is refused by the unified video_player route', () {
      for (final scheme in [DrmScheme.clearKey, DrmScheme.widevine]) {
        expect(
          target.canPlay(
            PlayableStream(
              url: 'x',
              format: StreamFormat.dash,
              drm: DrmConfig(scheme: scheme),
            ),
          ),
          isFalse,
          reason:
              '$scheme requires a DRM license flow video_player does not provide',
        );
      }
    });

    test('an unsupported DRM scheme is refused too', () {
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

  group('PlaybackTarget.canPlay — iOS', () {
    const target = PlaybackTarget.ios;

    test('plain HLS plays', () {
      expect(
        target.canPlay(
          const PlayableStream(url: 'x', format: StreamFormat.hls),
        ),
        isTrue,
      );
    });

    test('clear DASH remains eligible for the native backend to try', () {
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
              PlayableStream(
                url: 'x',
                format: format,
                drm: DrmConfig(scheme: scheme),
              ),
            ),
            isFalse,
            reason: 'DRM scheme $scheme should never play on iOS — no CDM',
          );
        }
      }
    });

    test('matches macOS exactly — both use the same route', () {
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
          reason: 'iOS and macOS share the same diagnostic route',
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

  group('PlaybackTarget.canPlay — macOS', () {
    const target = PlaybackTarget.macos;

    test('clear HLS and DASH are eligible, while DRM is refused', () {
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
