import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_app/player/play_item.dart';
import 'package:fvcksubs_app/player/player_page.dart';
import 'package:fvcksubs_app/player/source_cache.dart';
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';

import 'support/harness.dart';

/// Pressing Play: resolve everything up front under an overlay, then open the
/// player already able to switch between sources.
void main() {
  Widget playButton(MediaItem item) => Builder(
    builder: (context) => ElevatedButton(
      onPressed: () => playItem(context, item),
      child: const Text('play'),
    ),
  );

  Widget playButtonV2(MediaItemV2 item) => Builder(
    builder: (context) => ElevatedButton(
      onPressed: () => playItemV2(context, item),
      child: const Text('play v2'),
    ),
  );

  testWidgets('protocol v2 resolves sources and opens the native player', (
    tester,
  ) async {
    const item = VideoItemV2(
      ref: MediaRef(extensionId: 'fake', providerId: 'fake.p', id: 'video'),
      title: 'Native v2',
    );
    final registry = ExtensionRegistry([
      _V2FakeExtension(
        sourceList: const [StreamSource(id: 'primary', label: 'Primary')],
        resolved: const PlayableStream(
          url: 'https://edge/video.m3u8',
          format: StreamFormat.hls,
        ),
      ),
    ]);

    await tester.pumpWidget(
      wrapApp(child: playButtonV2(item), registry: registry),
    );
    await tester.tap(find.text('play v2'));
    await tester.pumpAndSettle();

    expect(find.byType(PlayerPage), findsOneWidget);
    expect(find.text('Native v2'), findsOneWidget);
  });

  Widget seriesPlayButton(MediaItem item, List<SeriesSeason> seasons) =>
      Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => playItem(context, item, seasons: seasons),
          child: const Text('play'),
        ),
      );

  testWidgets('the wait is an overlay, not a screen of its own', (
    tester,
  ) async {
    final item = fakeItem();
    final registry = ExtensionRegistry([
      FakeExtension(
        sourceList: const [StreamSource(id: 's', label: 'HD')],
        // Held open, or the resolve finishes inside a microtask and there is
        // no in-flight state left to look at.
        sourcesDelay: const Duration(milliseconds: 200),
        resolved: const PlayableStream(
          url: 'https://edge/live.m3u8',
          format: StreamFormat.hls,
        ),
      ),
    ]);

    await tester.pumpWidget(
      wrapApp(child: playButton(item), registry: registry),
    );
    await tester.tap(find.text('play'));
    // Mid-resolve: the spinner is up, and the screen that launched it is
    // still there underneath — the whole point of not pushing a page.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('play'), findsOneWidget);

    await tester.pumpAndSettle();

    // ...and it leaves nothing behind once the player is up.
    expect(find.byType(PlayerPage), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('the player opens as soon as one source is resolved', (
    tester,
  ) async {
    final item = fakeItem();
    final registry = ExtensionRegistry([
      FakeExtension(
        sourceList: const [
          StreamSource(id: 'a', label: 'Kora HD'),
          StreamSource(id: 'b', label: 'Cricfy SD'),
        ],
        resolved: const PlayableStream(
          url: 'https://edge/live.m3u8',
          format: StreamFormat.hls,
        ),
      ),
    ]);

    await tester.pumpWidget(
      wrapApp(child: playButton(item), registry: registry),
    );
    await tester.tap(find.text('play'));
    await tester.pumpAndSettle();

    final player = tester.widget<PlayerPage>(find.byType(PlayerPage));
    expect(player.resolvedSources, hasLength(1));
    // The first source is enough to start playback. Remaining sources resolve
    // in the background so a slow provider cannot hold the player hostage.
    expect(player.resolvedSources.first.source.id, 'a');
    // The app bar names what is being watched, not which server serves it.
    expect(find.text(item.title), findsOneWidget);
    // The source label appears in the bottom controls' source picker pill —
    // the player shows which source is active so the user can switch.
    expect(find.text('Kora HD'), findsOneWidget);
  });

  testWidgets('an item with no sources says so instead of opening a player', (
    tester,
  ) async {
    final item = fakeItem();
    final registry = ExtensionRegistry([FakeExtension()]);

    await tester.pumpWidget(
      wrapApp(child: playButton(item), registry: registry),
    );
    await tester.tap(find.text('play'));
    await tester.pumpAndSettle();

    expect(find.byType(PlayerPage), findsNothing);
    expect(find.text('No playable sources found.'), findsOneWidget);
    // Still on the screen it started from, with the overlay gone.
    expect(find.text('play'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('retries a transient empty live source result', (tester) async {
    final item = fakeItem();
    var calls = 0;
    final extension = FakeExtension(
      sourceListFor: (_) {
        calls++;
        return calls == 1
            ? const []
            : const [StreamSource(id: 'live', label: 'Live')];
      },
      resolved: const PlayableStream(
        url: 'https://edge/live.m3u8',
        format: StreamFormat.hls,
      ),
    );

    await tester.pumpWidget(
      wrapApp(
        child: playButton(item),
        registry: ExtensionRegistry([extension]),
      ),
    );
    await tester.tap(find.text('play'));
    await tester.pumpAndSettle();

    expect(find.byType(PlayerPage), findsOneWidget);
    expect(calls, 2);
  });

  testWidgets('a stream this platform cannot play is dropped', (tester) async {
    final item = fakeItem();
    final registry = ExtensionRegistry([
      FakeExtension(
        sourceList: const [StreamSource(id: 'a', label: 'PlayReady')],
        // A scheme no target supports — Android takes Widevine and ClearKey
        // happily, so those would prove nothing here.
        resolved: const PlayableStream(
          url: 'https://edge/x.mpd',
          format: StreamFormat.dash,
          drm: DrmConfig(
            scheme: DrmScheme.unsupported,
            licenseUrl: 'https://l',
          ),
        ),
      ),
    ]);

    await tester.pumpWidget(
      wrapApp(child: playButton(item), registry: registry),
    );
    await tester.tap(find.text('play'));
    await tester.pumpAndSettle();

    expect(find.byType(PlayerPage), findsNothing);
    expect(find.text('No playable sources found.'), findsOneWidget);
  });

  testWidgets('the wait names the sources still outstanding', (tester) async {
    // A bare spinner over a slow fan-out reads as a hang. What is named is
    // what is genuinely still being asked — not an animation through invented
    // steps that would keep running after the work finished.
    final item = fakeItem(extensionId: 'subs');
    final registry = ExtensionRegistry([
      SubtitleFakeExtension(
        subtitlesBySourceId: const {
          'a': ['en'],
          'b': ['id'],
        },
        resolveDelay: const Duration(milliseconds: 300),
      ),
    ]);

    await tester.pumpWidget(
      wrapApp(child: playButton(item), registry: registry),
    );
    await tester.tap(find.text('play'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Both are outstanding, so one of their names is on screen, with a count.
    expect(find.textContaining('Checking '), findsOneWidget);
    expect(find.text('0 of 2 ready'), findsOneWidget);
    expect(find.byIcon(Icons.travel_explore), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.byType(PlayerPage), findsOneWidget);
  });

  testWidgets('a source resolved once plays again without re-resolving', (
    tester,
  ) async {
    final item = fakeItem();
    final extension = FakeExtension(
      sourceList: const [StreamSource(id: 'a', label: 'HD')],
      resolved: const PlayableStream(
        url: 'https://edge/live.m3u8',
        format: StreamFormat.hls,
      ),
    );
    final registry = ExtensionRegistry([extension]);

    await tester.pumpWidget(
      wrapApp(child: playButton(item), registry: registry),
    );
    await tester.tap(find.text('play'));
    await tester.pumpAndSettle();

    expect(find.byType(PlayerPage), findsOneWidget);
    expect(extension.sourcesCalls, 1);
    expect(extension.resolveCalls, 1);

    // Back out to the screen playItem was launched from.
    Navigator.of(tester.element(find.byType(PlayerPage))).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.text('play'));
    // No overlay this time — a resolved source is already on hand, so there
    // is nothing to wait on.
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pumpAndSettle();

    expect(find.byType(PlayerPage), findsOneWidget);
    // Neither call happened again.
    expect(extension.sourcesCalls, 1);
    expect(extension.resolveCalls, 1);
  });

  testWidgets('a fresh cache hit does not revalidate in the background', (
    tester,
  ) async {
    final item = fakeItem();
    final extension = FakeExtension(
      sourceList: const [StreamSource(id: 'a', label: 'HD')],
      resolved: const PlayableStream(
        url: 'https://edge/live.m3u8',
        format: StreamFormat.hls,
      ),
    );
    final registry = ExtensionRegistry([extension]);
    var now = DateTime(2026);
    final cache = SourceCache(now: () => now);

    await tester.pumpWidget(
      wrapApp(child: playButton(item), registry: registry, sourceCache: cache),
    );
    await tester.tap(find.text('play'));
    await tester.pumpAndSettle();
    expect(extension.resolveCalls, 1);

    Navigator.of(tester.element(find.byType(PlayerPage))).pop();
    await tester.pumpAndSettle();

    // Well inside the revalidate window — just a cache hit, nothing else.
    now = now.add(const Duration(minutes: 1));
    await tester.tap(find.text('play'));
    await tester.pumpAndSettle();

    expect(find.byType(PlayerPage), findsOneWidget);
    expect(extension.resolveCalls, 1);
  });

  testWidgets(
    'a stale cache hit plays instantly and revalidates in the background',
    (tester) async {
      final item = fakeItem();
      final extension = FakeExtension(
        sourceList: const [StreamSource(id: 'a', label: 'HD')],
        resolved: const PlayableStream(
          url: 'https://edge/live.m3u8',
          format: StreamFormat.hls,
        ),
      );
      final registry = ExtensionRegistry([extension]);
      var now = DateTime(2026);
      final cache = SourceCache(
        now: () => now,
        revalidateAfter: const Duration(minutes: 3),
      );

      await tester.pumpWidget(
        wrapApp(
          child: playButton(item),
          registry: registry,
          sourceCache: cache,
        ),
      );
      await tester.tap(find.text('play'));
      await tester.pumpAndSettle();
      expect(extension.resolveCalls, 1);

      Navigator.of(tester.element(find.byType(PlayerPage))).pop();
      await tester.pumpAndSettle();

      // Past the revalidate window.
      now = now.add(const Duration(minutes: 4));
      await tester.tap(find.text('play'));
      // No overlay on the way in — the cache hit needs no wait, unlike the
      // background refresh that's about to start alongside it.
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);

      await tester.pumpAndSettle();
      // The quiet refresh ran, and it's the only extra call — playback
      // itself was never interrupted to wait on it.
      expect(extension.resolveCalls, 2);
      expect(find.byType(PlayerPage), findsOneWidget);
    },
  );

  testWidgets(
    'a cache entry hours old still plays instantly, not a hard-TTL miss',
    (tester) async {
      // What used to be past SourceCache's old 15-minute ttl: entries no
      // longer expire by age, since an hour-old resolved link is no more or
      // less likely to be dead than a three-minute-old one — see
      // SourceCache's class doc comment.
      final item = fakeItem();
      final extension = FakeExtension(
        sourceList: const [StreamSource(id: 'a', label: 'HD')],
        resolved: const PlayableStream(
          url: 'https://edge/live.m3u8',
          format: StreamFormat.hls,
        ),
      );
      final registry = ExtensionRegistry([extension]);
      var now = DateTime(2026);
      final cache = SourceCache(now: () => now);

      await tester.pumpWidget(
        wrapApp(
          child: playButton(item),
          registry: registry,
          sourceCache: cache,
        ),
      );
      await tester.tap(find.text('play'));
      await tester.pumpAndSettle();
      expect(extension.resolveCalls, 1);

      Navigator.of(tester.element(find.byType(PlayerPage))).pop();
      await tester.pumpAndSettle();

      now = now.add(const Duration(hours: 6));
      await tester.tap(find.text('play'));
      // Instant, no "finding sources" overlay — a hard-TTL miss would fall
      // through to the full blocking fan-out here instead.
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.pumpAndSettle();
      expect(find.byType(PlayerPage), findsOneWidget);
    },
  );

  group('cold-start fast path (persisted source list, no resolved cache)', () {
    SourceCache seededCache(MediaRef ref, List<StreamSource> sources) {
      final cache = SourceCache();
      cache.recordSourceList(ref, sources);
      return cache;
    }

    testWidgets(
      'a persisted source list opens on just the first, then tops up the '
      'rest in the background',
      (tester) async {
        final item = fakeItem();
        final extension = FakeExtension(
          sourceList: const [
            StreamSource(id: 'a', label: 'Kora HD'),
            StreamSource(id: 'b', label: 'Cricfy SD'),
          ],
          resolved: const PlayableStream(
            url: 'https://edge/live.m3u8',
            format: StreamFormat.hls,
          ),
        );
        final registry = ExtensionRegistry([extension]);
        final sourceCache = seededCache(item.ref, const [
          StreamSource(id: 'a', label: 'Kora HD'),
          StreamSource(id: 'b', label: 'Cricfy SD'),
        ]);

        await tester.pumpWidget(
          wrapApp(
            child: playButton(item),
            registry: registry,
            sourceCache: sourceCache,
          ),
        );
        await tester.tap(find.text('play'));
        await tester.pumpAndSettle();

        // The player opened on just the persisted primary — a full fan-out
        // would have handed it both. What actually skipped discovery is
        // only observable here, in what the player was given: the
        // background revalidate below runs discovery anyway (see its own
        // assertions), so `sourcesCalls` can't distinguish the two paths by
        // itself once settled.
        expect(find.byType(PlayerPage), findsOneWidget);
        final player = tester.widget<PlayerPage>(find.byType(PlayerPage));
        expect(player.resolvedSources, hasLength(1));
        expect(player.resolvedSources.single.source.id, 'a');

        // The viewer is already watching by the time this fires — it's a
        // full discovery+resolve, refreshing both the resolved cache and
        // (via _playableSources) the persisted source list, same as a
        // stale in-memory cache hit's background revalidate.
        expect(extension.sourcesCalls, 1);
        // 1 from the fast path above + 2 from this fan-out re-asking for
        // both — it doesn't know the first was already confirmed.
        expect(extension.resolveCalls, 3);
        expect(sourceCache.peek(item.ref), hasLength(2));
      },
    );

    testWidgets(
      'the change-source chip appears once the background top-up lands',
      (tester) async {
        // The bug this guards: the fast path opens PlayerPage with only one
        // ResolvedSource, and the "change source" chip is gated on there
        // being more than one — so without PlayerPage picking up the
        // top-up itself, restarting the app and playing something whose
        // source was already known meant no way to switch sources until
        // backing out and pressing Play again.
        final item = fakeItem();
        final extension = FakeExtension(
          sourceList: const [
            StreamSource(id: 'a', label: 'Kora HD'),
            StreamSource(id: 'b', label: 'Cricfy SD'),
          ],
          resolved: const PlayableStream(
            url: 'https://edge/live.m3u8',
            format: StreamFormat.hls,
          ),
        );
        final registry = ExtensionRegistry([extension]);
        final sourceCache = seededCache(item.ref, const [
          StreamSource(id: 'a', label: 'Kora HD'),
          StreamSource(id: 'b', label: 'Cricfy SD'),
        ]);

        await tester.pumpWidget(
          wrapApp(
            child: playButton(item),
            registry: registry,
            sourceCache: sourceCache,
          ),
        );
        await tester.tap(find.text('play'));
        await tester.pumpAndSettle();

        // The background top-up (no artificial delay in this fake) has
        // already landed by the time pumpAndSettle returns.
        expect(find.byIcon(Icons.playlist_play_rounded), findsOneWidget);

        // Still playing the original primary — the top-up filled in the
        // rest without interrupting playback.
        final player = tester.widget<PlayerPage>(find.byType(PlayerPage));
        expect(player.resolvedSources.single.source.id, 'a');
      },
    );

    testWidgets('a stale persisted primary falls back to full discovery', (
      tester,
    ) async {
      final item = fakeItem();
      final extension = FakeExtension(
        sourceList: const [StreamSource(id: 'b', label: 'Cricfy SD')],
        resolved: const PlayableStream(
          url: 'https://edge/live.m3u8',
          format: StreamFormat.hls,
        ),
        resolveFailsFor: const {'a'},
      );
      final registry = ExtensionRegistry([extension]);
      // Persisted from an earlier session — source 'a' no longer resolves
      // (the upstream dropped it); only the fan-out below would find 'b'.
      final sourceCache = seededCache(item.ref, const [
        StreamSource(id: 'a', label: 'Kora HD (gone)'),
      ]);

      await tester.pumpWidget(
        wrapApp(
          child: playButton(item),
          registry: registry,
          sourceCache: sourceCache,
        ),
      );
      await tester.tap(find.text('play'));
      await tester.pumpAndSettle();

      expect(find.byType(PlayerPage), findsOneWidget);
      expect(extension.sourcesCalls, 1);
      final player = tester.widget<PlayerPage>(find.byType(PlayerPage));
      expect(player.resolvedSources.single.source.id, 'b');
    });
  });

  testWidgets('seasons passed to playItem reach the player', (tester) async {
    final item = fakeItem();
    final registry = ExtensionRegistry([
      FakeExtension(
        sourceList: const [StreamSource(id: 'a', label: 'HD')],
        resolved: const PlayableStream(
          url: 'https://edge/live.m3u8',
          format: StreamFormat.hls,
        ),
      ),
    ]);
    const seasons = [
      SeriesSeason(
        number: 1,
        name: 'Season 1',
        episodes: [
          SeriesEpisode(title: 'Ep 1'),
          SeriesEpisode(title: 'Ep 2'),
        ],
      ),
    ];

    await tester.pumpWidget(
      wrapApp(child: seriesPlayButton(item, seasons), registry: registry),
    );
    await tester.tap(find.text('play'));
    await tester.pumpAndSettle();

    final player = tester.widget<PlayerPage>(find.byType(PlayerPage));
    expect(player.seasons, seasons);
  });

  testWidgets(
    'replaceCurrent swaps the player route instead of stacking a new one',
    (tester) async {
      final item = fakeItem();
      final next = fakeItem(id: 'e2', title: 'Next Episode');
      final registry = ExtensionRegistry([
        FakeExtension(
          sourceList: const [StreamSource(id: 'a', label: 'HD')],
          resolved: const PlayableStream(
            url: 'https://edge/live.m3u8',
            format: StreamFormat.hls,
          ),
        ),
      ]);

      await tester.pumpWidget(
        wrapApp(child: playButton(item), registry: registry),
      );
      await tester.tap(find.text('play'));
      await tester.pumpAndSettle();
      expect(find.byType(PlayerPage), findsOneWidget);

      // What auto-next does from inside the player: call playItem again with
      // replaceCurrent, using the still-mounted PlayerPage's own context.
      final playerContext = tester.element(find.byType(PlayerPage));
      await playItem(playerContext, next, replaceCurrent: true);
      await tester.pumpAndSettle();

      // Exactly one PlayerPage — a plain push would have left the old one
      // mounted underneath, so this also proves the route was replaced, not
      // stacked on top of.
      expect(find.byType(PlayerPage), findsOneWidget);
      expect(find.text('Next Episode'), findsOneWidget);
    },
  );

  testWidgets('before the source list lands there is nothing to name', (
    tester,
  ) async {
    final item = fakeItem();
    final registry = ExtensionRegistry([
      FakeExtension(
        sourceList: const [StreamSource(id: 's', label: 'HD')],
        sourcesDelay: const Duration(milliseconds: 300),
        resolved: const PlayableStream(
          url: 'https://edge/live.m3u8',
          format: StreamFormat.hls,
        ),
      ),
    ]);

    await tester.pumpWidget(
      wrapApp(child: playButton(item), registry: registry),
    );
    await tester.tap(find.text('play'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Finding sources…'), findsOneWidget);
    expect(find.textContaining('ready'), findsNothing);

    await tester.pumpAndSettle();
  });
}

class _V2FakeExtension extends FakeExtension {
  _V2FakeExtension({required super.sourceList, required super.resolved});

  @override
  Future<List<StreamSource>> sourcesV2(
    MediaItemV2 item, {
    Set<String>? enabledProviders,
  }) => Future.value(sourceList);
}
