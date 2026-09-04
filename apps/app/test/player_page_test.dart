import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_app/player/player_page.dart';
import 'package:fvcksubs_app/player/models/app_player_controller.dart';
import 'package:fvcksubs_app/player/state/quality_preference_controller.dart';
import 'package:fvcksubs_app/player/state/subtitle_preference_controller.dart';
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
    final player = _PositionRecordingPlayer();
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

    controller.add(later);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Server 3'));
    await tester.pumpAndSettle();
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
    await tester.pumpAndSettle();
    expect(find.text('Bein Sport 1'), findsOneWidget);
    await controller.close();
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
      preferredExternalSubtitle: preferredExternalSubtitle,
      subtitleAppearance: subtitleAppearance,
      key: key,
    );
    if (controllers.isEmpty) {
      final controller = _FakePlayerController();
      controllers.add(controller);
      onControllerCreated?.call(controller);
    }
    return widget;
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
    onPlaybackReady?.call(controller);
    return widget;
  }
}

class _FakePlayerController implements AppPlayerController {
  _FakePlayerController({AppPlayerValue initialValue = const AppPlayerValue()})
    : _value = ValueNotifier(initialValue);

  final ValueNotifier<AppPlayerValue> _value;
  final StreamController<AppPlayerEvent> _events =
      StreamController<AppPlayerEvent>.broadcast(sync: true);
  Duration? lastSeekPosition;

  void emitError(Object error) {
    _events.add(AppPlayerEvent(AppPlayerEventType.error, error: error));
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
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> seekTo(Duration position) async => lastSeekPosition = position;

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
