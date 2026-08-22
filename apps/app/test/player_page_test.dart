import 'dart:async';

import 'package:better_player_plus/better_player_plus.dart';
import 'package:better_player_plus/src/video_player/video_player_platform_interface.dart'
    show DurationRange;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_app/player/player_page.dart';
import 'package:fvcksubs_app/player/playback_media.dart';
import 'package:fvcksubs_app/player/source_cache.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';

import 'support/harness.dart';

/// The drag-down-to-close gesture, and specifically what happens when the drag
/// doesn't end cleanly.
///
/// [PlayerPage] wraps its content in a widget that translates the player
/// downward as the viewer drags, snapping back if they let go before the
/// dismiss threshold. The regression this guards: the snap-back was wired to
/// `onVerticalDragEnd` only — a *cancelled* drag (the gesture arena handing
/// the pointer to some other recognizer mid-gesture, which happens whenever
/// a competing tap/drag recognizer elsewhere in the tree wins) fires
/// `onVerticalDragCancel` instead, and nothing was listening for that. The
/// player was left translated downward with no code path back to zero —
/// visually stuck.
void main() {
  test('playback media identifies legacy and protocol-v2 episodes', () {
    const legacyEpisode = MediaItem(
      ref: MediaRef(
        extensionId: 'extension',
        providerId: 'provider',
        id: 'episode',
      ),
      kind: MediaKind.episode,
      title: 'Episode',
    );
    const v2Episode = EpisodeItemV2(
      ref: MediaRef(
        extensionId: 'extension',
        providerId: 'provider',
        id: 'episode-v2',
      ),
      title: 'Episode v2',
      episode: EpisodeIdentity(
        parentRef: MediaRef(
          extensionId: 'extension',
          providerId: 'provider',
          id: 'series',
        ),
        groupId: 'season-1',
        position: 1,
      ),
    );

    expect(const PlaybackMedia.legacy(legacyEpisode).isEpisode, isTrue);
    expect(const PlaybackMedia.v2(v2Episode).isEpisode, isTrue);
  });

  // Away from every button the controls overlay draws — back/favorite up
  // top, play/rewind/forward dead centre, source/CC pill at the bottom — so
  // the touch is unambiguously a drag on empty background, not a tap on some
  // control.
  const dragStart = Offset(700, 150);

  double fakePlayerY(WidgetTester tester) =>
      tester.getCenter(find.byKey(const Key('fake-player'))).dy;

  test('live seek edge survives a missing duration', () {
    final value = VideoPlayerValue(
      duration: null,
      position: const Duration(seconds: 12),
      buffered: const [
        DurationRange(Duration(seconds: 8), Duration(seconds: 30)),
      ],
    );

    expect(liveSeekEdge(value), const Duration(seconds: 30));
  });

  test('seekbar buffer edge uses the furthest buffered range', () {
    final value = VideoPlayerValue(
      duration: const Duration(minutes: 10),
      position: const Duration(seconds: 20),
      buffered: const [DurationRange(Duration.zero, Duration(seconds: 45))],
    );

    expect(bufferedSeekEdge(value), const Duration(seconds: 45));
  });

  test(
    'background source refresh keeps the playing source and appends new ones',
    () {
      const playing = ResolvedSource(
        source: StreamSource(id: 'playing', label: 'Primary'),
        stream: PlayableStream(
          url: 'https://edge/playing.m3u8',
          format: StreamFormat.hls,
        ),
      );
      const added = ResolvedSource(
        source: StreamSource(id: 'added', label: 'Backup'),
        stream: PlayableStream(
          url: 'https://edge/added.m3u8',
          format: StreamFormat.hls,
        ),
      );

      final merged = mergeResolvedSources([playing], [playing, added]);

      expect(merged.map((source) => source.source.id), ['playing', 'added']);
    },
  );

  test('a live scrub close to the end stays safely behind the edge', () {
    const edge = Duration(seconds: 30);

    expect(
      liveSeekTarget(
        const Duration(seconds: 29),
        edge,
        currentPosition: const Duration(seconds: 20),
      ),
      const Duration(seconds: 28),
    );
    expect(
      liveSeekTarget(
        const Duration(seconds: 27),
        edge,
        currentPosition: const Duration(seconds: 20),
      ),
      const Duration(seconds: 27),
    );
  });

  test('a rightmost scrub is a no-op when playback is already live', () {
    expect(
      liveSeekTarget(
        const Duration(seconds: 30),
        const Duration(seconds: 30),
        currentPosition: const Duration(seconds: 29),
      ),
      isNull,
    );
  });

  test('live edge state becomes stale after the playback tolerance', () {
    const edge = Duration(seconds: 30);

    expect(isAtLiveEdge(const Duration(seconds: 26), edge), isTrue);
    expect(isAtLiveEdge(const Duration(seconds: 24), edge), isFalse);
  });

  test('a paused live timeline keeps advancing while position stays fixed', () {
    const edgeAtPause = Duration(seconds: 30);
    const position = Duration(seconds: 30);

    final edgeAfterPause = liveEdgeAfterPause(
      edgeAtPause,
      const Duration(seconds: 6),
    );

    expect(edgeAfterPause, const Duration(seconds: 36));
    expect(isAtLiveEdge(position, edgeAfterPause), isFalse);
  });

  Future<void> pumpPlayer(
    WidgetTester tester, {
    List<SubtitleTrack> subtitles = const [],
    bool isLive = false,
  }) async {
    final item = fakeItem(
      title: 'Some Movie',
      poster: isLive ? null : const ImageRef('https://img/movie.jpg'),
    );
    final resolved = [
      ResolvedSource(
        source: const StreamSource(id: 's', label: 'HD'),
        stream: PlayableStream(
          url: 'https://edge/movie.m3u8',
          format: StreamFormat.hls,
          subtitles: subtitles,
        ),
      ),
    ];

    await tester.pumpWidget(
      wrapApp(
        child: PlayerPage(item: item, resolvedSources: resolved),
        registry: ExtensionRegistry(const []),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// A single big `gesture.moveBy` doesn't reliably arm a vertical-drag
  /// recognizer in widget tests — the framework's own
  /// `WidgetController.dragFrom` breaks a move into a slop-crossing step
  /// ([kDragSlopDefault]) followed by the remainder, and a raw [TestGesture]
  /// needs that same two-step shape to register as a drag instead of being
  /// dropped. The slop-crossing step itself isn't reported to
  /// `onVerticalDragUpdate` — only [dy] minus the slop actually lands.
  Future<TestGesture> startVerticalDrag(
    WidgetTester tester,
    Offset start,
    double dy,
  ) async {
    final gesture = await tester.startGesture(start);
    final slop = kDragSlopDefault * dy.sign;
    await gesture.moveBy(Offset(0, slop));
    await gesture.moveBy(Offset(0, dy - slop));
    return gesture;
  }

  testWidgets('a mid-drag translates the player downward', (tester) async {
    await pumpPlayer(tester);
    final startY = fakePlayerY(tester);

    final gesture = await startVerticalDrag(tester, dragStart, 100);
    await tester.pump();

    expect(fakePlayerY(tester), startY + (100 - kDragSlopDefault));
    await gesture.up();
  });

  testWidgets('releasing before the threshold snaps back to the start', (
    tester,
  ) async {
    await pumpPlayer(tester);
    final startY = fakePlayerY(tester);

    final gesture = await startVerticalDrag(tester, dragStart, 100);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(fakePlayerY(tester), startY);
  });

  testWidgets('a drag that is cancelled rather than ended also snaps back', (
    tester,
  ) async {
    // The bug this guards: only onVerticalDragEnd used to reset the
    // position, so a cancelled gesture — never "ended" at all — left the
    // player stuck exactly where the drag left it.
    await pumpPlayer(tester);
    final startY = fakePlayerY(tester);

    final gesture = await startVerticalDrag(tester, dragStart, 100);
    await tester.pump();
    expect(fakePlayerY(tester), isNot(startY));

    await gesture.cancel();
    await tester.pumpAndSettle();

    expect(fakePlayerY(tester), startY);
  });

  testWidgets('protocol v2 item uses native title and library state', (
    tester,
  ) async {
    const item = VideoItemV2(
      ref: MediaRef(
        extensionId: 'extension',
        providerId: 'provider',
        id: 'video',
      ),
      title: 'Protocol v2 video',
    );
    final resolved = [
      const ResolvedSource(
        source: StreamSource(id: 'source', label: 'Primary'),
        stream: PlayableStream(
          url: 'https://edge/video.m3u8',
          format: StreamFormat.hls,
        ),
      ),
    ];

    await tester.pumpWidget(
      wrapApp(
        child: PlayerPage.v2(item: item, resolvedSources: resolved),
        registry: ExtensionRegistry(const []),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Protocol v2 video'), findsOneWidget);
    expect(find.byIcon(Icons.picture_in_picture_alt_rounded), findsNothing);
    await tester.tap(find.byTooltip('Add to favorites'));
    await tester.pump();
    expect(find.byTooltip('Remove from favorites'), findsOneWidget);
  });

  group('subtitle picker', () {
    Future<void> openPicker(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.closed_caption_off_rounded));
      await tester.pumpAndSettle();
    }

    testWidgets('live controls do not offer subtitles', (tester) async {
      await pumpPlayer(
        tester,
        isLive: true,
        subtitles: const [
          SubtitleTrack(language: 'en', url: 'https://subs/live.vtt'),
        ],
      );

      expect(find.byIcon(Icons.closed_caption_off_rounded), findsNothing);
      expect(find.byIcon(Icons.closed_caption_rounded), findsNothing);
    });

    testWidgets('live controls identify the broadcast', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpPlayer(tester, isLive: true);

      expect(find.byKey(const Key('player-live-indicator')), findsOneWidget);
      expect(find.text('LIVE'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Live broadcast')), findsOneWidget);
      expect(find.byType(Slider), findsOneWidget);
      expect(
        tester.getTopLeft(find.byKey(const Key('player-live-indicator'))).dx,
        lessThan(tester.getTopLeft(find.byType(Slider)).dx),
      );
      expect(find.byIcon(Icons.replay_10_rounded), findsNothing);
      expect(find.byIcon(Icons.forward_10_rounded), findsNothing);
      expect(find.byIcon(Icons.picture_in_picture_alt_rounded), findsNothing);
      semantics.dispose();
    });

    testWidgets('same-language tracks collapse into one row with a count', (
      tester,
    ) async {
      await pumpPlayer(
        tester,
        subtitles: const [
          SubtitleTrack(
            language: 'en',
            url: 'https://subs/en-1.srt',
            label: 'English',
          ),
          SubtitleTrack(
            language: 'en',
            url: 'https://subs/en-2.srt',
            label: 'English SDH',
          ),
          SubtitleTrack(language: 'id', url: 'https://subs/id.srt'),
        ],
      );

      await openPicker(tester);

      expect(find.text('🇬🇧 English (2)'), findsOneWidget);
      expect(find.text('🇮🇩 Indonesia'), findsOneWidget);
      // Not drilled in yet — the real per-track names aren't shown until
      // the group itself is tapped.
      expect(find.text('English SDH'), findsNothing);
    });

    testWidgets('a single track in a language gets no count and no submenu', (
      tester,
    ) async {
      await pumpPlayer(
        tester,
        subtitles: const [
          SubtitleTrack(
            language: 'en',
            url: 'https://subs/en.srt',
            label: 'English',
          ),
        ],
      );

      await openPicker(tester);

      expect(find.text('🇬🇧 English'), findsOneWidget);
      expect(find.text('🇬🇧 English (1)'), findsNothing);
    });

    testWidgets('tapping a grouped language drills into its real track names', (
      tester,
    ) async {
      await pumpPlayer(
        tester,
        subtitles: const [
          SubtitleTrack(
            language: 'en',
            url: 'https://subs/en-1.srt',
            label: 'English',
          ),
          SubtitleTrack(
            language: 'en',
            url: 'https://subs/en-2.srt',
            label: 'English SDH',
          ),
        ],
      );

      await openPicker(tester);
      await tester.tap(find.text('🇬🇧 English (2)'));
      await tester.pumpAndSettle();

      expect(find.text('English'), findsOneWidget);
      expect(find.text('English SDH'), findsOneWidget);
      // The group list is replaced, not layered underneath.
      expect(find.text('🇬🇧 English (2)'), findsNothing);
    });

    testWidgets(
      'a track with no label of its own falls back to a plain ordinal',
      (tester) async {
        await pumpPlayer(
          tester,
          subtitles: const [
            SubtitleTrack(language: 'en', url: 'https://subs/en-1.srt'),
            SubtitleTrack(language: 'en', url: 'https://subs/en-2.srt'),
          ],
        );

        await openPicker(tester);
        await tester.tap(find.text('🇬🇧 English (2)'));
        await tester.pumpAndSettle();

        expect(find.text('Option 1'), findsOneWidget);
        expect(find.text('Option 2'), findsOneWidget);
      },
    );

    testWidgets('back from a drilled-in group returns to the language list', (
      tester,
    ) async {
      await pumpPlayer(
        tester,
        subtitles: const [
          SubtitleTrack(
            language: 'en',
            url: 'https://subs/en-1.srt',
            label: 'English',
          ),
          SubtitleTrack(
            language: 'en',
            url: 'https://subs/en-2.srt',
            label: 'English SDH',
          ),
        ],
      );

      await openPicker(tester);
      await tester.tap(find.text('🇬🇧 English (2)'));
      await tester.pumpAndSettle();

      // The player's own top-bar back button carries the same icon —
      // scoped to the sheet so this hits the sheet's, not that one.
      await tester.tap(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.byIcon(Icons.arrow_back_ios_new_rounded),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('🇬🇧 English (2)'), findsOneWidget);
      expect(find.text('English SDH'), findsNothing);
    });
  });

  group('switching sources', () {
    testWidgets(
      'a background-resolved fallback appears without waiting for all sources',
      (tester) async {
        final item = fakeItem(title: 'Some Movie');
        final pending = StreamController<ResolvedSource>();
        const current = ResolvedSource(
          source: StreamSource(id: 'primary', label: 'Primary'),
          stream: PlayableStream(
            url: 'https://edge/primary.m3u8',
            format: StreamFormat.hls,
          ),
        );
        const fallback = ResolvedSource(
          source: StreamSource(id: 'fallback', label: 'Fallback'),
          stream: PlayableStream(
            url: 'https://edge/fallback.m3u8',
            format: StreamFormat.hls,
          ),
        );

        await tester.pumpWidget(
          wrapApp(
            child: PlayerPage(
              item: item,
              resolvedSources: const [current],
              pendingSources: pending.stream,
            ),
            registry: ExtensionRegistry(const []),
          ),
        );
        await tester.pumpAndSettle();

        pending.add(fallback);
        await tester.pump();

        await tester.tap(find.byIcon(Icons.playlist_play_rounded));
        await tester.pumpAndSettle();

        expect(find.text('Fallback'), findsOneWidget);
        await pending.close();
      },
    );

    testWidgets(
      'source button shows the playing source before refresh completes',
      (tester) async {
        final item = fakeItem(title: 'Some Movie');
        const resolved = [
          ResolvedSource(
            source: StreamSource(id: 'playing', label: 'Primary'),
            stream: PlayableStream(
              url: 'https://edge/playing.m3u8',
              format: StreamFormat.hls,
            ),
          ),
        ];

        await tester.pumpWidget(
          wrapApp(
            child: PlayerPage(item: item, resolvedSources: resolved),
            registry: ExtensionRegistry(const []),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.playlist_play_rounded));
        await tester.pumpAndSettle();

        expect(find.text('Primary'), findsNWidgets(2));
        expect(find.byIcon(Icons.check), findsOneWidget);
      },
    );

    testWidgets('a manual switch is remembered for next time, in both caches', (
      tester,
    ) async {
      // The bug this guards: source #1 auto-plays, lags, the viewer picks
      // #2 from the sheet — and without this, nothing remembers that.
      // Next play (same session or a cold start) would go straight back
      // to #1, the one they just switched away from.
      final item = fakeItem(title: 'Some Movie');
      final resolved = [
        const ResolvedSource(
          source: StreamSource(id: 'a', label: 'Kora HD'),
          stream: PlayableStream(
            url: 'https://edge/a.m3u8',
            format: StreamFormat.hls,
          ),
        ),
        const ResolvedSource(
          source: StreamSource(id: 'b', label: 'Cricfy SD'),
          stream: PlayableStream(
            url: 'https://edge/b.m3u8',
            format: StreamFormat.hls,
          ),
        ),
      ];
      final sourceCache = SourceCache();
      sourceCache.store(item.ref, resolved);
      sourceCache.recordSourceList(item.ref, [
        resolved[0].source,
        resolved[1].source,
      ]);

      await tester.pumpWidget(
        wrapApp(
          child: PlayerPage(item: item, resolvedSources: resolved),
          registry: ExtensionRegistry(const []),
          sourceCache: sourceCache,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.playlist_play_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cricfy SD'));
      await tester.pumpAndSettle();

      expect(sourceCache.peek(item.ref)!.map((s) => s.source.id), ['b', 'a']);
      expect(sourceCache.peekSourceList(item.ref)!.map((s) => s.id), [
        'b',
        'a',
      ]);
    });

    testWidgets(
      'opening the picker and backing out without choosing promotes nothing',
      (tester) async {
        final item = fakeItem(title: 'Some Movie');
        final resolved = [
          const ResolvedSource(
            source: StreamSource(id: 'a', label: 'Kora HD'),
            stream: PlayableStream(
              url: 'https://edge/a.m3u8',
              format: StreamFormat.hls,
            ),
          ),
          const ResolvedSource(
            source: StreamSource(id: 'b', label: 'Cricfy SD'),
            stream: PlayableStream(
              url: 'https://edge/b.m3u8',
              format: StreamFormat.hls,
            ),
          ),
        ];
        final sourceCache = SourceCache();
        sourceCache.store(item.ref, resolved);

        await tester.pumpWidget(
          wrapApp(
            child: PlayerPage(item: item, resolvedSources: resolved),
            registry: ExtensionRegistry(const []),
            sourceCache: sourceCache,
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.playlist_play_rounded));
        await tester.pumpAndSettle();
        // Dismiss the sheet by tapping the barrier instead of a source.
        await tester.tapAt(const Offset(400, 50));
        await tester.pumpAndSettle();

        expect(sourceCache.peek(item.ref)!.map((s) => s.source.id), ['a', 'b']);
      },
    );
  });

  group('dedupedQualityTracks', () {
    BetterPlayerAsmsTrack track({int? height, int? bitrate, String id = ''}) =>
        BetterPlayerAsmsTrack(id, 0, height, bitrate, 0, '', '');

    test('sorts highest resolution first', () {
      final result = dedupedQualityTracks([
        track(height: 480, bitrate: 1),
        track(height: 1080, bitrate: 1),
        track(height: 720, bitrate: 1),
      ]);
      expect(result.map((t) => t.height), [1080, 720, 480]);
    });

    test('keeps the highest-bitrate variant when a resolution repeats', () {
      final result = dedupedQualityTracks([
        track(height: 1080, bitrate: 2000, id: 'low'),
        track(height: 1080, bitrate: 5000, id: 'high'),
      ]);
      expect(result, hasLength(1));
      expect(result.single.id, 'high');
    });

    test('drops the zero-height "auto" placeholder', () {
      final result = dedupedQualityTracks([
        BetterPlayerAsmsTrack.defaultTrack(),
        track(height: 720, bitrate: 1),
      ]);
      expect(result, hasLength(1));
      expect(result.single.height, 720);
    });

    test('an empty list stays empty', () {
      expect(dedupedQualityTracks(const []), isEmpty);
    });
  });

  group('quality control', () {
    testWidgets('the quality button is present in the controls', (
      tester,
    ) async {
      final item = fakeItem(title: 'Some Movie');
      final resolved = [
        const ResolvedSource(
          source: StreamSource(id: 's', label: 'HD'),
          stream: PlayableStream(
            url: 'https://edge/movie.m3u8',
            format: StreamFormat.hls,
          ),
        ),
      ];

      await tester.pumpWidget(
        wrapApp(
          child: PlayerPage(item: item, resolvedSources: resolved),
          registry: ExtensionRegistry(const []),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.high_quality_rounded), findsOneWidget);
    });
  });
}
