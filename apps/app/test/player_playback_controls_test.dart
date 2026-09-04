import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_app/player/controls/player_controls_overlay.dart';
import 'package:fvcksubs_app/player/controls/player_playback_controls.dart';
import 'package:fvcksubs_app/player/models/app_player_controller.dart';
import 'package:fvcksubs_app/player/models/playback_media.dart';
import 'package:fvcksubs_app/player/state/playback_stall_detector.dart';
import 'package:fvcksubs_app/player/models/resolved_source.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';

import 'support/harness.dart';

void main() {
  testWidgets('episode controls show series title and season context', (
    tester,
  ) async {
    const seriesRef = MediaRef(
      extensionId: 'test',
      providerId: 'test.provider',
      id: 'series-1',
    );
    const episodeRef = MediaRef(
      extensionId: 'test',
      providerId: 'test.provider',
      id: 'series-1-s2e3',
    );
    const episode = EpisodeItemV2(
      ref: episodeRef,
      title: 'Episode title',
      subtitle: 'Example Series',
      episode: EpisodeIdentity(
        parentRef: seriesRef,
        groupId: 'season-2',
        position: 3,
      ),
    );
    const guide = EpisodeGuide(
      groups: [
        EpisodeGroup(
          id: 'season-2',
          title: 'Season 2',
          episodes: [
            EpisodeSummary(
              ref: episodeRef,
              title: 'Episode title',
              position: 3,
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      _controls(
        _RecoveryController(),
        media: const PlaybackMedia(episode),
        episodeGuide: guide,
      ),
    );

    expect(find.text('Example Series'), findsOneWidget);
    expect(find.text('Season 2 · Episode 3'), findsOneWidget);
    expect(find.text('Episode title'), findsNothing);
  });

  testWidgets('episode controls hide opaque group ids without a guide', (
    tester,
  ) async {
    const episode = EpisodeItemV2(
      ref: MediaRef(
        extensionId: 'test',
        providerId: 'test.provider',
        id: 'episode-1',
      ),
      title: 'Episode title',
      subtitle: 'Example Series',
      episode: EpisodeIdentity(
        parentRef: MediaRef(
          extensionId: 'test',
          providerId: 'test.provider',
          id: 'series-1',
        ),
        groupId: 'tt0903747-2',
        position: 3,
      ),
    );

    await tester.pumpWidget(
      _controls(_RecoveryController(), media: const PlaybackMedia(episode)),
    );

    expect(find.text('Example Series'), findsOneWidget);
    expect(find.text('Episode 3'), findsOneWidget);
    expect(find.text('tt0903747-2 · Episode 3'), findsNothing);
  });

  testWidgets(
    'episode controls use episode title when series subtitle is null',
    (tester) async {
      const episode = EpisodeItemV2(
        ref: MediaRef(
          extensionId: 'test',
          providerId: 'test.provider',
          id: 'episode-1',
        ),
        title: 'Episode title',
        episode: EpisodeIdentity(
          parentRef: MediaRef(
            extensionId: 'test',
            providerId: 'test.provider',
            id: 'series-1',
          ),
          groupId: 'opaque-group',
          position: 3,
        ),
      );

      await tester.pumpWidget(
        _controls(_RecoveryController(), media: const PlaybackMedia(episode)),
      );

      expect(find.text('Episode title'), findsOneWidget);
      expect(find.text('Episode 3'), findsOneWidget);
    },
  );

  testWidgets('episode list opens from the player controls', (tester) async {
    final controller = _RecoveryController(
      const AppPlayerValue(
        initialized: true,
        isPlaying: true,
        duration: Duration(minutes: 2),
      ),
    );
    const seriesRef = MediaRef(
      extensionId: 'test',
      providerId: 'test.provider',
      id: 'series-1',
    );
    const currentRef = MediaRef(
      extensionId: 'test',
      providerId: 'test.provider',
      id: 'episode-1',
    );
    const guide = EpisodeGuide(
      groups: [
        EpisodeGroup(
          id: 'season-1',
          title: 'Season 1',
          episodes: [
            EpisodeSummary(ref: currentRef, title: 'Pilot', position: 1),
            EpisodeSummary(
              ref: MediaRef(
                extensionId: 'test',
                providerId: 'test.provider',
                id: 'episode-2',
              ),
              title: 'Second Episode',
              position: 2,
            ),
          ],
        ),
      ],
    );
    var selected = false;
    const current = EpisodeItemV2(
      ref: currentRef,
      title: 'Pilot',
      subtitle: 'Example Series',
      episode: EpisodeIdentity(
        parentRef: seriesRef,
        groupId: 'season-1',
        position: 1,
      ),
    );
    await tester.pumpWidget(
      _controls(
        controller,
        media: const PlaybackMedia(current),
        episodeGuide: guide,
        onPlayEpisode: (_) => selected = true,
      ),
    );

    expect(find.byIcon(Icons.video_library_rounded), findsOneWidget);
    final qualityTopBefore = tester
        .getTopLeft(find.byIcon(Icons.high_quality_rounded))
        .dy;
    await tester.tap(find.byIcon(Icons.video_library_rounded));
    await tester.pump();
    expect(find.byKey(const Key('player-episode-rail')), findsOneWidget);
    expect(find.text('Season 1 · Episode 2'), findsOneWidget);
    expect(
      tester.getTopLeft(find.byIcon(Icons.high_quality_rounded)).dy,
      closeTo(qualityTopBefore, 0.1),
    );

    await tester.tap(find.text('Second Episode'));
    expect(selected, isTrue);
  });

  testWidgets('hiding player controls also closes the episode list', (
    tester,
  ) async {
    const currentRef = MediaRef(
      extensionId: 'test',
      providerId: 'test.provider',
      id: 'episode-1',
    );
    const episode = EpisodeItemV2(
      ref: currentRef,
      title: 'Episode 1',
      subtitle: 'Example Series',
      episode: EpisodeIdentity(
        parentRef: MediaRef(
          extensionId: 'test',
          providerId: 'test.provider',
          id: 'series-1',
        ),
        groupId: 'season-1',
        position: 1,
      ),
    );
    final controller = _RecoveryController(
      const AppPlayerValue(
        initialized: true,
        isPlaying: true,
        duration: Duration(minutes: 2),
      ),
    );
    const guide = EpisodeGuide(
      groups: [
        EpisodeGroup(
          id: 'season-1',
          title: 'Season 1',
          episodes: [
            EpisodeSummary(ref: currentRef, title: 'Episode 1', position: 1),
            EpisodeSummary(
              ref: MediaRef(
                extensionId: 'test',
                providerId: 'test.provider',
                id: 'episode-2',
              ),
              title: 'Episode 2',
              position: 2,
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      _controls(
        controller,
        media: const PlaybackMedia(episode),
        episodeGuide: guide,
      ),
    );
    await tester.tap(find.byIcon(Icons.video_library_rounded));
    await tester.pump();
    expect(find.byKey(const Key('player-episode-rail')), findsOneWidget);

    await tester.tapAt(const Offset(20, 250));
    await tester.pump();
    expect(find.byKey(const Key('player-episode-rail')), findsNothing);
  });

  testWidgets('up-next trigger follows the provider outro marker', (
    tester,
  ) async {
    const episode = EpisodeItemV2(
      ref: MediaRef(
        extensionId: 'test',
        providerId: 'test.provider',
        id: 'episode-1',
      ),
      title: 'Episode',
      subtitle: 'Series',
      episode: EpisodeIdentity(
        parentRef: MediaRef(
          extensionId: 'test',
          providerId: 'test.provider',
          id: 'series-1',
        ),
        groupId: 'season:1',
        position: 1,
      ),
    );
    var nearEndCalls = 0;
    final controller = _RecoveryController(
      const AppPlayerValue(
        initialized: true,
        isPlaying: true,
        position: Duration(seconds: 60),
        duration: Duration(minutes: 2),
      ),
    );

    await tester.pumpWidget(
      _controls(
        controller,
        media: const PlaybackMedia(episode),
        playbackSegments: const [
          PlaybackSegment(
            type: PlaybackSegmentType.outro,
            startMs: 90000,
            endMs: 110000,
          ),
        ],
        onNearEnd: () => nearEndCalls++,
      ),
    );
    expect(nearEndCalls, 0);

    controller.update(
      const AppPlayerValue(
        initialized: true,
        isPlaying: true,
        position: Duration(seconds: 90),
        duration: Duration(minutes: 2),
      ),
    );
    await tester.pump();
    expect(nearEndCalls, 1);
  });

  testWidgets('up-next falls back to one minute without an outro marker', (
    tester,
  ) async {
    const episode = EpisodeItemV2(
      ref: MediaRef(
        extensionId: 'test',
        providerId: 'test.provider',
        id: 'episode-1',
      ),
      title: 'Episode',
      episode: EpisodeIdentity(
        parentRef: MediaRef(
          extensionId: 'test',
          providerId: 'test.provider',
          id: 'series-1',
        ),
        groupId: 'season:1',
        position: 1,
      ),
    );
    var nearEndCalls = 0;
    final controller = _RecoveryController(
      const AppPlayerValue(
        initialized: true,
        isPlaying: true,
        position: Duration(seconds: 59),
        duration: Duration(minutes: 2),
      ),
    );

    await tester.pumpWidget(
      _controls(
        controller,
        media: const PlaybackMedia(episode),
        onNearEnd: () => nearEndCalls++,
      ),
    );
    expect(nearEndCalls, 0);

    controller.update(
      const AppPlayerValue(
        initialized: true,
        isPlaying: true,
        position: Duration(seconds: 60),
        duration: Duration(minutes: 2),
      ),
    );
    await tester.pump();
    expect(nearEndCalls, 1);
  });

  testWidgets('a seek tells the page to hold off its stall watchdog', (
    tester,
  ) async {
    final controller = _RecoveryController(
      const AppPlayerValue(
        initialized: true,
        isPlaying: true,
        position: Duration(seconds: 50),
      ),
    );
    final graces = <Duration>[];

    await tester.pumpWidget(_controls(controller, onSettling: graces.add));
    await tester.tap(find.byIcon(Icons.forward_10_rounded));

    expect(controller.lastSeek, const Duration(seconds: 60));
    expect(graces, [playerSettleGrace(isLive: false, trackSwitch: false)]);
  });

  test('the live grace stays inside the stall watchdog budget', () {
    // A live URL is signed and short-lived, so the re-resolve this defers is
    // the recovery live depends on most. On demand there is no such urgency.
    final threshold = PlaybackStallDetector().threshold;
    expect(
      playerSettleGrace(isLive: true, trackSwitch: false),
      lessThan(threshold),
    );
    expect(
      playerSettleGrace(isLive: true, trackSwitch: true),
      lessThan(threshold),
    );
  });

  test('a seek is given less room to settle than a track swap', () {
    // A seek out of the buffered range can hang outright, and the re-resolve
    // this grace defers is what recovers it. A track swap only ever refills.
    expect(
      playerSettleGrace(isLive: false, trackSwitch: false),
      lessThan(playerSettleGrace(isLive: false, trackSwitch: true)),
    );
  });

  testWidgets('skip intro seeks to the provider segment end', (tester) async {
    const episode = EpisodeItemV2(
      ref: MediaRef(
        extensionId: 'test',
        providerId: 'test.provider',
        id: 'episode-1',
      ),
      title: 'Episode',
      subtitle: 'Series',
      episode: EpisodeIdentity(
        parentRef: MediaRef(
          extensionId: 'test',
          providerId: 'test.provider',
          id: 'series-1',
        ),
        groupId: 'season:1',
        position: 1,
      ),
    );
    final controller = _RecoveryController(
      const AppPlayerValue(
        initialized: true,
        isPlaying: true,
        position: Duration(seconds: 50),
      ),
    );

    await tester.pumpWidget(
      _controls(
        controller,
        media: const PlaybackMedia(episode),
        playbackSegments: const [
          PlaybackSegment(
            type: PlaybackSegmentType.intro,
            startMs: 42000,
            endMs: 128500,
          ),
        ],
      ),
    );

    expect(find.text('Skip intro'), findsOneWidget);
    await tester.tap(find.text('Skip intro'));
    expect(controller.lastSeek, const Duration(milliseconds: 128500));
  });

  testWidgets('skip intro stays hidden until the player is initialized', (
    tester,
  ) async {
    const episode = EpisodeItemV2(
      ref: MediaRef(
        extensionId: 'test',
        providerId: 'test.provider',
        id: 'episode-1',
      ),
      title: 'Episode',
      episode: EpisodeIdentity(
        parentRef: MediaRef(
          extensionId: 'test',
          providerId: 'test.provider',
          id: 'series-1',
        ),
        groupId: 'season:1',
        position: 1,
      ),
    );
    final controller = _RecoveryController();
    const segments = [
      PlaybackSegment(
        type: PlaybackSegmentType.intro,
        startMs: 42000,
        endMs: 128500,
      ),
    ];

    await tester.pumpWidget(
      _controls(
        controller,
        media: const PlaybackMedia(episode),
        playbackSegments: segments,
      ),
    );
    expect(find.text('Skip intro'), findsNothing);

    controller.update(const AppPlayerValue(initialized: true));
    await tester.pump();
    await tester.pump();
    expect(find.text('Skip intro'), findsNothing);

    controller.update(
      const AppPlayerValue(
        initialized: true,
        isPlaying: true,
        position: Duration(seconds: 50),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Skip intro'), findsOneWidget);
  });

  testWidgets('an intro already skipped is not offered again', (tester) async {
    const episode = EpisodeItemV2(
      ref: MediaRef(
        extensionId: 'test',
        providerId: 'test.provider',
        id: 'episode-1',
      ),
      title: 'Episode',
      subtitle: 'Series',
      episode: EpisodeIdentity(
        parentRef: MediaRef(
          extensionId: 'test',
          providerId: 'test.provider',
          id: 'series-1',
        ),
        groupId: 'season:1',
        position: 1,
      ),
    );
    final controller = _RecoveryController(
      const AppPlayerValue(
        initialized: true,
        isPlaying: true,
        position: Duration(seconds: 50),
      ),
    );

    await tester.pumpWidget(
      _controls(
        controller,
        media: const PlaybackMedia(episode),
        playbackSegments: const [
          PlaybackSegment(
            type: PlaybackSegmentType.intro,
            startMs: 42000,
            endMs: 128500,
          ),
        ],
      ),
    );

    await tester.tap(find.text('Skip intro'));
    expect(controller.lastSeek, const Duration(milliseconds: 128500));

    // A jump out of the buffered range lands on the demuxer's own keyframe,
    // and a cut playlist starts at the segment boundary before it — either
    // leaves playback inside the intro that was just skipped.
    controller.update(
      const AppPlayerValue(
        initialized: true,
        isPlaying: true,
        position: Duration(seconds: 125),
      ),
    );
    // The value lands in a post-frame callback, so the rebuild it asks for
    // happens on the frame after this one.
    await tester.pump();
    await tester.pump();
    expect(find.text('Skip intro'), findsNothing);

    // Rewinding to before the intro drops that memory again, so a viewer
    // who scrubs back is offered the skip once more — left uncovered here
    // because driving three consecutive values through this widget's
    // post-frame update needs more of the harness than the behaviour is
    // worth.
  });

  testWidgets('skip intro appears in the right-side overlay at its marker', (
    tester,
  ) async {
    const episode = EpisodeItemV2(
      ref: MediaRef(
        extensionId: 'test',
        providerId: 'test.provider',
        id: 'episode-1',
      ),
      title: 'Episode',
      episode: EpisodeIdentity(
        parentRef: MediaRef(
          extensionId: 'test',
          providerId: 'test.provider',
          id: 'series-1',
        ),
        groupId: 'season:1',
        position: 1,
      ),
    );
    final visibility = <bool>[];
    final controller = _RecoveryController(
      const AppPlayerValue(
        initialized: true,
        isPlaying: true,
        position: Duration.zero,
        duration: Duration(minutes: 10),
      ),
    );

    await tester.pumpWidget(
      _controls(
        controller,
        media: const PlaybackMedia(episode),
        playbackSegments: const [
          PlaybackSegment(
            type: PlaybackSegmentType.intro,
            startMs: 420000,
            endMs: 480000,
          ),
        ],
        onVisibilityChanged: visibility.add,
      ),
    );
    await tester.tapAt(const Offset(20, 300));
    expect(visibility, contains(false));

    controller.update(
      const AppPlayerValue(
        initialized: true,
        isPlaying: true,
        position: Duration(minutes: 7),
        duration: Duration(minutes: 10),
      ),
    );
    await tester.pump();
    expect(find.text('Skip intro'), findsOneWidget);
    expect(tester.getCenter(find.text('Skip intro')).dx, greaterThan(400));
  });

  testWidgets('repeated buffering resumes when playback is still intended', (
    tester,
  ) async {
    final controller = _RecoveryController();
    await tester.pumpWidget(_controls(controller));

    controller.update(
      const AppPlayerValue(initialized: true, isBuffering: true),
    );
    await tester.pump();
    controller.update(
      const AppPlayerValue(initialized: true, isBuffering: false),
    );
    await tester.pump();

    expect(controller.playCalls, 1);

    controller.update(
      const AppPlayerValue(initialized: true, isBuffering: true),
    );
    await tester.pump();
    controller.update(
      const AppPlayerValue(initialized: true, isBuffering: false),
    );
    await tester.pump();

    expect(controller.playCalls, 2);
  });

  testWidgets('buffering does not resume after the user pauses', (
    tester,
  ) async {
    final controller = _RecoveryController(
      const AppPlayerValue(
        initialized: true,
        isPlaying: true,
        isBuffering: false,
      ),
    );
    await tester.pumpWidget(_controls(controller));

    await tester.tap(find.byIcon(Icons.pause_circle_filled_rounded));
    expect(controller.pauseCalls, 1);

    controller.update(
      const AppPlayerValue(initialized: true, isBuffering: true),
    );
    await tester.pump();
    controller.update(
      const AppPlayerValue(initialized: true, isBuffering: false),
    );
    await tester.pump();

    expect(controller.playCalls, 0);
  });
}

Widget _controls(
  _RecoveryController controller, {
  PlaybackMedia? media,
  EpisodeGuide? episodeGuide,
  List<PlaybackSegment> playbackSegments = const [],
  VoidCallback? onNearEnd,
  ValueChanged<PlayerEpisodeEntry>? onPlayEpisode,
  void Function(bool visibility)? onVisibilityChanged,
  void Function(Duration grace)? onSettling,
}) => wrapApp(
  registry: ExtensionRegistry([]),
  child: PlayerPlaybackControls(
    controller: controller,
    onVisibilityChanged: onVisibilityChanged ?? (_) {},
    media:
        media ??
        const PlaybackMedia(
          VideoItemV2(
            ref: MediaRef(
              extensionId: 'test',
              providerId: 'test.provider',
              id: 'movie-1',
            ),
            title: 'Movie',
          ),
        ),
    resolvedSources: const [
      ResolvedSource(
        source: StreamSource(id: 'source-1', label: 'Source 1'),
        stream: PlayableStream(
          url: 'https://stream.example/movie.m3u8',
          format: StreamFormat.hls,
        ),
      ),
    ],
    currentIndex: 0,
    onChangeSource: () {},
    onBack: () {},
    isLive: false,
    episodeGuide: episodeGuide,
    playbackSegments: playbackSegments,
    onPlayEpisode: onPlayEpisode ?? (_) {},
    onNearEnd: onNearEnd ?? () {},
    onPlayNext: () {},
    onPauseUpNext: () {},
    onCancelUpNext: () {},
    onSettling: onSettling ?? (_) {},
  ),
);

class _RecoveryController implements AppPlayerController {
  _RecoveryController([AppPlayerValue value = const AppPlayerValue()])
    : _value = ValueNotifier(value);

  final ValueNotifier<AppPlayerValue> _value;
  final StreamController<AppPlayerEvent> _events = StreamController.broadcast();
  int playCalls = 0;
  int pauseCalls = 0;
  Duration? lastSeek;

  void update(AppPlayerValue value) => _value.value = value;

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
  Future<void> seekTo(Duration position) async => lastSeek = position;
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
}
