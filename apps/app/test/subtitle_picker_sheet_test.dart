import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_app/player/models/playback_media.dart';
import 'package:fvcksubs_app/player/sheets/subtitle_picker_sheet.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';

import 'support/harness.dart';

void main() {
  testWidgets('reopens with the remembered external subtitle visible', (
    tester,
  ) async {
    const external = SubtitleTrack(
      language: 'id',
      label: 'Indonesia (Shegu)',
      url: 'https://subtitles.example/id.vtt',
    );

    await tester.pumpWidget(
      wrapApp(
        registry: ExtensionRegistry([]),
        child: Scaffold(
          body: PlayerSubtitlePickerSheet(
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
            tracks: const [],
            current: external,
            filterTracks: (tracks) => tracks,
            initialExternalTracks: const [external],
          ),
        ),
      ),
    );

    expect(find.textContaining('Indonesia'), findsOneWidget);
    expect(find.text('Fetch external subtitles'), findsOneWidget);
  });
}
