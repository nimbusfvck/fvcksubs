import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_app/player/models/resolved_source.dart';
import 'package:fvcksubs_app/player/sheets/player_selection_sheets.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';

ResolvedSource _source(String id, String label, String provider) =>
    ResolvedSource(
      source: StreamSource(
        id: id,
        label: label,
        provider: provider,
        providerId: 'nimora.${provider.toLowerCase()}',
      ),
      stream: PlayableStream(
        url: 'https://stream.example/$id.m3u8',
        format: StreamFormat.hls,
      ),
    );

Future<void> _showSheet(
  WidgetTester tester, {
  required List<ResolvedSource> sources,
  String? title,
  Future<List<ResolvedSource>> Function()? onRefresh,
  ValueListenable<bool>? backgroundSourceLoading,
  ValueListenable<List<ResolvedSource>>? resolvedSourcesListenable,
}) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: PlayerSourcePickerSheet(
        resolvedSources: sources,
        current: sources.first,
        title: title,
        onRefresh: onRefresh,
        backgroundSourceLoading: backgroundSourceLoading,
        resolvedSourcesListenable: resolvedSourcesListenable,
      ),
    ),
  ),
);

void main() {
  final cricfy = _source('c1', 'Server 4', 'Cricfy');
  final kora = _source('k1', 'Bein Sport 1', 'Kora');

  test(
    'refresh replaces a token-changing source instead of duplicating it',
    () {
      final refreshed = _source('c2', 'Server 4', 'Cricfy');

      final merged = mergeResolvedSources([cricfy], [refreshed]);

      expect(merged, hasLength(1));
      expect(merged.single.source.id, 'c2');
    },
  );

  test('Febbox label migration does not duplicate the same source', () {
    const oldSource = StreamSource(
      id: 'nimora.showbox:stable-file-share',
      label: 'Febbox ⚡ · Auto · 2.2 GB',
      provider: 'Nimora',
      providerId: 'nimora.showbox',
    );
    const refreshedSource = StreamSource(
      id: 'nimora.showbox:stable-file-share',
      label: 'Febbox ⚡',
      provider: 'Nimora',
      providerId: 'nimora.showbox',
    );
    const oldResolved = ResolvedSource(
      source: oldSource,
      stream: PlayableStream(
        url: 'https://stream.example/old.m3u8',
        format: StreamFormat.hls,
      ),
    );
    const refreshedResolved = ResolvedSource(
      source: refreshedSource,
      stream: PlayableStream(
        url: 'https://stream.example/refreshed.m3u8',
        format: StreamFormat.hls,
      ),
    );

    final merged = mergeResolvedSources([oldResolved], [refreshedResolved]);

    expect(merged, hasLength(1));
    expect(merged.single.source.label, 'Febbox ⚡');
    expect(merged.single.stream.url, 'https://stream.example/refreshed.m3u8');
  });

  test('refresh keeps the source currently playing stable', () {
    final refreshed = _source('c2', 'Server 4', 'Cricfy');

    final merged = mergeResolvedSources(
      [cricfy],
      [refreshed],
      preserveSourceId: 'c1',
    );

    expect(merged, hasLength(1));
    expect(merged.single.source.id, 'c1');
  });

  test(
    'full refresh removes stale quality entries from a refreshed provider',
    () {
      final febboxAuto = _source('auto-new', 'Febbox Auto', 'Febbox');
      final febbox1080 = _source('1080-old', 'Febbox 1080p', 'Febbox');
      final febbox720 = _source('720-old', 'Febbox 720p', 'Febbox');

      final merged = mergeResolvedSources(
        [febbox1080, febbox720, kora],
        [febboxAuto],
        refreshedDescriptors: [febboxAuto.source],
      );

      expect(merged.map((source) => source.source.id), ['k1', 'auto-new']);
    },
  );

  test('full refresh retains a stale descriptor only while it is playing', () {
    final febboxAuto = _source('auto-new', 'Febbox Auto', 'Febbox');
    final febbox1080 = _source('1080-old', 'Febbox 1080p', 'Febbox');

    final merged = mergeResolvedSources(
      [febbox1080, kora],
      [febboxAuto],
      preserveSourceId: '1080-old',
      refreshedDescriptors: [febboxAuto.source],
    );

    expect(merged.map((source) => source.source.id), [
      '1080-old',
      'k1',
      'auto-new',
    ]);
  });

  testWidgets('the refresh control is hidden when no handler is given', (
    tester,
  ) async {
    await _showSheet(tester, sources: [cricfy], title: 'Source · Home vs Away');
    expect(find.byIcon(Icons.refresh), findsNothing);
    expect(find.text('Source · Home vs Away'), findsOneWidget);
  });

  testWidgets('refreshing adds the sources discovery missed the first time', (
    tester,
  ) async {
    await _showSheet(
      tester,
      sources: [cricfy],
      onRefresh: () async => [cricfy, kora],
    );

    expect(find.text('Bein Sport 1'), findsNothing);
    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pumpAndSettle();

    expect(find.text('Bein Sport 1'), findsNothing);
    expect(find.text('Kora'), findsOneWidget, reason: 'grouped by provider');
    expect(find.text('Cricfy'), findsOneWidget, reason: 'nothing is lost');
  });

  testWidgets('background discovery shows progress instead of refresh', (
    tester,
  ) async {
    final loading = ValueNotifier<bool>(true);
    addTearDown(loading.dispose);
    await _showSheet(
      tester,
      sources: [cricfy],
      onRefresh: () async => [cricfy, kora],
      backgroundSourceLoading: loading,
    );

    expect(find.byIcon(Icons.refresh), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    loading.value = false;
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byIcon(Icons.refresh), findsOneWidget);
  });

  testWidgets('sources arriving while the sheet is open appear immediately', (
    tester,
  ) async {
    final sources = ValueNotifier<List<ResolvedSource>>([cricfy]);
    addTearDown(sources.dispose);
    await _showSheet(
      tester,
      sources: [cricfy],
      resolvedSourcesListenable: sources,
    );

    expect(find.text('Kora'), findsNothing);
    sources.value = [cricfy, kora];
    await tester.pump();

    expect(find.text('Kora'), findsOneWidget);
  });

  testWidgets('provider variants are expanded like subtitle variants', (
    tester,
  ) async {
    final second = _source('c2', 'Server 5', 'Cricfy');
    await _showSheet(tester, sources: [cricfy, second]);

    expect(find.text('Cricfy (2)'), findsOneWidget);
    expect(find.text('Server 4'), findsNothing);

    await tester.tap(find.text('Cricfy (2)'));
    await tester.pump();

    expect(find.text('Server 4'), findsOneWidget);
    expect(find.text('Server 5'), findsOneWidget);
  });

  // A second fan-out would compete with the resolves feeding playback on the
  // extension's single event loop rather than finish any sooner.
  testWidgets('tapping repeatedly while in flight sends one request', (
    tester,
  ) async {
    var calls = 0;
    final gate = Completer<List<ResolvedSource>>();
    await _showSheet(
      tester,
      sources: [cricfy],
      onRefresh: () {
        calls++;
        return gate.future;
      },
    );

    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pump();

    // The control is replaced by progress, so there is nothing left to tap.
    expect(find.byIcon(Icons.refresh), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    gate.complete([cricfy, kora]);
    await tester.pumpAndSettle();

    expect(calls, 1);
    expect(find.byIcon(Icons.refresh), findsOneWidget, reason: 'usable again');
    expect(find.text('Bein Sport 1'), findsNothing);
    expect(find.text('Kora'), findsOneWidget);
  });

  testWidgets('a refresh that finds nothing new leaves the list alone', (
    tester,
  ) async {
    await _showSheet(
      tester,
      sources: [cricfy],
      onRefresh: () async => [cricfy],
    );

    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pumpAndSettle();

    expect(find.text('Cricfy'), findsOneWidget);
    expect(find.byIcon(Icons.refresh), findsOneWidget);
  });

  testWidgets('a failing refresh keeps the sheet alive and usable', (
    tester,
  ) async {
    await _showSheet(
      tester,
      sources: [cricfy],
      onRefresh: () async => throw StateError('discovery failed'),
    );

    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pumpAndSettle();

    expect(
      tester.takeException(),
      isNull,
      reason: 'a failed refresh must not escape into the framework',
    );
    expect(find.byIcon(Icons.refresh), findsOneWidget);
    expect(find.text('Cricfy'), findsOneWidget);
  });
}
