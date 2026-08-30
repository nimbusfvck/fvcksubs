import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_app/player/widgets/media_kit_player.dart';
import 'package:fvcksubs_app/player/widgets/player_subtitle_style.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';

void main() {
  test('deferred subtitle retries after a failed first attempt', () {
    expect(
      shouldApplyDeferredSubtitle(
        mounted: true,
        expectedRevision: 1,
        currentRevision: 1,
      ),
      isTrue,
    );
  });

  test('deferred subtitle does not overwrite a newer user selection', () {
    expect(
      shouldApplyDeferredSubtitle(
        mounted: true,
        expectedRevision: 1,
        currentRevision: 2,
      ),
      isFalse,
    );
    expect(
      shouldApplyDeferredSubtitle(
        mounted: false,
        expectedRevision: 1,
        currentRevision: 1,
      ),
      isFalse,
    );
  });

  test('subtitle appearance is shared by native backends', () {
    expect(playerSubtitleFontSize, 24);
    expect(playerSubtitleTextStyle.fontSize, playerSubtitleFontSize);
    expect(
      playerSubtitleTextStyle.backgroundColor,
      playerSubtitleBackgroundColor,
    );
  });

  group('preferred subtitle track', () {
    const indonesian = SubtitleTrack(
      language: 'Indonesian',
      url: 'https://subs.example/id.srt',
    );
    const english = SubtitleTrack(
      language: 'en',
      url: 'https://subs.example/en.srt',
    );

    test('matches a track the upstream named, not just a bare subtag', () {
      // VidEasy sends the display label, MovieBox the legacy "in" tag; both
      // are the language the viewer asked for.
      for (final language in const ['Indonesian', 'in', 'ind', 'id-ID']) {
        final track = SubtitleTrack(
          language: language,
          url: 'https://subs.example/$language.srt',
        );
        expect(
          preferredSubtitleTrack(
            tracks: [english, track],
            isLive: false,
            preferredLanguage: 'id',
          ),
          track,
          reason: 'language "$language" should match the "id" preference',
        );
      }
    });

    test('an explicit external pick outranks the source own track', () {
      const external = SubtitleTrack(
        language: 'id',
        url: 'https://shegu.example/id.srt',
      );
      expect(
        preferredSubtitleTrack(
          tracks: const [indonesian],
          isLive: false,
          preferredLanguage: 'id',
          preferredExternal: external,
        ),
        external,
      );
    });

    test('no preference, no match, and live streams select nothing', () {
      expect(
        preferredSubtitleTrack(tracks: const [indonesian], isLive: false),
        isNull,
      );
      expect(
        preferredSubtitleTrack(
          tracks: const [english],
          isLive: false,
          preferredLanguage: 'id',
        ),
        isNull,
      );
      expect(
        preferredSubtitleTrack(
          tracks: const [indonesian],
          isLive: true,
          preferredLanguage: 'id',
        ),
        isNull,
      );
    });
  });

  group('mpvPlaybackTuning', () {
    test('always asks FFmpeg to reconnect a dropped connection', () {
      for (final isLive in [true, false]) {
        final tuning = mpvPlaybackTuning(isLive: isLive);
        expect(tuning['stream-lavf-o'], contains('reconnect=1'));
        expect(tuning['stream-lavf-o'], contains('reconnect_streamed=1'));
        expect(tuning['network-timeout'], '8');
      }
    });

    test('live playback prioritizes a stable in-memory buffer', () {
      final tuning = mpvPlaybackTuning(isLive: true);

      expect(tuning['cache'], 'yes');
      expect(tuning['cache-on-disk'], 'no');
      expect(tuning['cache-secs'], '45');
      expect(tuning['cache-pause-initial'], 'yes');
      expect(tuning['cache-pause-wait'], '5');
      expect(tuning['demuxer-max-bytes'], '${64 * 1024 * 1024}');
      expect(tuning['demuxer-max-back-bytes'], '${8 * 1024 * 1024}');
    });

    test('on-demand playback keeps media_kit\'s own cache defaults', () {
      final tuning = mpvPlaybackTuning(isLive: false);
      expect(tuning.containsKey('cache'), isFalse);
      expect(tuning.containsKey('cache-on-disk'), isFalse);
      expect(tuning.containsKey('cache-secs'), isFalse);
      expect(tuning.containsKey('cache-pause-initial'), isFalse);
      expect(tuning.containsKey('cache-pause-wait'), isFalse);
      expect(tuning.containsKey('demuxer-max-bytes'), isFalse);
      expect(tuning.containsKey('demuxer-max-back-bytes'), isFalse);
    });
  });
}
