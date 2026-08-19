import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_app/addons/installer_controller.dart';
import 'package:fvcksubs_app/addons/permission_dialog.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';

void main() {
  ExtensionRepoEntry entry({
    List<String> hosts = const [],
    String? description,
    String? author,
  }) => ExtensionRepoEntry(
    id: 'remote_ext',
    name: 'Remote Extension',
    version: '2.0.0',
    manifestUrl: 'https://x/manifest.json',
    bundleUrl: 'https://x/bundle.js',
    bundleSha256: 'abc',
    hosts: hosts,
    description: description,
    author: author,
  );

  /// Pumps the dialog and returns whatever it resolved to.
  Future<bool?> show(WidgetTester tester, PermissionRequest request) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async =>
                result = await showPermissionDialog(context, request),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('a fresh install lists what the extension will reach', (
    tester,
  ) async {
    await show(
      tester,
      PermissionRequest(
        entry: entry(hosts: ['cdn.example', 'api.example']),
        newHosts: const ['cdn.example', 'api.example'],
        alreadyGrantedHosts: const [],
        isUpdate: false,
      ),
    );

    expect(find.text('Install Remote Extension?'), findsOneWidget);
    expect(find.textContaining('will be able to reach'), findsOneWidget);
    expect(find.text('• cdn.example'), findsOneWidget);
    expect(find.text('• api.example'), findsOneWidget);
  });

  testWidgets('an extension wanting nothing says so plainly', (tester) async {
    await show(
      tester,
      PermissionRequest(
        entry: entry(),
        newHosts: const [],
        alreadyGrantedHosts: const [],
        isUpdate: false,
      ),
    );

    expect(find.textContaining('requests no network access'), findsOneWidget);
  });

  testWidgets('an update separates the new hosts from the granted ones', (
    tester,
  ) async {
    await show(
      tester,
      PermissionRequest(
        entry: entry(hosts: ['cdn.example', 'tracker.example']),
        newHosts: const ['tracker.example'],
        alreadyGrantedHosts: const ['cdn.example'],
        isUpdate: true,
      ),
    );

    expect(find.text('Update Remote Extension?'), findsOneWidget);
    expect(find.textContaining('wants access to new sites'), findsOneWidget);
    // The new host is what needs attention; the old one is shown separately
    // under "Already allowed" rather than mixed in with it.
    expect(find.text('• tracker.example'), findsOneWidget);
    expect(find.text('Already allowed:'), findsOneWidget);
  });

  testWidgets('Install resolves true, Cancel resolves false', (tester) async {
    final request = PermissionRequest(
      entry: entry(hosts: ['cdn.example']),
      newHosts: const ['cdn.example'],
      alreadyGrantedHosts: const [],
      isUpdate: false,
    );

    bool? accepted;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async =>
                accepted = await showPermissionDialog(context, request),
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(accepted, isFalse);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Install'));
    await tester.pumpAndSettle();
    expect(accepted, isTrue);
  });

  testWidgets('dismissing without choosing counts as a refusal', (
    tester,
  ) async {
    bool? accepted;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async => accepted = await showPermissionDialog(
              context,
              PermissionRequest(
                entry: entry(hosts: ['cdn.example']),
                newHosts: const ['cdn.example'],
                alreadyGrantedHosts: const [],
                isUpdate: false,
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    // Tap the barrier, i.e. outside the dialog.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(
      accepted,
      isFalse,
      reason: 'an unanswered permission prompt must never mean yes',
    );
  });

  testWidgets('shows description and author so the choice is informed', (
    tester,
  ) async {
    await show(
      tester,
      PermissionRequest(
        entry: entry(
          hosts: ['cdn.example'],
          description: 'Football fixtures and streams.',
          author: 'Someone',
        ),
        newHosts: const ['cdn.example'],
        alreadyGrantedHosts: const [],
        isUpdate: false,
      ),
    );

    expect(find.text('Football fixtures and streams.'), findsOneWidget);
    expect(find.textContaining('by Someone'), findsOneWidget);
  });

  testWidgets('an entry with no description still renders', (tester) async {
    await show(
      tester,
      PermissionRequest(
        entry: entry(hosts: ['cdn.example']),
        newHosts: const ['cdn.example'],
        alreadyGrantedHosts: const [],
        isUpdate: false,
      ),
    );

    expect(find.text('Install Remote Extension?'), findsOneWidget);
    expect(find.textContaining('by '), findsNothing);
  });

  testWidgets('a long host list scrolls without overflowing', (tester) async {
    tester.view.physicalSize = const Size(390, 620);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final hosts = List.generate(30, (index) => 'host-$index.example');
    await show(
      tester,
      PermissionRequest(
        entry: entry(hosts: hosts, description: 'A long permission request.'),
        newHosts: hosts,
        alreadyGrantedHosts: const [],
        isUpdate: false,
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(SingleChildScrollView), findsWidgets);
    expect(find.text('• host-0.example'), findsOneWidget);
  });
}
