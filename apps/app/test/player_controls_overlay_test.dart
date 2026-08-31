import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_app/player/controls/player_controls_overlay.dart';
import 'package:fvcksubs_app/player/models/app_player_controller.dart';
import 'package:fvcksubs_app/player/sheets/player_selection_sheets.dart';

void main() {
  testWidgets('series overlay shows series title and episode context', (
    tester,
  ) async {
    await tester.pumpWidget(
      _overlay(title: 'Example Series', subtitle: 'Season 2 · Episode 3'),
    );

    expect(find.text('Example Series'), findsOneWidget);
    expect(find.text('Season 2 · Episode 3'), findsOneWidget);
  });

  testWidgets(
    'live controls hide VOD seeking controls and keep source switching',
    (tester) async {
      var sourceChanges = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlayerControlsOverlayView(
              title: 'Live match',
              controlsVisible: true,
              isLive: true,
              isPlaying: true,
              isBuffering: false,
              sourceLabel: 'Source A',
              activeSubtitleLabel: null,
              activeQualityLabel: null,
              position: const Duration(seconds: 40),
              duration: const Duration(minutes: 1),
              timelineExtent: const Duration(minutes: 1),
              bufferedExtent: const Duration(seconds: 50),
              atLiveEdge: false,
              dragValueMs: null,
              onBackgroundTap: () {},
              onBack: () {},
              onSkip: (_) {},
              onTogglePlayPause: () {},
              onChangeSource: () => sourceChanges++,
              onPlayNext: null,
              onOpenSubtitlePicker: () {},
              onOpenQualityPicker: () {},
              onTimelineChangeStart: (_) {},
              onTimelineChanged: (_) {},
              onTimelineChangeEnd: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('LIVE'), findsOneWidget);
      expect(find.byIcon(Icons.replay_10_rounded), findsNothing);
      expect(find.byIcon(Icons.forward_10_rounded), findsNothing);
      expect(find.byIcon(Icons.closed_caption_off_rounded), findsNothing);
      expect(find.byIcon(Icons.fullscreen_rounded), findsNothing);
      expect(find.byIcon(Icons.favorite_border), findsNothing);
      expect(find.byIcon(Icons.favorite), findsNothing);

      await tester.tap(find.byTooltip('Source A'));
      expect(sourceChanges, 1);
    },
  );

  testWidgets('on-demand controls forward skip intent', (tester) async {
    final skips = <int>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlayerControlsOverlayView(
            title: 'Movie',
            controlsVisible: true,
            isLive: false,
            isPlaying: false,
            isBuffering: false,
            sourceLabel: null,
            activeSubtitleLabel: null,
            activeQualityLabel: null,
            position: const Duration(seconds: 30),
            duration: const Duration(minutes: 2),
            timelineExtent: const Duration(minutes: 2),
            bufferedExtent: const Duration(seconds: 45),
            atLiveEdge: true,
            dragValueMs: null,
            onBackgroundTap: () {},
            onBack: () {},
            onSkip: skips.add,
            onTogglePlayPause: () {},
            onChangeSource: () {},
            onPlayNext: null,
            onOpenSubtitlePicker: () {},
            onOpenQualityPicker: () {},
            onTimelineChangeStart: (_) {},
            onTimelineChanged: (_) {},
            onTimelineChangeEnd: (_) {},
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.replay_10_rounded));
    await tester.tap(find.byIcon(Icons.forward_10_rounded));

    expect(skips, [-10, 10]);
    expect(find.byIcon(Icons.closed_caption_off_rounded), findsOneWidget);
  });

  testWidgets('on-demand timeline shows the dragged position', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlayerControlsOverlayView(
            title: 'Movie',
            controlsVisible: true,
            isLive: false,
            isPlaying: true,
            isBuffering: false,
            sourceLabel: null,
            activeSubtitleLabel: null,
            activeQualityLabel: null,
            position: const Duration(seconds: 30),
            duration: const Duration(minutes: 2),
            timelineExtent: const Duration(minutes: 2),
            bufferedExtent: const Duration(seconds: 45),
            atLiveEdge: true,
            dragValueMs: const Duration(seconds: 75).inMilliseconds.toDouble(),
            onBackgroundTap: () {},
            onBack: () {},
            onSkip: (_) {},
            onTogglePlayPause: () {},
            onChangeSource: () {},
            onPlayNext: null,
            onOpenSubtitlePicker: () {},
            onOpenQualityPicker: () {},
            onTimelineChangeStart: (_) {},
            onTimelineChanged: (_) {},
            onTimelineChangeEnd: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('01:15'), findsOneWidget);
    expect(find.text('02:00'), findsOneWidget);
  });

  testWidgets('on-demand timeline keeps its slider width across an hour', (
    tester,
  ) async {
    Widget overlay(Duration position) => MaterialApp(
      home: Scaffold(
        body: PlayerControlsOverlayView(
          title: 'Movie',
          controlsVisible: true,
          isLive: false,
          isPlaying: true,
          isBuffering: false,
          sourceLabel: null,
          activeSubtitleLabel: null,
          activeQualityLabel: null,
          position: position,
          duration: const Duration(hours: 2),
          timelineExtent: const Duration(hours: 2),
          bufferedExtent: const Duration(hours: 2),
          atLiveEdge: true,
          dragValueMs: null,
          onBackgroundTap: () {},
          onBack: () {},
          onSkip: (_) {},
          onTogglePlayPause: () {},
          onChangeSource: () {},
          onPlayNext: null,
          onOpenSubtitlePicker: () {},
          onOpenQualityPicker: () {},
          onTimelineChangeStart: (_) {},
          onTimelineChanged: (_) {},
          onTimelineChangeEnd: (_) {},
        ),
      ),
    );

    await tester.pumpWidget(overlay(const Duration(minutes: 59, seconds: 59)));
    final initialSliderWidth = tester.getSize(find.byType(Slider)).width;
    final initialLabelWidth = tester
        .getSize(find.byKey(const Key('player-position-label')))
        .width;

    await tester.pumpWidget(overlay(const Duration(hours: 1)));

    expect(tester.getSize(find.byType(Slider)).width, initialSliderWidth);
    expect(
      tester.getSize(find.byKey(const Key('player-position-label'))).width,
      initialLabelWidth,
    );
  });

  testWidgets('audio picker labels unnamed tracks and marks the active track', (
    tester,
  ) async {
    final tracks = [
      const AppAudioTrack(id: '1', label: 'English', language: 'en'),
      const AppAudioTrack(id: '2', label: 'Audio', language: 'id'),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlayerAudioPickerSheet(tracks: tracks, current: tracks.first),
        ),
      ),
    );

    expect(find.text('English'), findsOneWidget);
    expect(find.text('Indonesia'), findsOneWidget);
    expect(find.text('id'), findsOneWidget);

    await tester.tap(find.text('Indonesia'));
    expect(find.byIcon(Icons.check), findsOneWidget);
  });

  testWidgets('Auto names the rendition it settled on', (tester) async {
    const tracks = [
      AppQualityTrack(id: '1', height: 1080, bitrate: 4000000),
      AppQualityTrack(id: '2', height: 720, bitrate: 1500000),
    ];

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PlayerQualityPickerSheet(
            tracks: tracks,
            current: null,
            activeHeight: 720,
          ),
        ),
      ),
    );

    // Auto is what the viewer chose, and the tick stays on it — but it no
    // longer leaves them guessing what they are watching.
    expect(find.text('Auto (720p)'), findsOneWidget);
    expect(
      tester
          .widget<ListTile>(
            find.ancestor(
              of: find.text('Auto (720p)'),
              matching: find.byType(ListTile),
            ),
          )
          .trailing,
      isA<Icon>(),
    );
  });

  testWidgets('Auto stays plain until a rendition is known', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PlayerQualityPickerSheet(tracks: [], current: null),
        ),
      ),
    );

    expect(find.text('Auto'), findsOneWidget);
  });

  test('the playing track is found by the backend id, not by identity', () {
    // Both backends rebuild their track list — and every track object in it —
    // whenever the tracks change, so a freshly built list must still resolve
    // the track the backend says it is playing.
    List<AppAudioTrack> rebuild() => [
      const AppAudioTrack(id: 'en', label: 'English', nativeId: '1'),
      const AppAudioTrack(id: 'id', label: 'Indonesia', nativeId: '2'),
    ];

    expect(audioTrackByNativeId(rebuild(), '2')?.id, 'id');
    expect(audioTrackByNativeId(rebuild(), null), isNull);
    expect(audioTrackByNativeId(rebuild(), '9'), isNull);
  });

  test('tracks a source names identically are still told apart', () {
    // What a provider like FlyStream hands over: every rendition carries the
    // same title and language, so the picker's own labels collide.
    const tracks = [
      AppAudioTrack(
        id: 'id',
        label: 'Audio',
        language: 'id',
        details: 'AAC · stereo',
        nativeId: '1',
      ),
      AppAudioTrack(
        id: 'id-1',
        label: 'Audio',
        language: 'id',
        details: 'EAC3 · 5.1',
        nativeId: '2',
      ),
      AppAudioTrack(
        id: 'id-2',
        label: 'Audio',
        language: 'id',
        nativeId: '3',
      ),
      AppAudioTrack(
        id: 'id-3',
        label: 'Audio',
        language: 'id',
        nativeId: '4',
      ),
    ];

    final labels = audioTrackPickerLabels(tracks);

    expect(labels.toSet(), hasLength(labels.length));
    // A real difference the viewer can hear names the track.
    expect(labels[0], 'Indonesia · AAC · stereo');
    expect(labels[1], 'Indonesia · EAC3 · 5.1');
    // Tracks the backend describes identically fall back to their position.
    expect(labels[2], 'Indonesia 1');
    expect(labels[3], 'Indonesia 2');
  });

  test('a track named on its own keeps its plain label', () {
    const tracks = [
      AppAudioTrack(id: 'en', label: 'English', language: 'en', nativeId: '1'),
      AppAudioTrack(
        id: 'id',
        label: 'Indonesia',
        language: 'id',
        details: 'AAC · stereo',
        nativeId: '2',
      ),
    ];

    expect(audioTrackPickerLabels(tracks), ['English', 'Indonesia']);
  });

  test('unnamed audio tracks receive distinct ids and picker labels', () {
    const first = AppAudioTrack(id: 'audio', label: 'Audio');
    const second = AppAudioTrack(id: 'audio', label: 'Audio');

    expect(uniqueAudioTrackId(base: 'audio', occurrence: 0, index: 0), 'audio');
    expect(
      uniqueAudioTrackId(base: 'audio', occurrence: 1, index: 1),
      'audio-1',
    );
    expect(audioTrackPickerLabel(first, 0), 'Audio 1');
    expect(audioTrackPickerLabel(second, 1), 'Audio 2');
  });
}

Widget _overlay({required String title, String? subtitle}) => MaterialApp(
  home: Scaffold(
    body: PlayerControlsOverlayView(
      title: title,
      subtitle: subtitle,
      controlsVisible: true,
      isLive: false,
      isPlaying: true,
      isBuffering: false,
      sourceLabel: null,
      activeSubtitleLabel: null,
      activeQualityLabel: null,
      position: Duration.zero,
      duration: const Duration(minutes: 1),
      timelineExtent: const Duration(minutes: 1),
      bufferedExtent: Duration.zero,
      atLiveEdge: false,
      dragValueMs: null,
      onBackgroundTap: () {},
      onBack: () {},
      onSkip: (_) {},
      onTogglePlayPause: () {},
      onChangeSource: () {},
      onPlayNext: null,
      onOpenSubtitlePicker: () {},
      onOpenQualityPicker: () {},
      onTimelineChangeStart: (_) {},
      onTimelineChanged: (_) {},
      onTimelineChangeEnd: (_) {},
    ),
  ),
);
