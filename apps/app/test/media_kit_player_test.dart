import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_app/player/models/app_player_controller.dart';
import 'package:fvcksubs_app/player/state/playback_stall_detector.dart';
import 'package:fvcksubs_app/player/state/quality_preference_controller.dart';
import 'package:fvcksubs_app/player/widgets/media_kit_player.dart';
import 'package:fvcksubs_app/player/widgets/player_subtitle_style.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';

void main() {
  test('keeps the HLS cut workaround disabled for native track switching', () {
    expect(hlsCutWorkaroundEnabled, isFalse);
  });

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

  group('preferred quality track', () {
    AppQualityTrack track(int height, {int bitrate = 0}) => AppQualityTrack(
      id: '$height-$bitrate',
      height: height,
      bitrate: bitrate,
    );

    test('chooses the highest rendition at or below the cap', () {
      expect(
        preferredQualityTrack(
          tracks: [track(1080), track(720), track(480)],
          maxHeight: 720,
        )?.height,
        720,
      );
    });

    test('chooses the lowest rendition when every track exceeds the cap', () {
      expect(
        preferredQualityTrack(
          tracks: [track(1080), track(720)],
          maxHeight: 480,
        )?.height,
        720,
      );
    });

    test('leaves Auto untouched and ignores unusable tracks', () {
      expect(
        preferredQualityTrack(tracks: [track(0), track(-1)], maxHeight: 720),
        isNull,
      );
      expect(
        preferredQualityTrack(tracks: [track(720)], maxHeight: null),
        isNull,
      );
    });
  });

  group('startupMaxHeight', () {
    test('a viewer who chose nothing is kept off the largest rendition', () {
      expect(
        startupMaxHeight(preference: null, isLive: false),
        defaultStartupMaxHeight,
      );
      // Downloading and decoding 4K nobody asked for is the thing this
      // exists to prevent.
      expect(defaultStartupMaxHeight, lessThan(2160));
    });

    test('a viewer who chose is obeyed, higher or lower', () {
      expect(startupMaxHeight(preference: 2160, isLive: false), 2160);
      expect(startupMaxHeight(preference: 480, isLive: false), 480);
    });

    test('live keeps the channel to itself', () {
      expect(startupMaxHeight(preference: null, isLive: true), isNull);
      expect(startupMaxHeight(preference: 1080, isLive: true), 1080);
    });
  });

  group('vodHlsMpvOptions', () {
    test('on-demand HLS opens on the smallest rendition', () {
      // libmpv's own default is `max`; the wanted rendition arrives by
      // re-open once the track list is known.
      expect(vodHlsMpvOptions['hls-bitrate'], 'min');
    });
  });

  group('hlsBitrateForVariant', () {
    const uhd = AppQualityTrack(id: '1', height: 2160, bitrate: 1900000);
    const hd = AppQualityTrack(id: '2', height: 720, bitrate: 1500000);

    test('names the wanted rendition by its own bitrate', () {
      expect(hlsBitrateForVariant(wanted: hd, active: uhd), 1500000);
    });

    test('leaves a rendition already playing alone', () {
      expect(hlsBitrateForVariant(wanted: hd, active: hd), isNull);
    });

    test('gives up on a playlist that declares no bitrate', () {
      // Nothing to address it with: the mid-stream switch stays in charge.
      const unpriced = AppQualityTrack(id: '3', height: 720);
      expect(hlsBitrateForVariant(wanted: unpriced, active: uhd), isNull);
      expect(hlsBitrateForVariant(wanted: null, active: uhd), isNull);
    });
  });

  group('resolveSliceOffset', () {
    const start = Duration(minutes: 10);
    const full = Duration(minutes: 148);
    const remaining = Duration(minutes: 138);

    test('a cut describing what is left is placed at its start', () {
      expect(
        resolveSliceOffset(
          reportedDuration: remaining,
          sliceStart: start,
          sliceDuration: remaining,
          fullDuration: full,
        ),
        start,
      );
    });

    test('a stream that already knows the whole film needs no offset', () {
      expect(
        resolveSliceOffset(
          reportedDuration: full,
          sliceStart: start,
          sliceDuration: remaining,
          fullDuration: full,
        ),
        Duration.zero,
      );
    });

    test('nothing reported yet keeps the start it was opened at', () {
      expect(
        resolveSliceOffset(
          reportedDuration: Duration.zero,
          sliceStart: start,
          sliceDuration: remaining,
          fullDuration: full,
        ),
        start,
      );
    });
  });

  test('subtitle loaded after a cut uses the inverse cut clock', () {
    expect(
      subtitleDelaySeconds(const Duration(minutes: 10, milliseconds: 250)),
      -600.25,
    );
  });

  group('HLS audio selection', () {
    test('the original master keeps its native audio tracks', () {
      expect(
        usesSliceAudioTracks(sliceIsActive: false, hasSliceTracks: true),
        isFalse,
      );
    });

    test('a cut keeps the provider audio ladder available', () {
      expect(
        usesSliceAudioTracks(sliceIsActive: true, hasSliceTracks: true),
        isTrue,
      );
    });
  });

  group('HLS playlist bytes', () {
    test('decodes a valid UTF-8 playlist', () {
      expect(
        decodeHlsPlaylistBytes('#EXTM3U\n#EXTINF:2.0,\npart.m4s\n'.codeUnits),
        '#EXTM3U\n#EXTINF:2.0,\npart.m4s\n',
      );
    });

    test('rejects binary data instead of throwing in a background fetch', () {
      expect(decodeHlsPlaylistBytes(const [0x23, 0xff, 0x00]), isNull);
    });
  });

  group('isWithinBuffer', () {
    const value = AppPlayerValue(
      initialized: true,
      position: Duration(minutes: 3),
      bufferedPosition: Duration(minutes: 6),
      duration: Duration(minutes: 58),
    );

    test('a target already downloaded keeps frame accuracy', () {
      expect(isWithinBuffer(const Duration(minutes: 4), value), isTrue);
      expect(isWithinBuffer(const Duration(minutes: 6), value), isTrue);
    });

    test('a jump past the buffer gives it up', () {
      // The frames between where FFmpeg lands and the exact target would have
      // to be downloaded before the picture returns.
      expect(isWithinBuffer(const Duration(minutes: 10), value), isFalse);
    });

    test('a jump backwards gives it up', () {
      expect(isWithinBuffer(const Duration(minutes: 1), value), isFalse);
    });
  });

  group('mpvPlaybackTuning', () {
    test('on-demand playback leaves reconnect policy unset', () {
      final tuning = mpvPlaybackTuning(isLive: false);
      expect(tuning['stream-lavf-o'], isNull);
      expect(tuning['network-timeout'], '8');
    });

    test('live playback leaves reconnect policy unset', () {
      final tuning = mpvPlaybackTuning(isLive: true);
      expect(tuning['stream-lavf-o'], isNull);
      expect(tuning['network-timeout'], '8');
    });

    test('live playback prioritizes a stable in-memory buffer', () {
      final tuning = mpvPlaybackTuning(isLive: true);

      expect(tuning['cache'], 'yes');
      expect(tuning['cache-on-disk'], 'no');
      expect(tuning['cache-secs'], '45');
      expect(tuning['cache-pause-initial'], 'yes');
      expect(tuning['cache-pause-wait'], '3');
      expect(tuning['demuxer-max-bytes'], '${64 * 1024 * 1024}');
      expect(tuning['demuxer-max-back-bytes'], '${8 * 1024 * 1024}');
    });

    test('the rebuffer wait stays under the stall threshold', () {
      final wait = Duration(
        seconds: int.parse(
          mpvPlaybackTuning(isLive: true)['cache-pause-wait']!,
        ),
      );
      // A rebuffer that outlives the stall timer costs the source a
      // re-resolve while libmpv is still recovering from it.
      expect(wait, lessThan(PlaybackStallDetector().threshold));
    });

    test('on-demand HLS gives every segment its own connection', () {
      // A kept-alive connection leaves an undrained response body in front of
      // the request a far seek makes, and the read that follows never
      // returns — the freeze the viewer sees only when seeking out of the
      // buffered range.
      expect(vodHlsDemuxerLavfOptions['http_persistent'], '0');
      // Live reads sequentially and never seeks far, and pays the handshake
      // at the edge where there is no slack.
      expect(liveDemuxerLavfOptions.containsKey('http_persistent'), isFalse);
    });

    test('live playback joins the playlist behind the live edge', () {
      // Negative: counted back from the newest segment. FFmpeg's own default
      // is -3, so anything above it would shrink the cushion.
      final index = int.parse(liveDemuxerLavfOptions['live_start_index']!);
      expect(index, lessThan(-3));
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
