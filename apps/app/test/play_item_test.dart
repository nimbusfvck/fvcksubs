import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_app/player/models/playback_media.dart';
import 'package:fvcksubs_app/player/models/resolved_source.dart';
import 'package:fvcksubs_app/player/state/source_cache.dart';
import 'package:fvcksubs_app/player/state/subtitle_preference_controller.dart';
import 'package:fvcksubs_app/player/workflow/play_item.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';

import 'support/harness.dart';

void main() {
  const ref = MediaRef(
    extensionId: 'test',
    providerId: 'test.provider',
    id: 'movie-1',
  );
  const movie = PlaybackMedia(VideoItemV2(ref: ref, title: 'Movie'));
  const channel = PlaybackMedia(ChannelItemV2(ref: ref, title: 'Channel'));

  SubtitlePreferenceController controllerFor(String? language) =>
      SubtitlePreferenceController(
        store: FakeSubtitlePreferenceStore(),
        initial: language,
      );

  test('a VOD item with a language preference is looked up', () {
    expect(needsExternalSubtitleLookup(controllerFor('id'), movie), isTrue);
  });

  test('no preference and live streams are not looked up', () {
    expect(needsExternalSubtitleLookup(controllerFor(null), movie), isFalse);
    expect(needsExternalSubtitleLookup(controllerFor('id'), channel), isFalse);
  });

  test('a lookup that already found the language is not repeated', () {
    final preference = controllerFor('id');
    preference.rememberExternalSubtitles(ref, const [
      SubtitleTrack(language: 'id', url: 'https://shegu.example/id.srt'),
    ]);

    expect(needsExternalSubtitleLookup(preference, movie), isFalse);
  });

  test('a lookup that found only another language is retried', () {
    final preference = controllerFor('id');
    preference.rememberExternalSubtitles(ref, const [
      SubtitleTrack(language: 'en', url: 'https://shegu.example/en.srt'),
    ]);

    expect(needsExternalSubtitleLookup(preference, movie), isTrue);
  });

  testWidgets('a second Play tap does not stack another player route', (
    tester,
  ) async {
    const item = PlaybackMedia(
      VideoItemV2(
        ref: MediaRef(extensionId: 'fake', providerId: 'fake.p', id: 'movie-1'),
        title: 'Movie',
      ),
    );
    final player = RecordingPlayer();
    final extension = FakeExtension(
      sourceList: const [StreamSource(id: 'source', label: 'Source')],
      sourcesDelay: const Duration(milliseconds: 20),
      resolved: const PlayableStream(
        url: 'https://stream.example/source.m3u8',
        format: StreamFormat.hls,
      ),
    );

    await tester.pumpWidget(
      wrapApp(
        child: Builder(
          builder: (context) => FilledButton(
            onPressed: () {
              unawaited(playItemV2(context, item.item));
              unawaited(playItemV2(context, item.item));
            },
            child: const Text('Play'),
          ),
        ),
        registry: ExtensionRegistry([extension]),
        player: player,
      ),
    );

    await tester.tap(
      find.widgetWithText(FilledButton, 'Play'),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    expect(extension.sourcesCalls, 2);
    expect(player.played, isNotNull);
  });

  testWidgets('live playback keeps full discovery but uses fastest source', (
    tester,
  ) async {
    final extension = SubtitleFakeExtension(
      subtitlesBySourceId: const {'preferred': [], 'fast': []},
      resolveDelayBySourceId: const {
        'preferred': Duration(milliseconds: 100),
        'fast': Duration.zero,
      },
    );
    final player = RecordingPlayer();
    final event = fakeItem(
      id: 'live-1',
      extensionId: 'subs',
      title: 'Preferred vs Fast',
      participants: const [
        Participant(name: 'Preferred'),
        Participant(name: 'Fast'),
      ],
    );

    await tester.pumpWidget(
      wrapApp(
        child: Builder(
          builder: (context) => FilledButton(
            onPressed: () => unawaited(playItemV2(context, event)),
            child: const Text('Play'),
          ),
        ),
        registry: ExtensionRegistry([extension]),
        player: player,
      ),
    );

    await tester.tap(
      find.widgetWithText(FilledButton, 'Play'),
      warnIfMissed: false,
    );
    await tester.pump(const Duration(milliseconds: 20));

    expect(extension.lastFast, isFalse);

    await tester.pumpAndSettle();
    expect(player.played?.url, 'https://edge/fast.m3u8');
  });

  testWidgets(
    'stale cached playback publishes refreshed sources to the picker',
    (tester) async {
      const staleItem = PlaybackMedia(
        VideoItemV2(
          ref: MediaRef(
            extensionId: 'fake',
            providerId: 'fake.p',
            id: 'movie-stale-cache',
          ),
          title: 'Movie',
        ),
      );
      var now = DateTime(2026);
      final sourceCache = SourceCache(now: () => now);
      const cachedSource = StreamSource(id: 'hydrax', label: 'HYDRAX');
      const refreshedSource = StreamSource(id: 'cast', label: 'CAST');
      const stream = PlayableStream(
        url: 'https://stream.example/movie.m3u8',
        format: StreamFormat.hls,
      );
      sourceCache.store(staleItem.ref, const [
        ResolvedSource(source: cachedSource, stream: stream),
      ]);
      now = now.add(const Duration(minutes: 4));

      final extension = FakeExtension(
        sourceList: const [cachedSource, refreshedSource],
        resolved: stream,
      );
      final player = RecordingPlayer();

      await tester.pumpWidget(
        wrapApp(
          child: Builder(
            builder: (context) => FilledButton(
              onPressed: () => unawaited(playItemV2(context, staleItem.item)),
              child: const Text('Play'),
            ),
          ),
          registry: ExtensionRegistry([extension]),
          player: player,
          sourceCache: sourceCache,
        ),
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Play'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('HYDRAX'));
      await tester.pump();

      expect(find.text('CAST'), findsOneWidget);
    },
  );

  testWidgets('background sources reach the picker as they resolve', (
    tester,
  ) async {
    const item = VideoItemV2(
      ref: MediaRef(
        extensionId: 'subs',
        providerId: 'subs.p',
        id: 'movie-incremental-refresh',
      ),
      title: 'Movie',
    );
    var now = DateTime(2026);
    final sourceCache = SourceCache(now: () => now);
    final stream = const PlayableStream(
      url: 'https://stream.example/movie.m3u8',
      format: StreamFormat.hls,
    );
    sourceCache.store(item.ref, [
      ResolvedSource(
        source: const StreamSource(id: 'hydrax', label: 'Source hydrax'),
        stream: stream,
      ),
    ]);
    now = now.add(const Duration(minutes: 4));

    final extension = SubtitleFakeExtension(
      subtitlesBySourceId: const {'hydrax': [], 'cast': []},
      resolveDelayBySourceId: const {
        'cast': Duration(milliseconds: 400),
      },
    );

    await tester.pumpWidget(
      wrapApp(
        child: Builder(
          builder: (context) => FilledButton(
            onPressed: () => unawaited(playItemV2(context, item)),
            child: const Text('Play'),
          ),
        ),
        registry: ExtensionRegistry([extension]),
        player: RecordingPlayer(),
        sourceCache: sourceCache,
      ),
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Play'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byTooltip('Source hydrax').last);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Source cast'), findsNothing);

    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Source cast'), findsOneWidget);
  });
}
