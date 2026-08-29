import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_app/library/library_controller.dart';
import 'package:fvcksubs_app/player/player_page.dart';
import 'package:fvcksubs_app/shorts/shorts_page.dart';
import 'package:fvcksubs_app/shorts/widgets/shorts_feed_card.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';
import 'package:fvcksubs_storage/fvcksubs_storage.dart';

import 'support/harness.dart';

VideoItemV2 _item(String id, {String? title}) => VideoItemV2(
  ref: MediaRef(extensionId: 'a', providerId: 'a.p', id: id),
  title: title ?? id,
);

const _directSourceResponse = PreviewResponse(
  sources: [
    DirectPreviewSource(id: 'd1', stream: PlayableStream(url: 'https://cdn.example.com/1.mp4')),
  ],
);

FakeExtension _extension({
  required List<MediaItemV2> items,
  Map<String, PreviewResponse> previewFor = const {},
  List<StreamSource> sourceList = const [],
  PlayableStream? resolved,
}) => FakeExtension(
  id: 'a',
  catalogs: [
    FakeCatalog(id: 'previews', name: 'Previews', categories: const [], items: items, surface: CatalogSurface.preview),
  ],
  previewFor: previewFor,
  sourceList: sourceList,
  resolved: resolved,
);

void main() {
  testWidgets('loading, then the feed renders once items arrive', (tester) async {
    final registry = ExtensionRegistry([
      _extension(items: [_item('one'), _item('two')], previewFor: {'one': _directSourceResponse, 'two': _directSourceResponse}),
    ]);

    await tester.pumpWidget(wrapApp(child: const ShortsPage(), registry: registry));
    await tester.pump();
    await tester.pump();

    expect(find.text('one'), findsOneWidget);
  });

  testWidgets('an empty feed shows the empty message', (tester) async {
    final registry = ExtensionRegistry([FakeExtension(id: 'a')]);

    await tester.pumpWidget(wrapApp(child: const ShortsPage(), registry: registry));
    await tester.pumpAndSettle();

    expect(find.text('No previews are available right now.'), findsOneWidget);
  });

  testWidgets('vertical paging advances to the next item', (tester) async {
    final registry = ExtensionRegistry([
      _extension(
        items: [_item('one'), _item('two')],
        previewFor: {'one': _directSourceResponse, 'two': _directSourceResponse},
      ),
    ]);

    await tester.pumpWidget(wrapApp(child: const ShortsPage(), registry: registry));
    await tester.pump();
    await tester.pump();
    expect(find.text('one'), findsOneWidget);

    await tester.drag(find.byType(PageView), const Offset(0, -600));
    await tester.pumpAndSettle();

    expect(find.text('two'), findsOneWidget);
    expect(find.text('one'), findsNothing);
  });

  testWidgets('an item with no supported preview is skipped automatically', (
    tester,
  ) async {
    final registry = ExtensionRegistry([
      _extension(
        items: [_item('unusable'), _item('usable')],
        previewFor: {
          'unusable': const PreviewResponse(
            sources: [EmbeddedPreviewSource(id: '1', provider: 'vimeo', mediaId: 'v1')],
          ),
          'usable': _directSourceResponse,
        },
      ),
    ]);

    await tester.pumpWidget(wrapApp(child: const ShortsPage(), registry: registry));
    // Enough pumps for load(), the initial ensurePreviewResolved(0), the
    // unusable result, and the post-frame-scheduled page-advance animation.
    await tester.pump();
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('usable'), findsOneWidget);
  });

  testWidgets('sound starts muted and a tap unmutes, persisting across a page change', (
    tester,
  ) async {
    final previewPlayer = RecordingPreviewPlayer();
    final registry = ExtensionRegistry([
      _extension(
        items: [_item('one'), _item('two')],
        previewFor: {'one': _directSourceResponse, 'two': _directSourceResponse},
      ),
    ]);

    await tester.pumpWidget(
      wrapApp(child: const ShortsPage(), registry: registry, previewPlayer: previewPlayer),
    );
    await tester.pump();
    await tester.pump();

    expect(previewPlayer.playedMuted, isTrue);

    await tester.tap(find.byTooltip('Unmute'));
    await tester.pump();
    expect(previewPlayer.playedMuted, isFalse);

    await tester.drag(find.byType(PageView), const Offset(0, -600));
    await tester.pumpAndSettle();

    expect(previewPlayer.playedMuted, isFalse);
  });

  testWidgets('a tap away from the buttons toggles pause, then play', (
    tester,
  ) async {
    final previewPlayer = RecordingPreviewPlayer();
    final registry = ExtensionRegistry([
      _extension(items: [_item('one')], previewFor: {'one': _directSourceResponse}),
    ]);

    await tester.pumpWidget(
      wrapApp(child: const ShortsPage(), registry: registry, previewPlayer: previewPlayer),
    );
    await tester.pump();
    await tester.pump();
    expect(previewPlayer.playedPlaying, isTrue);

    // Near the top of the card, well clear of the bottom-anchored rail/text.
    final cardTopLeft = tester.getTopLeft(find.byType(ShortsFeedCard));
    await tester.tapAt(cardTopLeft + const Offset(50, 50));
    await tester.pump(const Duration(milliseconds: 50));
    expect(previewPlayer.playedPlaying, isFalse);

    await tester.tapAt(cardTopLeft + const Offset(50, 50));
    await tester.pump(const Duration(milliseconds: 50));
    expect(previewPlayer.playedPlaying, isTrue);
  });

  testWidgets('holding pauses and releasing resumes automatically', (
    tester,
  ) async {
    final previewPlayer = RecordingPreviewPlayer();
    final registry = ExtensionRegistry([
      _extension(items: [_item('one')], previewFor: {'one': _directSourceResponse}),
    ]);

    await tester.pumpWidget(
      wrapApp(child: const ShortsPage(), registry: registry, previewPlayer: previewPlayer),
    );
    await tester.pump();
    await tester.pump();
    expect(previewPlayer.playedPlaying, isTrue);

    final cardTopLeft = tester.getTopLeft(find.byType(ShortsFeedCard));
    final gesture = await tester.startGesture(cardTopLeft + const Offset(50, 50));
    await tester.pump(const Duration(milliseconds: 600)); // past the long-press threshold
    expect(previewPlayer.playedPlaying, isFalse);

    await gesture.up();
    await tester.pump();
    expect(previewPlayer.playedPlaying, isTrue);
  });

  testWidgets('the fit button toggles between letterboxed and full-screen', (
    tester,
  ) async {
    final previewPlayer = RecordingPreviewPlayer();
    final registry = ExtensionRegistry([
      _extension(items: [_item('one')], previewFor: {'one': _directSourceResponse}),
    ]);

    await tester.pumpWidget(
      wrapApp(child: const ShortsPage(), registry: registry, previewPlayer: previewPlayer),
    );
    await tester.pump();
    await tester.pump();

    expect(previewPlayer.playedFit, BoxFit.contain);
    // The tooltip names what tapping switches *to*.
    expect(find.byTooltip('Fit screen'), findsOneWidget);

    await tester.tap(find.byTooltip('Fit screen'));
    await tester.pump();
    expect(previewPlayer.playedFit, BoxFit.cover);
    expect(find.byTooltip('Fit ratio'), findsOneWidget);

    await tester.tap(find.byTooltip('Fit ratio'));
    await tester.pump();
    expect(previewPlayer.playedFit, BoxFit.contain);
  });

  testWidgets('Watch on an available video hands off to full playback', (
    tester,
  ) async {
    final registry = ExtensionRegistry([
      _extension(
        items: [_item('one')],
        previewFor: {'one': _directSourceResponse},
        sourceList: const [StreamSource(id: 's1', label: 'HD')],
        resolved: const PlayableStream(url: 'https://cdn.example.com/full.m3u8'),
      ),
    ]);

    await tester.pumpWidget(wrapApp(child: const ShortsPage(), registry: registry));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byTooltip('Watch'));
    // playItemV2 races source resolution against a 1s external-subtitle
    // grace period (play_item.dart's _externalSubtitleGrace) before it
    // opens the player — flush past it explicitly rather than relying on
    // pumpAndSettle to catch a real Future.delayed this long.
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.byType(PlayerPage), findsOneWidget);
  });

  testWidgets('Favorite toggles through the shared LibraryController', (
    tester,
  ) async {
    final registry = ExtensionRegistry([
      _extension(items: [_item('one')], previewFor: {'one': _directSourceResponse}),
    ]);
    final library = LibraryController(store: _MemoryLibraryStore());

    await tester.pumpWidget(
      wrapApp(child: const ShortsPage(), registry: registry, libraryController: library),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byTooltip('Add to favorites'));
    await tester.pumpAndSettle();

    expect(library.isFavorite(_item('one').ref), isTrue);
    expect(find.byTooltip('In favorites'), findsOneWidget);
  });
}

class _MemoryLibraryStore implements LibraryStore {
  @override
  Future<Map<String, UserMediaState>> load() async => {};

  @override
  Future<void> save(Map<String, UserMediaState> records) async {}
}
