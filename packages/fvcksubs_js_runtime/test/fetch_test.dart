import 'dart:async';
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
        case '/slow':
          await Future<void>.delayed(const Duration(milliseconds: 700));
          request.response
            ..statusCode = 200
            ..write('worth the wait');
          await request.response.close();
        case '/echo-headers':
          request.response
            ..statusCode = 200
            ..write(
              jsonEncode({
                for (final name in _receivedHeaderNames(request)) name: true,
              }),
            );
          await request.response.close();
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

  test('a fetch that settles after dispose is dropped, not delivered', () async {
    final doomed = JsEngine(
      allowedHosts: {InternetAddress.loopbackIPv4.address},
      fetchTimeout: const Duration(seconds: 5),
    );
    // Deliberately not awaited: the engine goes away while it is in flight,
    // which is what an extension replaced by an update does to its own.
    unawaited(
      doomed
          .evalAsync('await fetch(${jsonEncode(urlFor('127.0.0.1', '/slow'))})')
          .catchError((Object _) => ''),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    doomed.dispose();

    // Long enough for the response to arrive at a disposed engine.
    await Future<void>.delayed(const Duration(milliseconds: 900));
  });

  group('per-request timeoutMs', () {
    test('lets one call wait past the engine-wide fetch timeout', () async {
      final url = jsonEncode(urlFor('127.0.0.1', '/slow'));

      // Same URL, same engine: only the option differs.
      await expectLater(
        engine.evalAsync('await fetch($url)'),
        throwsA(isA<JsEvalException>()),
      );
      final result = await engine.evalAsync(
        'fetch($url, {timeoutMs: 5000}).then((r) => r.body)',
      );
      expect(jsonDecode(result), 'worth the wait');
    });

    test('cannot be raised past maxFetchTimeout', () async {
      final capped = JsEngine(
        fetchTimeout: const Duration(milliseconds: 300),
        maxFetchTimeout: const Duration(milliseconds: 400),
      );
      try {
        await expectLater(
          capped.evalAsync(
            'await fetch(${jsonEncode(urlFor('127.0.0.1', '/slow'))}, '
            '{timeoutMs: 5000})',
          ),
          throwsA(isA<JsEvalException>()),
        );
      } finally {
        capped.dispose();
      }
    });

    test('cannot be used to shorten a call below the engine default', () async {
      final result = await engine.evalAsync(
        'fetch(${jsonEncode(urlFor('127.0.0.1', '/ok'))}, {timeoutMs: 1})'
        '.then((r) => r.body)',
      );
      expect(jsonDecode(result), 'hi there');
    });

    test('never sends the option on to the server', () async {
      final result = await engine.evalAsync(
        'fetch(${jsonEncode(urlFor('127.0.0.1', '/echo-headers'))}, '
        '{timeoutMs: 5000, headers: {\'X-Keep\': \'yes\'}})'
        '.then((r) => r.body)',
      );
      final names = (jsonDecode(jsonDecode(result) as String) as Map).keys;
      expect(names, contains('x-keep'));
      expect(names, isNot(contains('x-qjsr-timeout-ms')));
    });
  });
}

Iterable<String> _receivedHeaderNames(HttpRequest request) {
  final names = <String>[];
  request.headers.forEach((name, _) => names.add(name.toLowerCase()));
  return names;
}
