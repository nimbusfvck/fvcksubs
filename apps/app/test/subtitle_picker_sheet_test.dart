import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_app/player/data/online_subtitle_service.dart';
import 'package:fvcksubs_app/player/data/subtitle_translate_service.dart';
import 'package:fvcksubs_app/player/models/playback_media.dart';
import 'package:fvcksubs_app/player/sheets/subtitle_picker_sheet.dart';
import 'package:fvcksubs_app/player/state/subtitle_preference_controller.dart';
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

  testWidgets('shows cached online results and checks the selected one', (
    tester,
  ) async {
    const result = OnlineSubtitleSearchResult(
      id: 'subtitle-1',
      name: 'Movie.2026',
      language: 'id',
      source: 'OpenSubtitles',
      provider: 'opensubtitles',
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
            current: null,
            filterTracks: (tracks) => tracks,
            initialOnlineResults: const [result],
            selectedOnlineResultKey: 'opensubtitles\u0000subtitle-1',
          ),
        ),
      ),
    );

    expect(find.text('Movie.2026'), findsOneWidget);
    final resultTile = find.ancestor(
      of: find.text('Movie.2026'),
      matching: find.byType(ListTile),
    );
    expect(
      find.descendant(of: resultTile, matching: find.byIcon(Icons.check)),
      findsOneWidget,
    );
  });

  testWidgets('offers translation when the preferred language is absent', (
    tester,
  ) async {
    final preference = SubtitlePreferenceController(
      store: FakeSubtitlePreferenceStore(),
      initial: 'id',
    );
    const english = SubtitleTrack(
      language: 'en',
      url: 'https://subs.example/en.srt',
      label: 'English Full',
    );
    const forced = SubtitleTrack(
      language: 'en',
      url: 'https://subs.example/en-forced.srt',
      label: 'English Forced',
    );

    await tester.pumpWidget(
      wrapApp(
        registry: ExtensionRegistry([]),
        subtitlePreferenceController: preference,
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
            translationSourceTracks: const [english, forced],
            current: null,
            filterTracks: (tracks) => tracks,
          ),
        ),
      ),
    );

    expect(find.textContaining('Translate'), findsOneWidget);
    await tester.tap(find.textContaining('Translate'));
    await tester.pump();
    expect(find.text('English Full'), findsOneWidget);
    expect(find.text('English Forced'), findsOneWidget);
  });

  testWidgets('does not offer translation when the preferred track exists', (
    tester,
  ) async {
    final preference = SubtitlePreferenceController(
      store: FakeSubtitlePreferenceStore(),
      initial: 'id',
    );
    const indonesian = SubtitleTrack(
      language: 'id',
      url: 'https://subs.example/id.srt',
    );
    const english = SubtitleTrack(
      language: 'en',
      url: 'https://subs.example/en.srt',
    );

    await tester.pumpWidget(
      wrapApp(
        registry: ExtensionRegistry([]),
        subtitlePreferenceController: preference,
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
            tracks: const [indonesian],
            translationSourceTracks: const [indonesian, english],
            current: indonesian,
            filterTracks: (tracks) => tracks,
          ),
        ),
      ),
    );

    expect(find.textContaining('Translate'), findsNothing);
  });

  testWidgets('shows a spinner while translating a selected subtitle', (
    tester,
  ) async {
    final preference = SubtitlePreferenceController(
      store: FakeSubtitlePreferenceStore(),
      initial: 'id',
    );
    final translation = Completer<SubtitleTrack>();
    final service = _BlockingSubtitleTranslateService(translation.future);
    const english = SubtitleTrack(
      language: 'en',
      url: 'https://subs.example/en.srt',
      label: 'English Full',
    );

    await tester.pumpWidget(
      wrapApp(
        registry: ExtensionRegistry([]),
        subtitlePreferenceController: preference,
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
            translationSourceTracks: const [english],
            current: null,
            filterTracks: (tracks) => tracks,
            subtitleTranslateService: service,
          ),
        ),
      ),
    );

    await tester.tap(find.textContaining('Translate'));
    await tester.pump();
    await tester.tap(find.text('English Full'));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    final sourceTile = tester.widget<ListTile>(
      find.ancestor(
        of: find.text('English Full'),
        matching: find.byType(ListTile),
      ),
    );
    expect(sourceTile.enabled, isFalse);

    translation.complete(
      const SubtitleTrack(
        language: 'id',
        url: '/tmp/translated.srt',
        label: 'Translated English Full',
      ),
    );
    await tester.pump();
  });

  testWidgets('checks the translated current subtitle when reopened', (
    tester,
  ) async {
    final preference = SubtitlePreferenceController(
      store: FakeSubtitlePreferenceStore(),
      initial: 'id',
    );
    const translated = SubtitleTrack(
      language: 'id',
      url: '/tmp/translated.srt',
      label: 'Translated English Full',
    );

    await tester.pumpWidget(
      wrapApp(
        registry: ExtensionRegistry([]),
        subtitlePreferenceController: preference,
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
            current: translated,
            filterTracks: (tracks) => tracks,
          ),
        ),
      ),
    );

    final translatedTile = find.ancestor(
      of: find.text('🇮🇩 Indonesia'),
      matching: find.byType(ListTile),
    );
    expect(translatedTile, findsOneWidget);
    expect(
      find.descendant(of: translatedTile, matching: find.byIcon(Icons.check)),
      findsOneWidget,
    );
  });
}

class _BlockingSubtitleTranslateService implements SubtitleTranslateService {
  _BlockingSubtitleTranslateService(this.translation);

  final Future<SubtitleTrack> translation;

  @override
  Future<String> translate(
    String content,
    String targetIso, {
    String? sourceIso,
    void Function(double)? onProgress,
  }) async => content;

  @override
  Future<SubtitleTrack> translateTrack(
    SubtitleTrack source, {
    required String targetIso,
  }) => translation;
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
