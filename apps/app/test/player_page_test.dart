import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_app/detail/detail_page_v2.dart';
import 'package:fvcksubs_app/player/models/app_player_controller.dart';
import 'package:fvcksubs_app/player/models/playback_start_position.dart';
import 'package:fvcksubs_app/player/player_page.dart';
import 'package:fvcksubs_app/player/state/quality_preference_controller.dart';
import 'package:fvcksubs_app/player/state/picture_in_picture_preference_controller.dart';
import 'package:fvcksubs_app/player/state/picture_in_picture_session.dart';
import 'package:fvcksubs_app/player/state/subtitle_preference_controller.dart';
import 'package:fvcksubs_app/player/widgets/video_player_view.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';

import 'support/harness.dart';

void main() {
  test('VOD MP4 stalls use a different source instead of renewal', () {
    expect(
      shouldFallbackAfterVODStall(isLive: false, format: StreamFormat.mp4),
      isTrue,
    );
    expect(
      shouldFallbackAfterVODStall(isLive: false, format: StreamFormat.hls),
      isFalse,
    );
    expect(
      shouldFallbackAfterVODStall(isLive: true, format: StreamFormat.mp4),
      isFalse,
    );
  });

  test('live buffering and renewal health use playback progress', () {
    expect(
      liveForwardBuffer(
        position: const Duration(milliseconds: 107750),
        bufferedPosition: const Duration(milliseconds: 107839),
      ),
      const Duration(milliseconds: 89),
    );
    expect(
      liveContiguousForwardBuffer(
        position: const Duration(milliseconds: 25836),
        bufferedPosition: const Duration(milliseconds: 33882),
        bufferedRanges: [
          const AppPlayerTimeRange(
            Duration(milliseconds: 24454),
            Duration(milliseconds: 27398),
          ),
          const AppPlayerTimeRange(
            Duration(seconds: 30),
            Duration(milliseconds: 33882),
          ),
        ],
      ),
      const Duration(milliseconds: 1562),
    );
    expect(
      liveBufferingNeedsRecovery(
        position: const Duration(milliseconds: 107750),
        bufferedPosition: const Duration(milliseconds: 107839),
        isPlaying: true,
        isBuffering: true,
      ),
      isTrue,
    );
    expect(
      liveBufferingNeedsRecovery(
        position: const Duration(milliseconds: 25836),
        bufferedPosition: const Duration(milliseconds: 33882),
        bufferedRanges: [
          const AppPlayerTimeRange(
            Duration(milliseconds: 30_000),
            Duration(milliseconds: 33_882),
          ),
        ],
        previousPosition: const Duration(milliseconds: 25836),
        isPlaying: true,
        isBuffering: true,
      ),
      isTrue,
    );
    expect(
      liveBufferingNeedsRecovery(
        position: const Duration(milliseconds: 106323),
        bufferedPosition: const Duration(milliseconds: 107839),
        isPlaying: true,
        isBuffering: true,
      ),
      isFalse,
    );
    expect(
      liveBufferingNeedsRecovery(
        position: const Duration(seconds: 12),
        bufferedPosition: const Duration(milliseconds: 17802),
        previousPosition: const Duration(milliseconds: 17943),
        isPlaying: true,
        isBuffering: true,
      ),
      isTrue,
    );
    expect(
      liveBufferingNeedsRecovery(
        position: const Duration(seconds: 12),
        bufferedPosition: const Duration(milliseconds: 17802),
        previousPosition: const Duration(seconds: 12),
        isPlaying: true,
        isBuffering: true,
      ),
      isTrue,
    );
    expect(
      playbackIsStableForRenewalReset(
        isLive: true,
        position: const Duration(seconds: 20),
        isPlaying: true,
        isBuffering: false,
      ),
      isTrue,
    );
    expect(
      playbackIsStableForRenewalReset(
        isLive: true,
        position: Duration.zero,
        isPlaying: true,
        isBuffering: false,
      ),
      isFalse,
    );
    expect(
      playbackIsStableForRenewalReset(
        isLive: true,
        position: const Duration(seconds: 20),
        isPlaying: true,
        isBuffering: true,
      ),
      isFalse,
    );
  });

  testWidgets('portrait video receives the full player viewport', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(390, 844));
    final player = _FullViewportPlayer();

    await tester.pumpWidget(
      wrapApp(
        child: PlayerPage(
          item: const VideoItemV2(
            ref: MediaRef(
              extensionId: 'test',
              providerId: 'test.provider',
              id: 'portrait-movie',
            ),
            title: 'Portrait movie',
          ),
          resolvedSources: [_resolvedSource('portrait', 'Source')],
        ),
        registry: ExtensionRegistry([]),
        player: player,
      ),
    );
    await tester.pump();

    expect(
      tester.getSize(find.byKey(_FullViewportPlayer.marker)),
      const Size(390, 844),
    );
  });

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
    final player = _PositionRecordingPlayer();
    final first = _resolvedSource('first', 'Source A');
    final second = _resolvedSource('second', 'Source B');

    await tester.pumpWidget(
      wrapApp(
        child: PlayerPage(
          key: GlobalKey(),
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

    await tester.tap(find.byTooltip('Source A'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Source B').last);
    await tester.pumpAndSettle();

    expect(player.played, second.stream);
    expect(player.buildCount, greaterThan(initialBuilds));
    expect(player.controllers[1].lastSeekPosition, const Duration(minutes: 25));
    expect(find.byTooltip('Source B'), findsOneWidget);
  });

  testWidgets('passes the preferred maximum quality to the player', (
    tester,
  ) async {
    final player = RecordingPlayer();
    final quality = QualityPreferenceController(
      store: FakeQualityPreferenceStore(),
      initial: 720,
    );

    await tester.pumpWidget(
      wrapApp(
        child: PlayerPage(
          key: GlobalKey(),
          item: const VideoItemV2(
            ref: MediaRef(
              extensionId: 'test',
              providerId: 'test.provider',
              id: 'movie-quality',
            ),
            title: 'Movie',
          ),
          resolvedSources: [_resolvedSource('quality', 'Source')],
        ),
        registry: ExtensionRegistry([]),
        player: player,
        qualityPreferenceController: quality,
      ),
    );
    await tester.pump();

    expect(player.playedPreferredQualityMaxHeight, 720);
  });

  testWidgets('an initial playback error falls back to the next source', (
    tester,
  ) async {
    final player = _FailingPlayer();
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
    expect(
      player.controllers.any((controller) => controller.hasListener),
      isTrue,
    );

    player.controllers.single.emitError(StateError('source rejected'));
    await tester.pump();
    await tester.pump();

    expect(player.played, second.stream);
    expect(
      find.text('Source is unavailable. Try another source or retry later.'),
      findsNothing,
    );
  });

  testWidgets('an initial error waits silently for a late source', (
    tester,
  ) async {
    final player = _FailingPlayer();
    final first = _resolvedSource('first', 'Source A');
    final later = _resolvedSource('later', 'Source B');
    final pending = StreamController<ResolvedSource>();

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
          resolvedSources: [first],
          pendingSources: pending.stream,
        ),
        registry: ExtensionRegistry([]),
        player: player,
      ),
    );
    await tester.pump();

    player.controllers.single.emitError(StateError('source rejected'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Finding another source…'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('player-fallback-loading-indicator')),
      findsOneWidget,
    );

    pending.add(later);
    await tester.pump();
    await tester.pump();

    expect(player.played, later.stream);
    expect(find.text('Finding another source…'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('player-fallback-loading-indicator')),
      findsNothing,
    );
    await pending.close();
  });

  testWidgets('does not wait forever for a late fallback source', (
    tester,
  ) async {
    final player = _FailingPlayer();
    final first = _resolvedSource('first', 'Source A');
    final pending = StreamController<ResolvedSource>();

    await tester.pumpWidget(
      wrapApp(
        child: PlayerPage(
          item: const VideoItemV2(
            ref: MediaRef(
              extensionId: 'test',
              providerId: 'test.provider',
              id: 'fallback-timeout',
            ),
            title: 'Movie',
          ),
          resolvedSources: [first],
          pendingSources: pending.stream,
        ),
        registry: ExtensionRegistry([]),
        player: player,
      ),
    );
    await tester.pump();

    player.controllers.single.emitError(StateError('source rejected'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 11));

    expect(
      find.byKey(const ValueKey<String>('player-fallback-loading-indicator')),
      findsNothing,
    );
    expect(find.text("Couldn't play this source"), findsOneWidget);
    await pending.close();
  });

  testWidgets('a recovered source hides the fallback loading overlay', (
    tester,
  ) async {
    final player = _FailingPlayer();
    final first = _resolvedSource('first', 'Source A');
    final pending = StreamController<ResolvedSource>();

    await tester.pumpWidget(
      wrapApp(
        child: PlayerPage(
          item: const VideoItemV2(
            ref: MediaRef(
              extensionId: 'test',
              providerId: 'test.provider',
              id: 'movie-recovered',
            ),
            title: 'Movie',
          ),
          resolvedSources: [first],
          pendingSources: pending.stream,
        ),
        registry: ExtensionRegistry([]),
        player: player,
      ),
    );
    await tester.pump();

    final controller = player.controllers.single;
    controller.emitError(StateError('source temporarily unavailable'));
    await tester.pump();
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('player-fallback-loading-indicator')),
      findsOneWidget,
    );

    controller.emitValue(
      const AppPlayerValue(
        initialized: true,
        isPlaying: true,
        position: Duration(seconds: 1),
        duration: Duration(minutes: 10),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('player-fallback-loading-indicator')),
      findsNothing,
    );
    await pending.close();
  });

  // First play resolves nothing from cache: the player opens on the first
  // source that lands and the slower providers arrive afterwards on
  // `pendingSources`. Kora consistently settles about a second after Cricfy,
  // so if that stream never reaches the picker, its sources never show up.
  testWidgets('sources arriving after the player opens reach the picker', (
    tester,
  ) async {
    final player = RecordingPlayer();
    final first = _resolvedSource('cricfy-1', 'Server 3');
    final later = _resolvedSource('kora-1', 'Bein Sport 1');
    final controller = StreamController<ResolvedSource>();

    await tester.pumpWidget(
      wrapApp(
        child: PlayerPage(
          item: const VideoItemV2(
            ref: MediaRef(
              extensionId: 'test',
              providerId: 'test.provider',
              id: 'live-1',
            ),
            title: 'Match',
          ),
          resolvedSources: [first],
          pendingSources: controller.stream,
        ),
        registry: ExtensionRegistry([]),
        player: player,
      ),
    );
    await tester.pump();
    final initialBuilds = player.buildCount;

    controller.add(later);
    await tester.pumpAndSettle();

    expect(
      player.buildCount,
      initialBuilds,
      reason: 'late source discovery must not rebuild the active player',
    );

    await tester.tap(find.byTooltip('Server 3'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.text('Bein Sport 1'),
      findsOneWidget,
      reason: 'a source that settled after the player opened must be listed',
    );
    await controller.close();
  });

  // The same stream, but the event is emitted before anyone subscribes —
  // exactly what happens while the first source is still being awaited,
  // before the player route has been built at all.
  testWidgets('sources emitted before the page subscribes are not lost', (
    tester,
  ) async {
    final player = RecordingPlayer();
    final first = _resolvedSource('cricfy-1', 'Server 3');
    final later = _resolvedSource('kora-1', 'Bein Sport 1');
    final controller = StreamController<ResolvedSource>();
    controller.add(later);

    await tester.pumpWidget(
      wrapApp(
        child: PlayerPage(
          item: const VideoItemV2(
            ref: MediaRef(
              extensionId: 'test',
              providerId: 'test.provider',
              id: 'live-1',
            ),
            title: 'Match',
          ),
          resolvedSources: [first],
          pendingSources: controller.stream,
        ),
        registry: ExtensionRegistry([]),
        player: player,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Server 3'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Bein Sport 1'), findsOneWidget);
    await controller.close();
  });

  testWidgets('player Back minimizes and remains eligible for native PiP', (
    tester,
  ) async {
    final player = _PositionRecordingPlayer();
    final session = PictureInPictureSession();

    await tester.pumpWidget(
      wrapApp(
        child: PlayerPage(
          item: const VideoItemV2(
            ref: MediaRef(
              extensionId: 'test',
              providerId: 'test.provider',
              id: 'movie-pip',
            ),
            title: 'Movie',
          ),
          returnToDetail: true,
          resolvedSources: [_resolvedSource('pip', 'Source')],
        ),
        registry: ExtensionRegistry([]),
        player: player,
        pictureInPictureSession: session,
      ),
    );
    await tester.pump();
    expect(
      tester
          .widget<PlayerSubtitleVisibility>(
            find.byType(PlayerSubtitleVisibility),
          )
          .showSubtitles,
      isTrue,
    );

    final controller = player.controllers.single;
    controller.emitValue(
      const AppPlayerValue(
        initialized: true,
        isPlaying: true,
        position: Duration(minutes: 25),
        duration: Duration(hours: 1),
      ),
    );

    await tester.tap(find.byTooltip('Minimize player'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(controller.pictureInPictureCalls, 0);
    expect(session.isMinimized, isTrue);
    expect(
      tester
          .widget<PlayerSubtitleVisibility>(
            find.byType(PlayerSubtitleVisibility),
          )
          .showSubtitles,
      isFalse,
    );
    expect(controller.pictureInPictureAllowed, contains(true));
    expect(find.byType(PlayerPage), findsOneWidget);
    expect(find.byType(DetailPageV2), findsNothing);
  });

  testWidgets('automatic PiP restores a playing player when expanded', (
    tester,
  ) async {
    final player = _PositionRecordingPlayer();

    await tester.pumpWidget(
      wrapApp(
        child: PlayerPage(
          item: fakeItem(id: 'automatic-pip'),
          resolvedSources: [_resolvedSource('automatic-pip', 'Source')],
        ),
        registry: ExtensionRegistry([]),
        player: player,
      ),
    );
    await tester.pump();

    final controller = player.controllers.single;
    controller.emitValue(
      const AppPlayerValue(
        initialized: true,
        isPlaying: true,
        duration: Duration(minutes: 10),
      ),
    );
    controller.emitPictureInPictureStarted();
    await tester.pump();

    controller.emitPictureInPictureRestore();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(PlayerPage), findsOneWidget);
    expect(controller.playCalls, 1);
  });

  testWidgets('PiP restores the mini-player presentation it started from', (
    tester,
  ) async {
    final player = _PositionRecordingPlayer();
    final session = PictureInPictureSession();
    final playerPage = PlayerPage(
      key: GlobalKey(),
      item: fakeItem(id: 'mini-pip-restore'),
      resolvedSources: [_resolvedSource('mini-pip-restore', 'Source')],
    );

    await tester.pumpWidget(
      wrapApp(
        child: const SizedBox(),
        registry: ExtensionRegistry([]),
        player: player,
        pictureInPictureSession: session,
      ),
    );
    session.attach(playerPage);
    await tester.pump();
    session.minimize();
    await tester.pump();

    final controller = player.controllers.single;
    controller.emitValue(
      const AppPlayerValue(
        initialized: true,
        isPlaying: true,
        duration: Duration(minutes: 10),
      ),
    );
    controller.emitPictureInPictureStarted();
    await tester.pump();

    controller.emitPictureInPictureRestore();
    await tester.pump();

    expect(session.isMinimized, isTrue);
    expect(controller.pictureInPictureRestoreCompletions, 1);
  });

  testWidgets('closing PiP detaches and disposes the hosted player', (
    tester,
  ) async {
    final player = _PositionRecordingPlayer();
    final session = PictureInPictureSession();
    final playerPage = PlayerPage(
      item: fakeItem(id: 'closed-pip'),
      resolvedSources: [_resolvedSource('closed-pip', 'Source')],
    );

    await tester.pumpWidget(
      wrapApp(
        child: const SizedBox(),
        registry: ExtensionRegistry([]),
        player: player,
        pictureInPictureSession: session,
      ),
    );
    session.attach(playerPage);
    await tester.pump();

    final controller = player.controllers.single;
    controller.emitPictureInPictureClosed();
    await tester.pump();

    expect(find.byType(PlayerPage), findsNothing);
  });

  testWidgets('disabled PiP preference keeps the mini-player in-app', (
    tester,
  ) async {
    final player = _PositionRecordingPlayer();
    final pipController = PictureInPicturePreferenceController(
      store: FakePictureInPicturePreferenceStore(),
      initial: false,
    );

    await tester.pumpWidget(
      wrapApp(
        child: PlayerPage(
          item: fakeItem(id: 'pip-disabled'),
          resolvedSources: [_resolvedSource('pip-disabled', 'Source')],
        ),
        registry: ExtensionRegistry([]),
        player: player,
        pictureInPicturePreferenceController: pipController,
      ),
    );
    await tester.pump();

    final controller = player.controllers.single;
    controller.emitValue(
      const AppPlayerValue(
        initialized: true,
        isPlaying: true,
        duration: Duration(minutes: 10),
      ),
    );

    await tester.tap(find.byTooltip('Minimize player'));
    await tester.pumpAndSettle();

    expect(find.byType(PlayerPage), findsOneWidget);
    expect(controller.pictureInPictureCalls, 0);
  });

  testWidgets('Back does not request native PiP or pause the mini-player', (
    tester,
  ) async {
    final player = _PositionRecordingPlayer();

    await tester.pumpWidget(
      wrapApp(
        child: PlayerPage(
          item: fakeItem(id: 'pip-failed'),
          resolvedSources: [_resolvedSource('pip-failed', 'Source')],
        ),
        registry: ExtensionRegistry([]),
        player: player,
      ),
    );
    await tester.pump();

    final controller = player.controllers.single;
    controller.emitValue(
      const AppPlayerValue(
        initialized: true,
        isPlaying: true,
        duration: Duration(minutes: 10),
      ),
    );

    await tester.tap(find.byTooltip('Minimize player'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(controller.pictureInPictureCalls, 0);
    expect(controller.pauseCalls, 0);
    expect(controller.pictureInPictureAllowed, contains(true));
  });

  testWidgets('live player Back closes before playback starts', (tester) async {
    final player = _PositionRecordingPlayer();

    await tester.pumpWidget(
      wrapApp(
        child: PlayerPage(
          key: GlobalKey(),
          item: fakeItem(id: 'live-pip'),
          resolvedSources: [_resolvedSource('pip-live', 'Live source')],
        ),
        registry: ExtensionRegistry([]),
        player: player,
      ),
    );
    await tester.pump();

    final controller = player.controllers.single;
    await tester.tap(find.byTooltip('Minimize player'));
    await tester.pumpAndSettle();

    expect(controller.pictureInPictureCalls, 0);
    expect(find.byType(PlayerPage), findsNothing);
    expect(find.byType(DetailPageV2), findsNothing);
    expect(find.text('Playing in Picture in Picture'), findsNothing);
  });

  testWidgets('mini-player stays mounted while the caller stays underneath', (
    tester,
  ) async {
    final player = _PositionRecordingPlayer();
    final session = PictureInPictureSession();
    final playerPage = PlayerPage(
      key: GlobalKey(),
      item: fakeItem(id: 'detached-pip'),
      resolvedSources: [_resolvedSource('detached', 'Source')],
    );
    await tester.pumpWidget(
      wrapApp(
        child: Scaffold(
          body: FilledButton(
            onPressed: () {},
            child: const Text('Caller button'),
          ),
        ),
        registry: ExtensionRegistry([]),
        player: player,
        pictureInPictureSession: session,
      ),
    );
    session.attach(playerPage);
    await tester.pump();

    final controller = player.controllers.single;
    controller.emitValue(
      const AppPlayerValue(
        initialized: true,
        isPlaying: true,
        position: Duration(seconds: 10),
        duration: Duration(minutes: 10),
      ),
    );

    await tester.tap(find.byTooltip('Minimize player'));
    await tester.pump(const Duration(milliseconds: 300));

    // The player stays in the app-level host so iOS can restore the same
    // UiKitView surface while the caller remains visible underneath.
    expect(find.text('Caller button'), findsOneWidget);
    expect(find.byType(PlayerPage), findsOneWidget);
    expect(player.controllers, hasLength(1));
    expect(session.isMinimized, isTrue);
    expect(controller.pictureInPictureCalls, 0);
  });

  testWidgets('an external track stands in only where the source has none', (
    tester,
  ) async {
    final player = RecordingPlayer();
    const ref = MediaRef(
      extensionId: 'test',
      providerId: 'test.provider',
      id: 'movie-1',
    );
    const external = SubtitleTrack(
      language: 'id',
      url: 'https://shegu.example/id.srt',
    );
    // The upstream's own spelling, not a bare subtag — the source still
    // counts as carrying the viewer's language.
    final withSubs = _resolvedSource(
      'second',
      'Source B',
      subtitles: const [
        SubtitleTrack(
          language: 'Indonesian',
          url: 'https://stream.example/second.srt',
        ),
      ],
    );
    final withoutSubs = _resolvedSource('first', 'Source A');

    final preference = SubtitlePreferenceController(
      store: FakeSubtitlePreferenceStore(),
      initial: 'id',
    );
    preference.rememberExternalSubtitles(ref, const [external]);

    await tester.pumpWidget(
      wrapApp(
        child: PlayerPage(
          item: const VideoItemV2(ref: ref, title: 'Movie'),
          resolvedSources: [withoutSubs, withSubs],
        ),
        registry: ExtensionRegistry([]),
        player: player,
        subtitlePreferenceController: preference,
      ),
    );
    await tester.pump();

    expect(player.playedPreferredExternalSubtitle, external);

    await tester.tap(find.byTooltip('Source A'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Source B').last);
    await tester.pumpAndSettle();

    expect(player.played, withSubs.stream);
    expect(player.playedPreferredExternalSubtitle, isNull);
  });
}

ResolvedSource _resolvedSource(
  String id,
  String label, {
  List<SubtitleTrack> subtitles = const [],
}) => ResolvedSource(
  source: StreamSource(id: id, label: label),
  stream: PlayableStream(
    url: 'https://stream.example/$id.m3u8',
    format: StreamFormat.hls,
    subtitles: subtitles,
  ),
);

class _FailingPlayer extends RecordingPlayer {
  final List<_FakePlayerController> controllers = [];

  @override
  Widget build(
    BuildContext context,
    PlayableStream stream, {
    required bool isLive,
    void Function(Object? controller)? onControllerCreated,
    void Function(Object? controller)? onPlaybackReady,
    Widget Function(
      BuildContext context,
      Object? controller,
      void Function(bool visibility) onVisibilityChanged,
    )?
    customControlsBuilder,
    String? preferredSubtitleLanguage,
    int? preferredQualityMaxHeight,
    PlaybackStartPosition? startPosition,
    SubtitleTrack? preferredExternalSubtitle,
    SubtitleAppearance? subtitleAppearance,
    Key? key,
  }) {
    final widget = super.build(
      context,
      stream,
      isLive: isLive,
      onControllerCreated: onControllerCreated,
      onPlaybackReady: onPlaybackReady,
      customControlsBuilder: customControlsBuilder,
      preferredSubtitleLanguage: preferredSubtitleLanguage,
      preferredQualityMaxHeight: preferredQualityMaxHeight,
      startPosition: startPosition,
      preferredExternalSubtitle: preferredExternalSubtitle,
      subtitleAppearance: subtitleAppearance,
      key: key,
    );
    if (controllers.isEmpty) {
      final controller = _FakePlayerController();
      controllers.add(controller);
      onControllerCreated?.call(controller);
      onPlaybackReady?.call(controller);
    }
    return widget;
  }
}

class _FullViewportPlayer extends RecordingPlayer {
  static const marker = Key('full-viewport-player');
  final _FakePlayerController controller = _FakePlayerController(
    initialValue: const AppPlayerValue(initialized: true),
  );
  bool _reportedController = false;

  @override
  Widget build(
    BuildContext context,
    PlayableStream stream, {
    required bool isLive,
    void Function(Object? controller)? onControllerCreated,
    void Function(Object? controller)? onPlaybackReady,
    Widget Function(
      BuildContext context,
      Object? controller,
      void Function(bool visibility) onVisibilityChanged,
    )?
    customControlsBuilder,
    String? preferredSubtitleLanguage,
    int? preferredQualityMaxHeight,
    PlaybackStartPosition? startPosition,
    SubtitleTrack? preferredExternalSubtitle,
    SubtitleAppearance? subtitleAppearance,
    Key? key,
  }) {
    if (!_reportedController) {
      _reportedController = true;
      onControllerCreated?.call(controller);
      onPlaybackReady?.call(controller);
    }
    return const SizedBox.expand(key: marker);
  }
}

class _PositionRecordingPlayer extends RecordingPlayer {
  final List<_FakePlayerController> controllers = [];
  String? _lastUrl;

  @override
  Widget build(
    BuildContext context,
    PlayableStream stream, {
    required bool isLive,
    void Function(Object? controller)? onControllerCreated,
    void Function(Object? controller)? onPlaybackReady,
    Widget Function(
      BuildContext context,
      Object? controller,
      void Function(bool visibility) onVisibilityChanged,
    )?
    customControlsBuilder,
    String? preferredSubtitleLanguage,
    int? preferredQualityMaxHeight,
    PlaybackStartPosition? startPosition,
    SubtitleTrack? preferredExternalSubtitle,
    SubtitleAppearance? subtitleAppearance,
    Key? key,
  }) {
    final widget = super.build(
      context,
      stream,
      isLive: isLive,
      onControllerCreated: onControllerCreated,
      onPlaybackReady: onPlaybackReady,
      customControlsBuilder: customControlsBuilder,
      preferredSubtitleLanguage: preferredSubtitleLanguage,
      preferredQualityMaxHeight: preferredQualityMaxHeight,
      startPosition: startPosition,
      preferredExternalSubtitle: preferredExternalSubtitle,
      subtitleAppearance: subtitleAppearance,
      key: key,
    );
    if (_lastUrl == stream.url) return widget;
    _lastUrl = stream.url;
    final controller = _FakePlayerController(
      initialValue: controllers.isEmpty
          ? const AppPlayerValue(
              initialized: true,
              position: Duration(minutes: 25),
              duration: Duration(hours: 1),
            )
          : const AppPlayerValue(
              initialized: true,
              duration: Duration(hours: 1),
            ),
    );
    controllers.add(controller);
    onControllerCreated?.call(controller);
    final target = startPosition?.target(
      controller.value.value.duration,
      isLive: isLive,
    );
    if (target != null) {
      controller.lastSeekPosition = target;
      controller.emitValue(controller.value.value.copyWith(position: target));
    }
    onPlaybackReady?.call(controller);
    return widget;
  }
}

class _FakePlayerController
    implements
        AppPlayerController,
        AppPlayerPictureInPictureRestorer,
        AppPlayerPictureInPicturePolicy {
  _FakePlayerController({AppPlayerValue initialValue = const AppPlayerValue()})
    : _value = ValueNotifier(initialValue);

  final ValueNotifier<AppPlayerValue> _value;
  final StreamController<AppPlayerEvent> _events =
      StreamController<AppPlayerEvent>.broadcast(sync: true);
  Duration? lastSeekPosition;
  bool pictureInPictureResult = false;
  int pictureInPictureCalls = 0;
  int pauseCalls = 0;
  int playCalls = 0;
  final List<bool> pictureInPictureAllowed = [];
  int pictureInPictureRestoreCompletions = 0;

  void emitError(Object error) {
    _events.add(AppPlayerEvent(AppPlayerEventType.error, error: error));
  }

  void emitValue(AppPlayerValue value) {
    _value.value = value;
  }

  void emitPictureInPictureRestore() {
    _events.add(
      const AppPlayerEvent(AppPlayerEventType.pictureInPictureRestore),
    );
  }

  void emitPictureInPictureStarted() {
    _events.add(
      const AppPlayerEvent(AppPlayerEventType.pictureInPictureStarted),
    );
  }

  void emitPictureInPictureClosed() {
    _events.add(
      const AppPlayerEvent(AppPlayerEventType.pictureInPictureClosed),
    );
  }

  bool get hasListener => _events.hasListener;

  @override
  ValueListenable<AppPlayerValue> get value => _value;

  @override
  Stream<AppPlayerEvent> get events => _events.stream;

  @override
  List<AppQualityTrack> get qualityTracks => const [];

  @override
  AppQualityTrack? get activeQuality => null;

  @override
  List<AppAudioTrack> get audioTracks => const [];

  @override
  AppAudioTrack? get activeAudio => null;

  @override
  SubtitleTrack? get activeSubtitle => null;

  @override
  bool get isFullScreen => false;

  @override
  Future<void> play() async => playCalls++;

  @override
  Future<void> pause() async => pauseCalls++;

  @override
  Future<void> seekTo(Duration position) async => lastSeekPosition = position;

  @override
  Future<void> setPlaybackSpeed(double speed) async {}

  @override
  Future<void> setSubtitle(SubtitleTrack? track) async {}

  @override
  Future<void> setQuality(AppQualityTrack? track) async {}

  @override
  Future<void> setAudioTrack(AppAudioTrack track) async {}

  @override
  Future<void> setFit(PlayerFitMode mode) async {}

  @override
  Future<void> setViewportAspectRatio(double ratio) async {}

  @override
  Future<void> toggleFullScreen() async {}

  @override
  Future<void> exitFullScreen() async {}

  @override
  Future<void> setPictureInPictureAllowed(bool allowed) async {
    pictureInPictureAllowed.add(allowed);
  }

  @override
  Future<bool> startPictureInPicture() async {
    pictureInPictureCalls++;
    return pictureInPictureResult;
  }

  @override
  Future<void> stopPictureInPicture() async {}

  @override
  Future<void> completePictureInPictureRestore() async {
    pictureInPictureRestoreCompletions++;
  }
}
