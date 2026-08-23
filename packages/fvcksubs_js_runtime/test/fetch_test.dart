import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'package:fvcksubs_js_runtime/fvcksubs_js_runtime.dart';

void main() {
  // One server plays both "the allowed host" and "the disallowed host" —
  // reached through two different host strings that both physically route
  // to it (`127.0.0.1` vs `localhost`). The allowlist matches on the
  // string, not the resolved address, so this still exercises the real
  // security property: a redirect/initial URL using the `localhost` form
  // must be rejected even though it's the exact same reachable server.
  late HttpServer server;
  var blockedHitCount = 0;
  late JsEngine engine;

  String urlFor(String host, String path) =>
      'http://$host:${server.port}$path';

  setUp(() async {
    blockedHitCount = 0;

    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      switch (request.uri.path) {
        case '/ok':
          request.response
            ..headers.set('x-test', 'hello')
            ..statusCode = 200
            ..write('hi there');
          await request.response.close();
        case '/redirect-ok':
          request.response
            ..statusCode = 302
            ..headers.set('location', '/ok');
          await request.response.close();
        case '/redirect-blocked':
          request.response
            ..statusCode = 302
            ..headers.set('location', urlFor('localhost', '/blocked'));
          await request.response.close();
        case '/blocked':
          blockedHitCount++;
          request.response.statusCode = 200;
          await request.response.close();
        case '/never-responds':
          break; // deliberately never closes the response
        default:
          request.response.statusCode = 404;
          await request.response.close();
      }
    });

    engine = JsEngine(
      allowedHosts: {InternetAddress.loopbackIPv4.address},
      fetchTimeout: const Duration(milliseconds: 300),
    );
  });

  tearDown(() async {
    engine.dispose();
    await server.close(force: true);
  });

  test('a successful GET resolves with status, headers, and body', () async {
    final result = await engine.evalAsync('''
      (async () => {
        const r = await fetch(${jsonEncode(urlFor('127.0.0.1', '/ok'))});
        return { status: r.status, body: r.body, header: r.headers['x-test'] };
      })()
    ''');
    final decoded = jsonDecode(result) as Map;
    expect(decoded['status'], 200);
    expect(decoded['body'], 'hi there');
    expect(decoded['header'], 'hello');
  });

  test('a .then() chain (no top-level await) also runs to completion', () async {
    final result = await engine.evalAsync(
      'fetch(${jsonEncode(urlFor('127.0.0.1', '/ok'))}).then(r => r.status)',
    );
    expect(result, '200');
  });

  test('a redirect within the allowlist is followed', () async {
    final result = await engine.evalAsync('''
      (async () => {
        const r = await fetch(${jsonEncode(urlFor('127.0.0.1', '/redirect-ok'))});
        return { status: r.status, url: r.url, body: r.body };
      })()
    ''');
    final decoded = jsonDecode(result) as Map;
    expect(decoded['status'], 200);
    expect(decoded['body'], 'hi there');
    expect(decoded['url'], contains('/ok'));
  });

  test(
    'a redirect to a disallowed host is rejected, and never reaches it',
    () async {
      await expectLater(
        engine.evalAsync(
          'await fetch(${jsonEncode(urlFor('127.0.0.1', '/redirect-blocked'))})',
        ),
        throwsA(isA<JsEvalException>()),
      );
      expect(blockedHitCount, 0);
    },
  );

  test(
    'an initially disallowed host is rejected without any request',
    () async {
      await expectLater(
        engine.evalAsync(
          'await fetch(${jsonEncode(urlFor('localhost', '/blocked'))})',
        ),
        throwsA(isA<JsEvalException>()),
      );
      expect(blockedHitCount, 0);
    },
  );

  test('a fetch that never responds rejects on timeout, not a hang', () async {
    await expectLater(
      engine.evalAsync(
        'await fetch(${jsonEncode(urlFor('127.0.0.1', '/never-responds'))})',
      ),
      throwsA(isA<JsEvalException>()),
    );
  });

  test('no allowlist (the default) permits any host', () async {
    final open = JsEngine();
    try {
      final result = await open.evalAsync(
        'fetch(${jsonEncode(urlFor('localhost', '/blocked'))})'
        '.then(r => r.status)',
      );
      expect(result, '200');
    } finally {
      open.dispose();
    }
  });

  test('a bare "*" entry permits a host no pattern names', () async {
    final open = JsEngine(allowedHosts: const {'*'});
    try {
      final result = await open.evalAsync(
        'fetch(${jsonEncode(urlFor('localhost', '/blocked'))})'
        '.then(r => r.status)',
      );
      expect(result, '200');
    } finally {
      open.dispose();
    }
  });

  test('a bare "*" also permits a redirect hop to another host', () async {
    final open = JsEngine(allowedHosts: const {'*'});
    try {
      final result = await open.evalAsync(
        'fetch(${jsonEncode(urlFor('127.0.0.1', '/redirect-blocked'))})'
        '.then(r => r.status)',
      );
      expect(result, '200');
      expect(blockedHitCount, 1);
    } finally {
      open.dispose();
    }
  });

  test('"*" as a label, not the whole entry, still matches one label', () async {
    final open = JsEngine(allowedHosts: const {'*.0.0.1'});
    try {
      await expectLater(
        open.evalAsync(
          'await fetch(${jsonEncode(urlFor('localhost', '/blocked'))})',
        ),
        throwsA(isA<JsEvalException>()),
      );
      expect(blockedHitCount, 0);
    } finally {
      open.dispose();
    }
  });
}
