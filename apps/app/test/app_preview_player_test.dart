import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_app/player/models/app_player_controller.dart';
import 'package:fvcksubs_app/player/widgets/app_preview_player.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';

import 'support/harness.dart';

const _directSource = DirectPreviewSource(
  id: 'direct:1',
  stream: PlayableStream(url: 'https://cdn.example.com/preview.mp4'),
);

const _youtubeSource = EmbeddedPreviewSource(
  id: 'yt:abc',
  provider: 'youtube',
  mediaId: 'abc',
);

const _vimeoSource = EmbeddedPreviewSource(
  id: 'vimeo:1',
  provider: 'vimeo',
  mediaId: '1',
);

Future<PlayableStream> _neverCalledResolver(String videoId) {
  fail('youtubeResolver should not have been called for "$videoId"');
}

void main() {
  testWidgets('a direct source renders immediately, no network call', (
    tester,
  ) async {
    final previewPlayer = RecordingPreviewPlayer();

    await tester.pumpWidget(
      wrapApp(
        child: const AppPreviewPlayer(
          source: _directSource,
          muted: true,
          playing: true,
          youtubeResolver: _neverCalledResolver,
        ),
        registry: ExtensionRegistry([]),
        previewPlayer: previewPlayer,
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('fake-preview-player')), findsOneWidget);
    expect(previewPlayer.played, _directSource.stream);
    expect(previewPlayer.playedMuted, isTrue);
    expect(previewPlayer.playedLooping, isTrue);
    expect(previewPlayer.playedPlaying, isTrue);
  });

  testWidgets('an embedded YouTube source resolves, then renders', (
    tester,
  ) async {
    final previewPlayer = RecordingPreviewPlayer();
    const resolved = PlayableStream(url: 'https://cdn.example.com/resolved.m3u8');

    await tester.pumpWidget(
      wrapApp(
        child: AppPreviewPlayer(
          source: _youtubeSource,
          muted: true,
          playing: true,
          youtubeResolver: (videoId) async {
            expect(videoId, 'abc');
            return resolved;
          },
        ),
        registry: ExtensionRegistry([]),
        previewPlayer: previewPlayer,
      ),
    );
    // The fake resolver completes on a microtask with no real delay, so the
    // "still unresolved" frame isn't reliably observable here — what matters
    // is that it does resolve and render once its future completes.
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('fake-preview-player')), findsOneWidget);
    expect(previewPlayer.played, resolved);
  });

  testWidgets('mute and playing are forwarded reactively on rebuild', (
    tester,
  ) async {
    final previewPlayer = RecordingPreviewPlayer();

    Future<void> pumpWith({required bool muted, required bool playing}) =>
        tester.pumpWidget(
          wrapApp(
            child: AppPreviewPlayer(
              source: _directSource,
              muted: muted,
              playing: playing,
              youtubeResolver: _neverCalledResolver,
            ),
            registry: ExtensionRegistry([]),
            previewPlayer: previewPlayer,
          ),
        );

    await pumpWith(muted: true, playing: true);
    await tester.pump();
    expect(previewPlayer.playedMuted, isTrue);
    expect(previewPlayer.playedPlaying, isTrue);

    await pumpWith(muted: false, playing: false);
    await tester.pump();
    expect(previewPlayer.playedMuted, isFalse);
    expect(previewPlayer.playedPlaying, isFalse);
  });

  testWidgets(
    'a fit change on the same source reaches the live controller, not just '
    'the next build',
    (tester) async {
      final previewPlayer = RecordingPreviewPlayer();

      Future<void> pumpWith(BoxFit fit) => tester.pumpWidget(
        wrapApp(
          child: AppPreviewPlayer(
            source: _directSource,
            muted: true,
            playing: true,
            fit: fit,
            youtubeResolver: _neverCalledResolver,
          ),
          registry: ExtensionRegistry([]),
          previewPlayer: previewPlayer,
        ),
      );

      await pumpWith(BoxFit.contain);
      await tester.pump();
      // The real native player widgets only read `fit` once, at
      // construction — a same-source update has to reach the *live*
      // controller's own setFit, the same mechanism the main player's fit
      // button already uses, not just flow through as a rebuilt prop.
      expect(previewPlayer.controller!.lastFit, isNull);

      await pumpWith(BoxFit.cover);
      await tester.pump();
      expect(previewPlayer.controller!.lastFit, PlayerFitMode.cover);

      await pumpWith(BoxFit.contain);
      await tester.pump();
      expect(previewPlayer.controller!.lastFit, PlayerFitMode.contain);
    },
  );

  testWidgets('an unsupported embed provider calls onError, no network call', (
    tester,
  ) async {
    Object? reportedError;

    await tester.pumpWidget(
      wrapApp(
        child: AppPreviewPlayer(
          source: _vimeoSource,
          muted: true,
          playing: true,
          youtubeResolver: _neverCalledResolver,
          onError: (error) => reportedError = error,
        ),
        registry: ExtensionRegistry([]),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('fake-preview-player')), findsNothing);
    expect(reportedError, isA<UnsupportedError>());
  });

  testWidgets('a YouTube resolution failure calls onError', (tester) async {
    Object? reportedError;

    await tester.pumpWidget(
      wrapApp(
        child: AppPreviewPlayer(
          source: _youtubeSource,
          muted: true,
          playing: true,
          youtubeResolver: (_) async => throw StateError('no stream'),
          onError: (error) => reportedError = error,
        ),
        registry: ExtensionRegistry([]),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(reportedError, isA<StateError>());
  });

  testWidgets('a native-controller error event reaches onError', (
    tester,
  ) async {
    final previewPlayer = RecordingPreviewPlayer();
    Object? reportedError;

    await tester.pumpWidget(
      wrapApp(
        child: AppPreviewPlayer(
          source: _directSource,
          muted: true,
          playing: true,
          youtubeResolver: _neverCalledResolver,
          onError: (error) => reportedError = error,
        ),
        registry: ExtensionRegistry([]),
        previewPlayer: previewPlayer,
      ),
    );
    await tester.pump();

    previewPlayer.emitError(StateError('native failure'));
    await tester.pump();

    expect(reportedError, isA<StateError>());
  });

  testWidgets('disposal cancels the controller event subscription', (
    tester,
  ) async {
    final previewPlayer = RecordingPreviewPlayer();

    await tester.pumpWidget(
      wrapApp(
        child: const AppPreviewPlayer(
          source: _directSource,
          muted: true,
          playing: true,
          youtubeResolver: _neverCalledResolver,
        ),
        registry: ExtensionRegistry([]),
        previewPlayer: previewPlayer,
      ),
    );
    await tester.pump();
    expect(previewPlayer.controller!.hasListener, isTrue);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();

    expect(previewPlayer.controller!.hasListener, isFalse);
  });
}
