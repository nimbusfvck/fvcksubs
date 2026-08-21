import 'package:better_player_plus/better_player_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_app/player/stream_player_mapping.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';

void main() {
  test('carries url and headers', () {
    final ds = betterPlayerDataSource(
      const PlayableStream(
        url: 'https://edge/live.m3u8',
        headers: {'Referer': 'https://x/'},
        format: StreamFormat.hls,
      ),
      isLive: true,
    );
    expect(ds.url, 'https://edge/live.m3u8');
    expect(ds.headers?['Referer'], 'https://x/');
    expect(ds.videoFormat, BetterPlayerVideoFormat.hls);
    expect(ds.drmConfiguration, isNull);
  });

  test('isLive: true maps to liveStream: true — no seek bar, no duration', () {
    final ds = betterPlayerDataSource(
      const PlayableStream(
        url: 'https://edge/live.m3u8',
        format: StreamFormat.hls,
      ),
      isLive: true,
    );
    expect(ds.liveStream, isTrue);
  });

  test('live streams never load subtitle tracks', () {
    final ds = betterPlayerDataSource(
      const PlayableStream(
        url: 'https://edge/live.m3u8',
        format: StreamFormat.hls,
        subtitles: [
          SubtitleTrack(language: 'en', url: 'https://subs/live.vtt'),
        ],
      ),
      isLive: true,
      preferredSubtitleLanguage: 'en',
    );

    expect(ds.subtitles, isNull);
  });

  test('isLive: false maps to liveStream: false — a real seek bar for VOD', () {
    // The bug M28's player update fixed: this used to be hardcoded `true`
    // unconditionally (ported as-is from back-pass, which only ever played
    // live sport), so a movie got the no-scrubbing live UI too.
    final ds = betterPlayerDataSource(
      const PlayableStream(
        url: 'https://edge/movie.m3u8',
        format: StreamFormat.hls,
      ),
      isLive: false,
    );
    expect(ds.liveStream, isFalse);
  });

  test('embedded previews use a small buffer and skip disk caching', () {
    final ds = betterPlayerDataSource(
      const PlayableStream(url: 'https://edge/preview.mp4'),
      isLive: false,
      preview: true,
    );

    expect(ds.cacheConfiguration?.useCache, isFalse);
    expect(ds.bufferingConfiguration.minBufferMs, 1500);
    expect(ds.bufferingConfiguration.maxBufferMs, 5000);
    expect(ds.bufferingConfiguration.bufferForPlaybackMs, 350);
    expect(ds.bufferingConfiguration.bufferForPlaybackAfterRebufferMs, 750);
  });

  test('maps DASH container', () {
    final ds = betterPlayerDataSource(
      const PlayableStream(
        url: 'https://edge/live.mpd',
        format: StreamFormat.dash,
      ),
      isLive: true,
    );
    expect(ds.videoFormat, BetterPlayerVideoFormat.dash);
  });

  test('maps ClearKey DRM to inline clearKey', () {
    final ds = betterPlayerDataSource(
      const PlayableStream(
        url: 'https://edge/live.mpd',
        format: StreamFormat.dash,
        drm: DrmConfig(scheme: DrmScheme.clearKey, clearKeyJson: '{"keys":[]}'),
      ),
      isLive: true,
    );
    expect(ds.drmConfiguration?.drmType, BetterPlayerDrmType.clearKey);
    expect(ds.drmConfiguration?.clearKey, '{"keys":[]}');
  });

  test('maps Widevine DRM to a license url plus headers', () {
    final ds = betterPlayerDataSource(
      const PlayableStream(
        url: 'https://edge/live.mpd',
        headers: {'User-Agent': 'UA'},
        format: StreamFormat.dash,
        drm: DrmConfig(scheme: DrmScheme.widevine, licenseUrl: 'https://lic/'),
      ),
      isLive: true,
    );
    expect(ds.drmConfiguration?.drmType, BetterPlayerDrmType.widevine);
    expect(ds.drmConfiguration?.licenseUrl, 'https://lic/');
    expect(ds.drmConfiguration?.headers?['User-Agent'], 'UA');
  });

  test('maps subtitle tracks — known language gets flag + native name', () {
    final ds = betterPlayerDataSource(
      const PlayableStream(
        url: 'https://edge/movie.m3u8',
        format: StreamFormat.hls,
        subtitles: [
          SubtitleTrack(language: 'en', url: 'https://subs/en.srt'),
          SubtitleTrack(language: 'id', url: 'https://subs/id.srt'),
        ],
      ),
      isLive: false,
    );
    expect(ds.subtitles, hasLength(2));
    expect(ds.subtitles?[0].type, BetterPlayerSubtitlesSourceType.network);
    expect(ds.subtitles?[0].name, '🇬🇧 English');
    expect(ds.subtitles?[0].urls, ['https://subs/en.srt']);
    expect(ds.subtitles?[1].name, '🇮🇩 Indonesia');
  });

  test('no preferred subtitle language means nothing is pre-selected', () {
    final ds = betterPlayerDataSource(
      const PlayableStream(
        url: 'https://edge/movie.m3u8',
        format: StreamFormat.hls,
        subtitles: [
          SubtitleTrack(language: 'en', url: 'https://subs/en.srt'),
          SubtitleTrack(language: 'id', url: 'https://subs/id.srt'),
        ],
      ),
      isLive: false,
    );
    expect(ds.subtitles!.every((s) => s.selectedByDefault != true), isTrue);
  });

  test(
    'a track matching the preferred subtitle language is pre-selected from the stream',
    () {
      final ds = betterPlayerDataSource(
        const PlayableStream(
          url: 'https://edge/movie.m3u8',
          format: StreamFormat.hls,
          subtitles: [
            SubtitleTrack(language: 'en', url: 'https://subs/en.srt'),
            SubtitleTrack(language: 'id', url: 'https://subs/id.srt'),
          ],
        ),
        isLive: false,
        preferredSubtitleLanguage: 'id',
      );
      final byLanguage = {for (final s in ds.subtitles!) s.name: s};
      expect(byLanguage['🇮🇩 Indonesia']!.selectedByDefault, isTrue);
      expect(byLanguage['🇬🇧 English']!.selectedByDefault, isNot(true));
    },
  );

  test('the preferred subtitle is the matching track from the stream', () {
    final subtitle = preferredSubtitleSource(const [
      SubtitleTrack(language: 'en', url: 'https://subs/en.srt'),
      SubtitleTrack(language: 'id', url: 'https://subs/id.srt'),
    ], 'id');

    expect(subtitle?.urls, ['https://subs/id.srt']);
    expect(subtitle?.selectedByDefault, isTrue);
  });

  test('a region variant matches by primary language subtag', () {
    final ds = betterPlayerDataSource(
      const PlayableStream(
        url: 'https://edge/movie.m3u8',
        format: StreamFormat.hls,
        subtitles: [
          SubtitleTrack(language: 'en-US', url: 'https://subs/en-us.srt'),
        ],
      ),
      isLive: false,
      preferredSubtitleLanguage: 'en',
    );
    expect(ds.subtitles!.single.selectedByDefault, isTrue);
  });

  test('a preferred language with no matching track selects nothing', () {
    final ds = betterPlayerDataSource(
      const PlayableStream(
        url: 'https://edge/movie.m3u8',
        format: StreamFormat.hls,
        subtitles: [SubtitleTrack(language: 'en', url: 'https://subs/en.srt')],
      ),
      isLive: false,
      preferredSubtitleLanguage: 'id',
    );
    expect(ds.subtitles!.every((s) => s.selectedByDefault != true), isTrue);
  });

  test('tracks are not restricted to hardcoded languages', () {
    final ds = betterPlayerDataSource(
      const PlayableStream(
        url: 'https://edge/movie.m3u8',
        format: StreamFormat.hls,
        subtitles: [
          SubtitleTrack(language: 'pt-BR', url: 'https://subs/pt-br.srt'),
          SubtitleTrack(language: 'fr', url: 'https://subs/fr.srt'),
          SubtitleTrack(language: 'en', url: 'https://subs/en.srt'),
          SubtitleTrack(language: 'ar', url: 'https://subs/ar.srt'),
        ],
      ),
      isLive: false,
    );
    expect(ds.subtitles, hasLength(4));
    expect(ds.subtitles?.map((track) => track.name), [
      '🇸🇦 العربية',
      '🇬🇧 English',
      '🇫🇷 Français',
      '🇧🇷 Português (BR)',
    ]);
  });

  test('non-preferred languages remain available', () {
    final ds = betterPlayerDataSource(
      const PlayableStream(
        url: 'https://edge/movie.m3u8',
        format: StreamFormat.hls,
        subtitles: [
          SubtitleTrack(language: 'pt-BR', url: 'https://subs/pt-br.srt'),
          SubtitleTrack(language: 'fr', url: 'https://subs/fr.srt'),
        ],
      ),
      isLive: false,
    );
    expect(ds.subtitles, hasLength(2));
    expect(ds.subtitles?.map((track) => track.name), [
      '🇫🇷 Français',
      '🇧🇷 Português (BR)',
    ]);
  });

  test('region-tagged English gets flag + region disambiguator', () {
    final ds = betterPlayerDataSource(
      const PlayableStream(
        url: 'https://edge/movie.m3u8',
        format: StreamFormat.hls,
        subtitles: [
          SubtitleTrack(language: 'en-US', url: 'https://subs/en-us.srt'),
          SubtitleTrack(language: 'en-GB', url: 'https://subs/en-gb.srt'),
        ],
      ),
      isLive: false,
    );
    expect(ds.subtitles?[0].name, '🇬🇧 English (GB)');
    expect(ds.subtitles?[1].name, '🇺🇸 English (US)');
  });

  test('subtitle tracks are sorted: en before id', () {
    final ds = betterPlayerDataSource(
      const PlayableStream(
        url: 'https://edge/movie.m3u8',
        format: StreamFormat.hls,
        subtitles: [
          SubtitleTrack(language: 'id', url: 'https://subs/id.srt'),
          SubtitleTrack(language: 'en', url: 'https://subs/en.srt'),
        ],
      ),
      isLive: false,
    );
    // Alphabetical by primary tag: en < id.
    expect(ds.subtitles?[0].name, contains('English'));
    expect(ds.subtitles?[1].name, contains('Indonesia'));
  });

  test('no subtitles maps to null, not an empty list', () {
    final ds = betterPlayerDataSource(
      const PlayableStream(url: 'https://edge/movie.m3u8'),
      isLive: false,
    );
    expect(ds.subtitles, isNull);
  });

  group('subtitlesForPicker', () {
    test('keeps every language and sorts by language tag', () {
      final result = subtitlesForPicker(const [
        SubtitleTrack(language: 'fr', url: 'https://subs/fr.srt'),
        SubtitleTrack(language: 'id', url: 'https://subs/id.srt'),
        SubtitleTrack(language: 'en', url: 'https://subs/en.srt'),
      ]);
      expect(result.map((t) => t.language), ['en', 'fr', 'id']);
    });

    test('drops a duplicate of an already-seen url', () {
      // A provider's own track and a fallback provider's copy of the same
      // file sometimes both end up in the list — same subtitle, two labels.
      final result = subtitlesForPicker(const [
        SubtitleTrack(
          language: 'id',
          url: 'https://subs/id.srt',
          label: 'Indonesian',
        ),
        SubtitleTrack(
          language: 'id',
          url: 'https://subs/id.srt',
          label: 'Bahasa Indonesia (shegu)',
        ),
      ]);
      expect(result, hasLength(1));
      expect(result.single.label, 'Indonesian');
    });

    test(
      'keeps every same-language track, unlike the flattened source list',
      () {
        final result = subtitlesForPicker(const [
          SubtitleTrack(
            language: 'en',
            url: 'https://subs/en-1.srt',
            label: 'English',
          ),
          SubtitleTrack(
            language: 'en',
            url: 'https://subs/en-2.srt',
            label: 'English SDH',
          ),
        ]);
        expect(result, hasLength(2));
        expect(result.map((t) => t.label), ['English', 'English SDH']);
      },
    );
  });

  group('subtitleLanguageLabel', () {
    test('known languages get flag + native name', () {
      expect(subtitleLanguageLabel('en'), '🇬🇧 English');
      expect(subtitleLanguageLabel('id'), '🇮🇩 Indonesia');
    });

    test('region-tagged codes get a disambiguator', () {
      expect(subtitleLanguageLabel('en-US'), '🇺🇸 English (US)');
    });

    test('unknown codes fall back to the raw code, upper-cased', () {
      expect(subtitleLanguageLabel('xx-yy'), 'XX-YY');
    });
  });

  group('subtitleIndicatorLabel', () {
    test('keeps a leading flag without the language name', () {
      expect(subtitleIndicatorLabel('🇮🇩 Indonesia'), '🇮🇩');
    });

    test('normalizes a built-in language name to its flag', () {
      expect(subtitleIndicatorLabel('INDONESIA'), '🇮🇩');
      expect(subtitleIndicatorLabel('Indonesian SDH'), '🇮🇩');
    });

    test('falls back to CC when the source name is unknown', () {
      expect(subtitleIndicatorLabel('Custom captions'), 'CC');
    });
  });
}
