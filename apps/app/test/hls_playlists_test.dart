import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_app/player/mappers/hls_playlists.dart';

final _base = Uri.parse(
  'https://media.flystream.net/source-hls/abc/index.m3u8',
);

/// Shaped after FlyStream's own master: a 4K HEVC rung above three AVC ones,
/// and audio in a group of its own whose renditions carry a name but no
/// language.
const _master = '''
#EXTM3U
#EXT-X-VERSION:7
#EXT-X-INDEPENDENT-SEGMENTS
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",NAME="Track 1, Dub",DEFAULT=YES,AUTOSELECT=YES,URI="asset/a-1.ts"
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",NAME="Track 2",DEFAULT=NO,AUTOSELECT=YES,URI="asset/a-2.ts"
#EXT-X-STREAM-INF:BANDWIDTH=16000000,RESOLUTION=3840x2160,CODECS="hvc1.1.2.L150.B0",AUDIO="audio"
asset/v-2160.ts
#EXT-X-STREAM-INF:BANDWIDTH=6000000,RESOLUTION=1920x1080,CODECS="avc1.4D4032",AUDIO="audio"
asset/v-1080.ts
#EXT-X-STREAM-INF:BANDWIDTH=3000000,RESOLUTION=1280x720,CODECS="avc1.4D4020",AUDIO="audio"
asset/v-720.ts
''';

/// And after its video rendition: fMP4 segments behind a `.ts` name, an init
/// segment every one of them needs, and a playlist that says it is finished.
const _media = '''
#EXTM3U
#EXT-X-TARGETDURATION:10
#EXT-X-VERSION:7
#EXT-X-MEDIA-SEQUENCE:0
#EXT-X-PLAYLIST-TYPE:VOD
#EXT-X-INDEPENDENT-SEGMENTS
#EXT-X-MAP:URI="asset/init.ts"
#EXTINF:10.000000,
asset/seg-0.ts
#EXTINF:10.000000,
asset/seg-1.ts
#EXTINF:10.000000,
asset/seg-2.ts
#EXTINF:4.500000,
asset/seg-3.ts
#EXT-X-ENDLIST
''';

