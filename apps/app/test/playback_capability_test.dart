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

    test('Widevine with a license URL is eligible', () {
      expect(
        target.canPlay(
          const PlayableStream(
            url: 'x',
            format: StreamFormat.dash,
            drm: DrmConfig(
              scheme: DrmScheme.widevine,
              licenseUrl: 'https://license.example/widevine',
            ),
          ),
        ),
        isTrue,
      );
    });

    test('other DRM schemes and incomplete Widevine are refused', () {
      for (final stream in [
        const PlayableStream(
          url: 'x',
          format: StreamFormat.dash,
          drm: DrmConfig(scheme: DrmScheme.clearKey),
        ),
        const PlayableStream(
          url: 'x',
          format: StreamFormat.dash,
          drm: DrmConfig(scheme: DrmScheme.fairPlay),
        ),
        const PlayableStream(
          url: 'x',
          format: StreamFormat.dash,
          drm: DrmConfig(scheme: DrmScheme.widevine),
        ),
      ]) {
        expect(target.canPlay(stream), isFalse);
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

    test('FairPlay with certificate and license URLs is eligible', () {
      expect(
        target.canPlay(
          const PlayableStream(
            url: 'x',
            format: StreamFormat.hls,
            drm: DrmConfig(
              scheme: DrmScheme.fairPlay,
              certificateUrl: 'https://license.example/fairplay.cer',
              licenseUrl: 'https://license.example/fairplay',
            ),
          ),
        ),
        isTrue,
      );
    });

    test('other DRM schemes and incomplete FairPlay are refused', () {
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
        );
      }
      expect(
        target.canPlay(
          const PlayableStream(
            url: 'x',
            format: StreamFormat.hls,
            drm: DrmConfig(
              scheme: DrmScheme.fairPlay,
              licenseUrl: 'https://license.example/fairplay',
            ),
          ),
        ),
        isFalse,
      );
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

    test(
      'clear HLS and DASH are eligible, while only FairPlay DRM is allowed',
      () {
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
              drm: DrmConfig(
                scheme: DrmScheme.fairPlay,
                certificateUrl: 'https://license.example/fairplay.cer',
                licenseUrl: 'https://license.example/fairplay',
              ),
            ),
          ),
          isTrue,
        );
      },
    );
  });
}
