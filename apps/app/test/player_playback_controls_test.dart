import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_app/player/controls/player_playback_controls.dart';
import 'package:fvcksubs_app/player/models/app_player_controller.dart';
import 'package:fvcksubs_app/player/models/playback_media.dart';
import 'package:fvcksubs_app/player/models/resolved_source.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';

import 'support/harness.dart';

void main() {
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

Widget _controls(_RecoveryController controller) => wrapApp(
  registry: ExtensionRegistry([]),
  child: PlayerPlaybackControls(
    controller: controller,
    onVisibilityChanged: (_) {},
    media: const PlaybackMedia(
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
    onNearEnd: () {},
    onPlayNext: () {},
    onPauseUpNext: () {},
    onCancelUpNext: () {},
  ),
);

class _RecoveryController implements AppPlayerController {
  _RecoveryController([AppPlayerValue value = const AppPlayerValue()])
    : _value = ValueNotifier(value);

  final ValueNotifier<AppPlayerValue> _value;
  final StreamController<AppPlayerEvent> _events = StreamController.broadcast();
  int playCalls = 0;
  int pauseCalls = 0;

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
  Future<void> seekTo(Duration position) async {}
  @override
  Future<void> setSubtitle(SubtitleTrack? track) async {}
  @override
  Future<void> setQuality(AppQualityTrack? track) async {}
  @override
  Future<void> setAudioTrack(AppAudioTrack track) async {}
  @override
  Future<void> toggleFullScreen() async {}
  @override
  Future<void> exitFullScreen() async {}
}
