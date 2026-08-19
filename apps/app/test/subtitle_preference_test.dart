import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_app/player/play_item.dart';
import 'package:fvcksubs_app/player/player_page.dart';
import 'package:fvcksubs_app/player/subtitle_preference_controller.dart';
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';

import 'support/harness.dart';

/// Preferring a subtitle language decides which source plays, because
/// subtitles come with the source rather than the title.
void main() {
  Widget playButton(MediaItem item) => Builder(
    builder: (context) => ElevatedButton(
      onPressed: () => playItem(context, item),
      child: const Text('play'),
    ),
  );

  /// An extension whose sources each resolve to their own subtitle set.
  ExtensionRegistry withSubtitles(Map<String, List<String>> bySourceId) =>
      ExtensionRegistry([
        SubtitleFakeExtension(subtitlesBySourceId: bySourceId),
      ]);

  testWidgets('a source carrying the preferred language plays first', (
    tester,
  ) async {
    final registry = withSubtitles({
      // Resolved first, but English-only.
      'a': ['en'],
      'b': ['id', 'en'],
    });

    await tester.pumpWidget(
      wrapApp(
        child: playButton(fakeItem(extensionId: 'subs')),
        registry: registry,
        subtitlePreferenceController: SubtitlePreferenceController(
          store: FakeSubtitlePreferenceStore(),
          initial: 'id',
        ),
      ),
    );
    await tester.tap(find.text('play'));
    await tester.pumpAndSettle();

    final player = tester.widget<PlayerPage>(find.byType(PlayerPage));
    expect(player.resolvedSources.first.source.id, 'b');
  });

  testWidgets('the others are still offered, just not first', (tester) async {
    // Dropping them would leave a viewer unable to watch anything their
    // preference happens not to cover.
    final registry = withSubtitles({
      'a': ['en'],
      'b': ['id'],
    });

    await tester.pumpWidget(
      wrapApp(
        child: playButton(fakeItem(extensionId: 'subs')),
        registry: registry,
        subtitlePreferenceController: SubtitlePreferenceController(
          store: FakeSubtitlePreferenceStore(),
          initial: 'id',
        ),
      ),
    );
    await tester.tap(find.text('play'));
    await tester.pumpAndSettle();

    final player = tester.widget<PlayerPage>(find.byType(PlayerPage));
    expect(player.resolvedSources.map((s) => s.source.id), ['b', 'a']);
  });

  testWidgets('no preference leaves the order alone', (tester) async {
    final registry = withSubtitles({
      'a': ['en'],
      'b': ['id'],
    });

    await tester.pumpWidget(
      wrapApp(
        child: playButton(fakeItem(extensionId: 'subs')),
        registry: registry,
      ),
    );
    await tester.tap(find.text('play'));
    await tester.pumpAndSettle();

    final player = tester.widget<PlayerPage>(find.byType(PlayerPage));
    expect(player.resolvedSources.map((s) => s.source.id), ['a', 'b']);
  });

  testWidgets('a region variant satisfies the preference', (tester) async {
    // "id-ID" is Indonesian as far as being able to read it goes.
    final registry = withSubtitles({
      'a': ['en'],
      'b': ['id-ID'],
    });

    await tester.pumpWidget(
      wrapApp(
        child: playButton(fakeItem(extensionId: 'subs')),
        registry: registry,
        subtitlePreferenceController: SubtitlePreferenceController(
          store: FakeSubtitlePreferenceStore(),
          initial: 'id',
        ),
      ),
    );
    await tester.tap(find.text('play'));
    await tester.pumpAndSettle();

    final player = tester.widget<PlayerPage>(find.byType(PlayerPage));
    expect(player.resolvedSources.first.source.id, 'b');
  });

  testWidgets('nothing matching keeps every source, in order', (tester) async {
    final registry = withSubtitles({
      'a': ['en'],
      'b': ['fr'],
    });

    await tester.pumpWidget(
      wrapApp(
        child: playButton(fakeItem(extensionId: 'subs')),
        registry: registry,
        subtitlePreferenceController: SubtitlePreferenceController(
          store: FakeSubtitlePreferenceStore(),
          initial: 'id',
        ),
      ),
    );
    await tester.tap(find.text('play'));
    await tester.pumpAndSettle();

    final player = tester.widget<PlayerPage>(find.byType(PlayerPage));
    expect(player.resolvedSources.map((s) => s.source.id), ['a', 'b']);
  });

  testWidgets(
    'the preference also reaches the player, to pre-select a subtitle track',
    (tester) async {
      final registry = withSubtitles({
        'a': ['en', 'id'],
      });
      final player = RecordingPlayer();

      await tester.pumpWidget(
        wrapApp(
          child: playButton(fakeItem(extensionId: 'subs')),
          registry: registry,
          player: player,
          subtitlePreferenceController: SubtitlePreferenceController(
            store: FakeSubtitlePreferenceStore(),
            initial: 'id',
          ),
        ),
      );
      await tester.tap(find.text('play'));
      await tester.pumpAndSettle();

      expect(player.playedPreferredSubtitleLanguage, 'id');
    },
  );

  testWidgets('no preference passes nothing through to the player', (
    tester,
  ) async {
    final registry = withSubtitles({
      'a': ['en'],
    });
    final player = RecordingPlayer();

    await tester.pumpWidget(
      wrapApp(
        child: playButton(fakeItem(extensionId: 'subs')),
        registry: registry,
        player: player,
      ),
    );
    await tester.tap(find.text('play'));
    await tester.pumpAndSettle();

    expect(player.playedPreferredSubtitleLanguage, isNull);
  });

  group('the preference itself', () {
    test('is remembered', () async {
      final store = FakeSubtitlePreferenceStore();
      SubtitlePreferenceController(store: store).select('id');
      expect(store.saved, 'id');
    });

    test('can be cleared back to no preference', () async {
      final store = FakeSubtitlePreferenceStore(initial: 'id');
      final controller = SubtitlePreferenceController(
        store: store,
        initial: 'id',
      )..select(null);

      expect(controller.languageCode, isNull);
      expect(store.saved, isNull);
    });
  });
}
