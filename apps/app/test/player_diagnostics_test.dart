import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_app/player/player_diagnostics.dart';

void main() {
  test('safe playback url removes query tokens and fragments', () {
    expect(
      safePlaybackUrlForLog(
        'https://edge.example/live.m3u8?token=secret#fragment',
      ),
      'https://edge.example/live.m3u8',
    );
  });

  test('diagnostic text redacts tokens embedded in native errors', () {
    expect(
      redactPlaybackLogText(
        'HTTP 403: https://edge.example/segment.ts?token=secret, retry failed',
      ),
      'HTTP 403: https://edge.example/segment.ts, retry failed',
    );
  });

  test('invalid playback url is never printed verbatim', () {
    expect(safePlaybackUrlForLog('not a URL?token=secret'), '<invalid-url>');
  });
}
