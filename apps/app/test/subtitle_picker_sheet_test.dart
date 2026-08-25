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

  testWidgets('an empty refetch preserves remembered external subtitles', (
    tester,
  ) async {
    const external = SubtitleTrack(
      language: 'id',
      label: 'Indonesia (Segu)',
      url: 'https://subtitles.example/id.vtt',
    );
    List<SubtitleTrack>? persisted;

    await tester.pumpWidget(
      wrapApp(
        registry: ExtensionRegistry([_ExternalSubtitleExtension(const [])]),
        child: Scaffold(
          body: PlayerSubtitlePickerSheet(
            media: const PlaybackMedia(
              VideoItemV2(
                ref: MediaRef(
                  extensionId: 'external',
                  providerId: 'external.p',
                  id: 'movie-1',
                ),
                title: 'Movie',
              ),
            ),
            tracks: const [],
            current: external,
            filterTracks: (tracks) => tracks,
            initialExternalTracks: const [external],
            onExternalTracksFetched: (tracks) => persisted = tracks,
          ),
        ),
      ),
    );

    await tester.tap(find.text('Fetch external subtitles'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Indonesia'), findsOneWidget);
    expect(persisted, [external]);
  });
}

class _ExternalSubtitleExtension extends ContentExtension {
  _ExternalSubtitleExtension(this.result)
    : _manifest = Manifest.parse({
        'apiVersion': 2,
        'id': 'external',
        'name': 'external',
        'version': '1.0.0',
        'runtime': 'builtin',
        'categories': ['movie'],
        'providers': [
          {
            'id': 'external.p',
            'roles': ['subtitles'],
          },
        ],
        'permissions': {'hosts': <String>[]},
      });

  final List<SubtitleTrack> result;
  final Manifest _manifest;

  @override
  Manifest get manifest => _manifest;

  @override
  Future<List<SubtitleTrack>> externalSubtitles(MediaItemV2 item) async =>
      result;
}
