@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';
import 'package:test/test.dart';

/// One engine, several role calls in flight.
///
/// A `JsEngine` runs one script at a time; `FvckExtension.sources` already
/// fans out across providers with `Future.wait`, and Home loads its shelves
/// concurrently. So "two calls at once" is not a hypothetical — an extension
/// that throws on it is unusable for anything beyond a single catalog.
void main() {
  late HttpServer server;
  late String baseUrl;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    baseUrl = 'http://${server.address.address}:${server.port}';
    server.listen((request) async {
      // Slow enough that a second call starts before the first finishes.
      await Future<void>.delayed(const Duration(milliseconds: 120));
      request.response
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'path': request.uri.path}));
      await request.response.close();
    });
  });

  tearDown(() => server.close(force: true));

  Manifest manifestFor(List<String> hosts) => Manifest.parse({
    'apiVersion': 2,
    'id': 'concurrent',
    'name': 'concurrent',
    'version': '1.0.0',
    'runtime': 'js',
    'categories': ['live'],
    'providers': [
      {
        'id': 'concurrent.p',
        'roles': ['catalog'],
        'catalogs': [
          {
            'id': 'c',
            'name': 'C',
            'category': 'live',
            'kind': 'event',
          },
        ],
      },
    ],
    'permissions': {'hosts': hosts},
  });

  /// A bundle whose catalog does one real (slow) fetch and echoes the
  /// catalogId back as an item id, so results can be told apart.
  String bundle() =>
      '''
globalThis.__extension = {
  async catalog(query) {
    const r = await fetch(${jsonEncode(baseUrl)} + "/" + query.catalogId);
    return { sections: [{ id: "main", items: [{
        ref: { extensionId: "concurrent", providerId: "concurrent.p", id: query.catalogId },
        kind: "event",
        schedule: {startsAt: "2026-01-01T00:00:00Z"},
        title: JSON.parse(r.body).path,
      }] }] };
  },
};
''';

  test('two overlapping role calls both complete, and do not cross', () async {
    final extension = JsExtension.load(
      manifest: manifestFor([server.address.address]),
      source: bundle(),
    );
    try {
      final pages = await Future.wait([
        extension.catalog(
          const CatalogQuery(providerId: 'concurrent.p', catalogId: 'first'),
        ),
        extension.catalog(
          const CatalogQuery(providerId: 'concurrent.p', catalogId: 'second'),
        ),
      ]);

      // Each call gets its own answer — not one shared, not one lost.
      expect(pages[0].items.single.ref.id, 'first');
      expect(pages[0].items.single.title, '/first');
      expect(pages[1].items.single.ref.id, 'second');
      expect(pages[1].items.single.title, '/second');
    } finally {
      extension.dispose();
    }
  });

  test('a queue of calls all complete in order', () async {
    final extension = JsExtension.load(
      manifest: manifestFor([server.address.address]),
      source: bundle(),
    );
    try {
      final pages = await Future.wait([
        for (var i = 0; i < 4; i++)
          extension.catalog(
            CatalogQuery(providerId: 'concurrent.p', catalogId: 'q$i'),
          ),
      ]);

      expect(pages.map((p) => p.items.single.ref.id), [
        'q0',
        'q1',
        'q2',
        'q3',
      ]);
    } finally {
      extension.dispose();
    }
  });

  test('a failure in one call does not wedge the next', () async {
    final extension = JsExtension.load(
      manifest: manifestFor([server.address.address]),
      source:
          '''
globalThis.__extension = {
  async catalog(query) {
    if (query.catalogId === "boom") throw new Error("nope");
    const r = await fetch(${jsonEncode(baseUrl)} + "/" + query.catalogId);
    return { sections: [{ id: "main", items: [] }] };
  },
};
''',
    );
    try {
      await expectLater(
        extension.catalog(
          const CatalogQuery(providerId: 'concurrent.p', catalogId: 'boom'),
        ),
        throwsA(isA<JsExtensionException>()),
      );
      // The engine must still be usable — a rejected call that left the
      // queue blocked would hang everything after it.
      await expectLater(
        extension.catalog(
          const CatalogQuery(providerId: 'concurrent.p', catalogId: 'ok'),
        ),
        completes,
      );
    } finally {
      extension.dispose();
    }
  });
}
