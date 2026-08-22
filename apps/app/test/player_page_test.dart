import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_app/player/player_page.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';

import 'support/harness.dart';

void main() {
  test('source switch keeps VOD position and does not seek live streams', () {
    expect(
      sourceSwitchSeekPosition(
        isLive: false,
        previousPosition: const Duration(minutes: 25),
        duration: const Duration(hours: 1),
      ),
      const Duration(minutes: 25),
    );
    expect(
      sourceSwitchSeekPosition(
        isLive: true,
        previousPosition: const Duration(minutes: 25),
        duration: const Duration(hours: 1),
      ),
      isNull,
    );
    expect(
      sourceSwitchSeekPosition(
        isLive: false,
        previousPosition: const Duration(hours: 2),
        duration: const Duration(hours: 1),
      ),
      const Duration(hours: 1),
    );
  });

  testWidgets('switching source recreates playback with the selected stream', (
    tester,
  ) async {
    final player = RecordingPlayer();
    final first = _resolvedSource('first', 'Source A');
    final second = _resolvedSource('second', 'Source B');

    await tester.pumpWidget(
      wrapApp(
        child: PlayerPage(
          item: const VideoItemV2(
            ref: MediaRef(
              extensionId: 'test',
              providerId: 'test.provider',
              id: 'movie-1',
            ),
            title: 'Movie',
          ),
          resolvedSources: [first, second],
        ),
        registry: ExtensionRegistry([]),
        player: player,
      ),
    );
    await tester.pump();
    final initialBuilds = player.buildCount;

    await tester.tap(find.text('Source A'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Source B').last);
    await tester.pumpAndSettle();

    expect(player.played, second.stream);
    expect(player.buildCount, greaterThan(initialBuilds));
    expect(find.text('Source B'), findsOneWidget);
  });
}

ResolvedSource _resolvedSource(String id, String label) => ResolvedSource(
  source: StreamSource(id: id, label: label),
  stream: PlayableStream(
    url: 'https://stream.example/$id.m3u8',
    format: StreamFormat.hls,
  ),
);