void main() {
  group('parseHlsMaster', () {
    final master = parseHlsMaster(_master, base: _base);

    test('reads renditions and audio, resolved against the master', () {
      expect(master.isMaster, isTrue);
      expect(master.variants, hasLength(3));
      expect(master.variants.first.height, 2160);
      expect(master.variants.first.audioGroup, 'audio');
      expect(
        master.variants.last.url.toString(),
        'https://media.flystream.net/source-hls/abc/asset/v-720.ts',
      );
      expect(master.audio, hasLength(2));
      expect(master.audio.first.isDefault, isTrue);
    });

    test('keeps a comma that sits inside a quoted name', () {
      expect(master.audio.first.name, 'Track 1, Dub');
    });

    test('a media playlist is not a master', () {
      expect(parseHlsMaster(_media, base: _base).isMaster, isFalse);
      expect(parseHlsMaster('<html>403</html>', base: _base).isMaster, isFalse);
    });

    test('picks the tallest rendition inside the ceiling', () {
      expect(master.variantFor(720)?.height, 720);
      expect(master.variantFor(1440)?.height, 1080);
      expect(master.variantFor(null)?.height, 2160);
      // Every rendition is above the ceiling: take the smallest rather than
      // silently going over.
      expect(master.variantFor(360)?.height, 720);
    });

    test('finds the audio group a rendition points at', () {
      expect(master.audioFor('audio')?.name, 'Track 1, Dub');
      expect(master.audioFor('missing'), isNull);
      expect(master.audioFor(null), isNull);
    });
  });

  group('parseHlsMediaPlaylist', () {
    final playlist = parseHlsMediaPlaylist(_media, base: _base);

    test('reads segments, durations and the init segment', () {
      expect(playlist.isMediaPlaylist, isTrue);
      expect(playlist.isFragmentedMp4, isTrue);
      expect(playlist.segments, hasLength(4));
      expect(playlist.version, 7);
      expect(playlist.targetDurationSeconds, 10);
      expect(playlist.totalDuration, const Duration(milliseconds: 34500));
      expect(
        playlist.initSegment.toString(),
        'https://media.flystream.net/source-hls/abc/asset/init.ts',
      );
    });

    test('a rendition without an init segment is not fMP4', () {
      const audio = '''
#EXTM3U
#EXT-X-VERSION:6
#EXTINF:10.000000,
asset/a-0.ts
#EXT-X-ENDLIST
''';
      final parsed = parseHlsMediaPlaylist(audio, base: _base);
      expect(parsed.isMediaPlaylist, isTrue);
      expect(parsed.isFragmentedMp4, isFalse);
    });

    test('a master is not a media playlist, and neither is a 403 page', () {
      // No #EXTINF in front of the URIs: nothing to place on a timeline.
      expect(
        parseHlsMediaPlaylist(_master, base: _base).isMediaPlaylist,
        isFalse,
      );
      expect(parseHlsMediaPlaylist('', base: _base).isMediaPlaylist, isFalse);
    });

    test('names the segment covering the moment asked for', () {
      expect(playlist.segmentIndexAt(Duration.zero), 0);
      expect(playlist.segmentIndexAt(const Duration(seconds: 9)), 0);
      expect(playlist.segmentIndexAt(const Duration(seconds: 10)), 1);
      expect(playlist.segmentIndexAt(const Duration(seconds: 25)), 2);
      expect(playlist.segmentIndexAt(const Duration(hours: 2)), 3);
    });

    test('a cut lands on the segment boundary before the target', () {
      // At most one segment early, which is what a browser gives too.
      expect(playlist.startOf(2), const Duration(seconds: 20));
    });
  });

  group('hlsSliceMaster', () {
    test('names both cuts so they stay in one demuxer', () {
      final master = hlsSliceMaster(
        videoPlaylist: 'cut-video.m3u8',
        audioPlaylist: 'cut-audio.m3u8',
        height: 720,
      );

      expect(master, contains('URI="cut-audio.m3u8"'));
      expect(master, contains('AUDIO="audio"'));
      expect(master, contains('cut-video.m3u8'));
      // It has to read back as a master, or FFmpeg treats it as a segment
      // list and plays nothing.
      final parsed = parseHlsMaster(master, base: _base);
      expect(parsed.isMaster, isTrue);
      expect(parsed.variants.single.height, 720);
      expect(parsed.audio.single.groupId, 'audio');
    });

    test('leaves out audio a rendition carries in its own segments', () {
      final master = hlsSliceMaster(videoPlaylist: 'cut-video.m3u8');
      expect(master, isNot(contains('EXT-X-MEDIA')));
      expect(master, isNot(contains('AUDIO=')));
      expect(parseHlsMaster(master, base: _base).variants, hasLength(1));
    });
  });

  group('sliceFrom', () {
    final playlist = parseHlsMediaPlaylist(_media, base: _base);

    test('carries the init segment every fMP4 segment depends on', () {
      // Dropping this is how a cut plays nothing at all.
      expect(
        playlist.sliceFrom(2),
        contains(
          '#EXT-X-MAP:URI="https://media.flystream.net/source-hls/abc/asset/init.ts"',
        ),
      );
    });

    test('begins at the segment asked for and runs to the end', () {
      final slice = playlist.sliceFrom(2);
      expect(slice, contains('asset/seg-2.ts'));
      expect(slice, contains('asset/seg-3.ts'));
      expect(slice, isNot(contains('seg-0.ts')));
      expect(slice, isNot(contains('seg-1.ts')));
      expect(slice, contains('#EXT-X-ENDLIST'));
    });

    test('writes segment URIs absolute', () {
      // The cut is opened from a local file, where a relative URI would
      // resolve against that file's own directory.
      expect(
        playlist.sliceFrom(1),
        contains('https://media.flystream.net/source-hls/abc/asset/seg-1.ts'),
      );
    });

    test('a cut it can read back describes the remaining runtime', () {
      final reparsed = parseHlsMediaPlaylist(
        playlist.sliceFrom(2),
        base: _base,
      );
      expect(reparsed.segments, hasLength(2));
      expect(reparsed.totalDuration, const Duration(milliseconds: 14500));
      expect(reparsed.initSegment, playlist.initSegment);
    });

    test('a cut at zero is the playlist itself', () {
      final reparsed = parseHlsMediaPlaylist(
        playlist.sliceFrom(0),
        base: _base,
      );
      expect(reparsed.segments, hasLength(4));
      expect(reparsed.totalDuration, playlist.totalDuration);
    });
  });
}
