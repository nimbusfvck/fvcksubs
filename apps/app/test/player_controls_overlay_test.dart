import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_app/player/controls/player_controls_overlay.dart';
import 'package:fvcksubs_app/player/models/app_player_controller.dart';
import 'package:fvcksubs_app/player/sheets/player_selection_sheets.dart';

void main() {
  testWidgets(
    'live controls hide VOD seeking controls and keep source switching',
    (tester) async {
      var sourceChanges = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlayerControlsOverlayView(
              title: 'Live match',
              favoriteAction: const SizedBox(),
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

      await tester.tap(find.text('Source A'));
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
            favoriteAction: const SizedBox(),
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

  testWidgets('on-demand timeline keeps its slider width across an hour', (
    tester,
  ) async {
    Widget overlay(Duration position) => MaterialApp(
      home: Scaffold(
        body: PlayerControlsOverlayView(
          title: 'Movie',
          favoriteAction: const SizedBox(),
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
    expect(find.text('Audio 2'), findsOneWidget);
    expect(find.text('id'), findsOneWidget);

    await tester.tap(find.text('Audio 2'));
    expect(find.byIcon(Icons.check), findsOneWidget);
  });
}
