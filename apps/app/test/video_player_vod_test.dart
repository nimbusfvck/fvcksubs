import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_app/player/widgets/video_player_vod.dart';

void main() {
  test('subtitle overlay keeps the same viewport rect across resolutions', () {
    const viewport = Size(390, 219.375);
    final hd = subtitleOverlayRect(
      videoSize: const Size(1280, 720),
      viewportSize: viewport,
      fit: BoxFit.contain,
    );
    final fourK = subtitleOverlayRect(
      videoSize: const Size(3840, 2160),
      viewportSize: viewport,
      fit: BoxFit.contain,
    );

    expect(hd, fourK);
    expect(hd.size, viewport);
  });

  test('subtitle overlay stays inside letterboxed video for contain', () {
    final rect = subtitleOverlayRect(
      videoSize: const Size(1920, 800),
      viewportSize: const Size(390, 219.375),
      fit: BoxFit.contain,
    );

    expect(rect.left, closeTo(0, 0.001));
    expect(rect.width, closeTo(390, 0.001));
    expect(rect.top, greaterThan(0));
    expect(rect.bottom, lessThan(219.375));
  });

  test('cover uses the complete visible viewport for subtitles', () {
    final rect = subtitleOverlayRect(
      videoSize: const Size(1920, 800),
      viewportSize: const Size(390, 219.375),
      fit: BoxFit.cover,
    );

    expect(rect, const Rect.fromLTWH(0, 0, 390, 219.375));
  });
}
