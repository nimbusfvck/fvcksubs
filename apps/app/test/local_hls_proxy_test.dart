import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_app/player/data/local_hls_proxy.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';

void main() {
  test(
    'keeps the local segment URL stable when upstream signatures rotate',
    () async {
      var playlistRefreshes = 0;
      String? receivedReferer;
      String? requestedSignature;
      final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      unawaited(
        upstream.forEach((request) async {
          if (request.uri.path == '/playlist.m3u8') {
            playlistRefreshes++;
            receivedReferer = request.headers.value('referer');
            final signature = playlistRefreshes == 1 ? 'first' : 'second';
            request.response.headers.contentType = ContentType(
              'application',
              'vnd.apple.mpegurl',
            );
            request.response.write('''#EXTM3U
#EXT-X-TARGETDURATION:6
#EXT-X-MEDIA-SEQUENCE:10
#EXTINF:6,
http://127.0.0.1:${upstream.port}/segment/10?sig=$signature
''');
            await request.response.close();
            return;
          }
          if (request.uri.path == '/segment/10') {
            requestedSignature = request.uri.queryParameters['sig'];
            request.response.add(utf8.encode('segment-bytes'));
            await request.response.close();
            return;
          }
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
        }),
      );

      final proxy = LocalHlsProxy();
      final client = HttpClient();
      try {
        final stream = PlayableStream(
          url: 'http://127.0.0.1:${upstream.port}/playlist.m3u8',
          format: StreamFormat.hls,
          headers: const {'Referer': 'https://gooz.aapmains.net'},
        );
        final proxied = await proxy.wrap(stream);

        final firstPlaylist = await _getText(client, Uri.parse(proxied.url));
        final secondPlaylist = await _getText(client, Uri.parse(proxied.url));
        final firstSegment = _playlistUri(firstPlaylist);
        final secondSegment = _playlistUri(secondPlaylist);

        expect(playlistRefreshes, 2);
        expect(receivedReferer, 'https://gooz.aapmains.net');
        expect(firstSegment, isNotEmpty);
        expect(secondSegment, firstSegment);

        final segmentResponse = await client.getUrl(Uri.parse(firstSegment));
        final segment = await segmentResponse.close();
        expect(await utf8.decoder.bind(segment).join(), 'segment-bytes');
        expect(requestedSignature, 'second');
      } finally {
        client.close(force: true);
        await proxy.dispose();
        await upstream.close(force: true);
      }
    },
  );
}

Future<String> _getText(HttpClient client, Uri uri) async {
  final request = await client.getUrl(uri);
  final response = await request.close();
  expect(response.statusCode, HttpStatus.ok);
  return utf8.decoder.bind(response).join();
}

String _playlistUri(String playlist) => playlist
    .split('\n')
    .firstWhere((line) => line.startsWith('http://127.0.0.1:'));
