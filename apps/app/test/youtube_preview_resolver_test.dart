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

HlsMuxedStreamInfo _hlsMuxed(
  String tagUrl, {
  VideoResolution resolution = _resolution,
  int tag = 1,
}) => HlsMuxedStreamInfo(
  _id,
  tag,
  Uri.parse(tagUrl),
  StreamContainer.m3u8,
  _size,
  _bitrate,
  'mp4a.40.2',
  'avc1',
  '${resolution.height}p',
  VideoQuality.high720,
  resolution,
  _framerate,
  MediaType('application', 'vnd.apple.mpegurl'),
);

MuxedStreamInfo _muxed(
  String url, {
  VideoResolution resolution = _resolution,
  int tag = 2,
}) => MuxedStreamInfo(
  _id,
  tag,
  Uri.parse(url),
  _mp4,
  _size,
  _bitrate,
  'mp4a.40.2',
  'avc1',
  '${resolution.height}p',
  VideoQuality.medium360,
  resolution,
  _framerate,
  _codec,
);

VideoOnlyStreamInfo _videoOnly(
  String url, {
  VideoResolution resolution = _resolution,
  int tag = 3,
}) => VideoOnlyStreamInfo(
  _id,
  tag,
  Uri.parse(url),
  _mp4,
  _size,
  _bitrate,
  'avc1',
  '${resolution.height}p',
  VideoQuality.high1080,
  resolution,
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

  test(
    'among several HLS qualities, picks the highest at or under 480p — '
    'a Shorts card is a small tile, not a full-screen player',
    () {
      final manifest = StreamManifest([
        _hlsMuxed('https://example.com/1080p.m3u8', tag: 1, resolution: const VideoResolution(1920, 1080)),
        _hlsMuxed('https://example.com/480p.m3u8', tag: 2, resolution: const VideoResolution(854, 480)),
        _hlsMuxed('https://example.com/360p.m3u8', tag: 3, resolution: const VideoResolution(640, 360)),
      ]);

      final stream = selectPreviewStream(manifest, videoId: _videoId);

      expect(stream.url, 'https://example.com/480p.m3u8');
    },
  );

  test(
    'falls back to the lowest available quality when nothing is at or '
    'under 480p',
    () {
      final manifest = StreamManifest([
        _hlsMuxed('https://example.com/1080p.m3u8', tag: 1, resolution: const VideoResolution(1920, 1080)),
        _hlsMuxed('https://example.com/720p.m3u8', tag: 2, resolution: const VideoResolution(1280, 720)),
      ]);

      final stream = selectPreviewStream(manifest, videoId: _videoId);

      expect(stream.url, 'https://example.com/720p.m3u8');
    },
  );

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
