import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_app/player/widgets/trailer_preview.dart';
import 'package:fvcksubs_app/player/widgets/video_player_view.dart';
import 'package:fvcksubs_app/settings/preview_autoplay_preference_controller.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';

import 'support/harness.dart';

const _trailer = MediaTrailer(
  title: 'Trailer',
  url: 'https://video.example/trailer.mp4',
  mimeType: 'video/mp4',
);

void main() {
  testWidgets(
    'decorative preview starts after a delay and stops at its limit',
    (tester) async {
      await tester.pumpWidget(
        wrapApp(
          child: const TrailerPreview(trailer: _trailer),
          registry: ExtensionRegistry([]),
        ),
      );
      await tester.pump();

      VideoPlayerView preview() =>
          tester.widget<VideoPlayerView>(find.byType(VideoPlayerView));

      expect(preview().playing, isFalse);
      expect(preview().looping, isFalse);

      await tester.pump(const Duration(milliseconds: 999));
      expect(preview().playing, isFalse);
      await tester.pump(const Duration(milliseconds: 1));
      expect(preview().playing, isTrue);

      await tester.pump(const Duration(seconds: 20));
      expect(preview().playing, isFalse);
      await tester.pump(const Duration(milliseconds: 180));
      expect(
        tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
        0,
      );
    },
  );

  testWidgets('disabled autoplay never starts the decorative preview', (
    tester,
  ) async {
    final preference = PreviewAutoplayPreferenceController(
      store: FakePreviewAutoplayPreferenceStore(),
      initial: false,
    );

    await tester.pumpWidget(
      wrapApp(
        child: const TrailerPreview(trailer: _trailer),
        registry: ExtensionRegistry([]),
        previewAutoplayPreferenceController: preference,
      ),
    );
    await tester.pump(const Duration(seconds: 2));

    final preview = tester.widget<VideoPlayerView>(
      find.byType(VideoPlayerView),
    );
    expect(preview.playing, isFalse);
    expect(preview.looping, isFalse);
  });
}
