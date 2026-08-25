import 'dart:async';

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
  Future<List<ResolvedSource>> Function()? onRefresh,
}) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: PlayerSourcePickerSheet(
        resolvedSources: sources,
        current: sources.first,
        onRefresh: onRefresh,
      ),
    ),
  ),
);

void main() {
  final cricfy = _source('c1', 'Server 4', 'Cricfy');
  final kora = _source('k1', 'Bein Sport 1', 'Kora');

  testWidgets('the refresh control is hidden when no handler is given', (
    tester,
  ) async {
    await _showSheet(tester, sources: [cricfy]);
    expect(find.byIcon(Icons.refresh), findsNothing);
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

    expect(find.text('Bein Sport 1'), findsOneWidget);
    expect(find.text('Kora'), findsOneWidget, reason: 'grouped by provider');
    expect(find.text('Server 4'), findsOneWidget, reason: 'nothing is lost');
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
    expect(find.text('Bein Sport 1'), findsOneWidget);
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

    expect(find.text('Server 4'), findsOneWidget);
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
    expect(find.text('Server 4'), findsOneWidget);
  });
}
