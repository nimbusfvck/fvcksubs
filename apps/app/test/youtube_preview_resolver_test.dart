import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_app/player/youtube/youtube_preview_resolver.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:http_parser/http_parser.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

const _videoId = 'dQw4w9WgXcQ';

VideoId get _id => VideoId(_videoId);

const _mp4 = StreamContainer.mp4;
const _size = FileSize(1000);
const _bitrate = Bitrate(1000);
const _resolution = VideoResolution(1280, 720);
const _framerate = Framerate(30);
final _codec = MediaType('video', 'mp4');

HlsMuxedStreamInfo _hlsMuxed(String tagUrl) => HlsMuxedStreamInfo(
  _id,
  1,
  Uri.parse(tagUrl),
  StreamContainer.m3u8,
  _size,
  _bitrate,
  'mp4a.40.2',
  'avc1',
  '720p',
  VideoQuality.high720,
  _resolution,
  _framerate,
  MediaType('application', 'vnd.apple.mpegurl'),
);

MuxedStreamInfo _muxed(String url) => MuxedStreamInfo(
  _id,
  2,
  Uri.parse(url),
  _mp4,
  _size,
  _bitrate,
  'mp4a.40.2',
  'avc1',
  '360p',
  VideoQuality.medium360,
  _resolution,
  _framerate,
  _codec,
);

VideoOnlyStreamInfo _videoOnly(String url) => VideoOnlyStreamInfo(
  _id,
  3,
  Uri.parse(url),
  _mp4,
  _size,
  _bitrate,
  'avc1',
  '1080p',
  VideoQuality.high1080,
  _resolution,
  _framerate,
  const [],
  _codec,
);

AudioOnlyStreamInfo _audioOnly(String url) => AudioOnlyStreamInfo(
  _id,
  4,
  Uri.parse(url),
  _mp4,
  _size,
  _bitrate,
  'mp4a.40.2',
  '128kbps',
  const [],
  MediaType('audio', 'mp4'),
  null,
);

void main() {
  test('an HLS muxed stream wins over everything else', () {
    final manifest = StreamManifest([
      _hlsMuxed('https://example.com/hls.m3u8'),
      _muxed('https://example.com/muxed.mp4'),
      _videoOnly('https://example.com/video.mp4'),
      _audioOnly('https://example.com/audio.mp4'),
    ]);

    final stream = selectPreviewStream(manifest, videoId: _videoId);

    expect(stream.url, 'https://example.com/hls.m3u8');
    expect(stream.format, StreamFormat.hls);
    expect(stream.audioUrl, isNull);
  });

  test('a muxed MP4 wins when no HLS muxed stream exists', () {
    final manifest = StreamManifest([
      _muxed('https://example.com/muxed.mp4'),
      _videoOnly('https://example.com/video.mp4'),
      _audioOnly('https://example.com/audio.mp4'),
    ]);

    final stream = selectPreviewStream(manifest, videoId: _videoId);

    expect(stream.url, 'https://example.com/muxed.mp4');
    expect(stream.format, StreamFormat.other);
    expect(stream.audioUrl, isNull);
  });

  test(
    'separate video+audio is the last resort, carrying audioUrl',
    () {
      final manifest = StreamManifest([
        _videoOnly('https://example.com/video.mp4'),
        _audioOnly('https://example.com/audio.mp4'),
      ]);

      final stream = selectPreviewStream(manifest, videoId: _videoId);

      expect(stream.url, 'https://example.com/video.mp4');
      expect(stream.audioUrl, 'https://example.com/audio.mp4');
      expect(stream.format, StreamFormat.other);
    },
  );

  test('no usable stream at all throws', () {
    final manifest = StreamManifest(const []);

    expect(
      () => selectPreviewStream(manifest, videoId: _videoId),
      throwsStateError,
    );
  });

  test('video-only without a matching audio-only stream throws', () {
    final manifest = StreamManifest([_videoOnly('https://example.com/video.mp4')]);

    expect(
      () => selectPreviewStream(manifest, videoId: _videoId),
      throwsStateError,
    );
  });
}
