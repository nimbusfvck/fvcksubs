import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:test/test.dart';

import '../support/round_trip.dart';

void main() {
  test('StreamSource round-trips', () {
    const source = StreamSource(
      id: 'cricfy:link-3',
      label: 'HD 1080p',
      provider: 'Cricfy',
    );
    expectRoundTrips(
      source,
      toJson: (s) => s.toJson(),
      fromJson: StreamSource.fromJson,
    );
  });

  test('PlayableStream with ClearKey DRM round-trips', () {
    const stream = PlayableStream(
      url: 'https://cdn.example.com/live.mpd',
      headers: {
        'User-Agent': 'Mozilla/5.0',
        'Referer': 'https://cricyplayers.com/',
      },
      format: StreamFormat.dash,
      drm: DrmConfig(
        scheme: DrmScheme.clearKey,
        clearKeyJson:
            '{"keys":[{"kty":"oct","k":"abc","kid":"def"}],"type":"temporary"}',
      ),
      label: 'Sports HD 1',
    );
    expectRoundTrips(
      stream,
      toJson: (s) => s.toJson(),
      fromJson: PlayableStream.fromJson,
    );
  });

  test('clear HLS stream (no DRM, no headers) round-trips', () {
    const stream = PlayableStream(
      url: 'https://edge.example.com/live/abc.m3u8',
      format: StreamFormat.hls,
    );
    expect(stream.isProtected, isFalse);
    expectRoundTrips(
      stream,
      toJson: (s) => s.toJson(),
      fromJson: PlayableStream.fromJson,
    );
  });

  test('unknown DRM scheme decodes to unsupported', () {
    final drm = DrmConfig.fromJson({'scheme': 'playReady'});
    expect(drm!.scheme, DrmScheme.unsupported);
  });

  test('SubtitleTrack round-trips', () {
    const track = SubtitleTrack(
      language: 'en',
      url: 'https://subtitles.shegu.st/sub/abc',
      label: 'English (13958798)',
    );
    expectRoundTrips(
      track,
      toJson: (t) => t.toJson(),
      fromJson: SubtitleTrack.fromJson,
    );
  });

  test('PlayableStream with subtitles round-trips', () {
    const stream = PlayableStream(
      url: 'https://cdn.example.com/movie.m3u8',
      format: StreamFormat.hls,
      subtitles: [
        SubtitleTrack(language: 'en', url: 'https://cdn.example.com/en.srt'),
        SubtitleTrack(
          language: 'id',
          url: 'https://cdn.example.com/id.srt',
          label: 'Indonesian',
        ),
      ],
    );
    expectRoundTrips(
      stream,
      toJson: (s) => s.toJson(),
      fromJson: PlayableStream.fromJson,
    );
  });

  test('a stream with no subtitles omits the field entirely', () {
    const stream = PlayableStream(url: 'https://cdn.example.com/movie.m3u8');
    expect(stream.toJson().containsKey('subtitles'), isFalse);
    expect(stream.subtitles, isEmpty);
  });
}
