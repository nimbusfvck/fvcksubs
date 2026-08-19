import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'package:fvcksubs_js_runtime/fvcksubs_js_runtime.dart';

/// PLAN.md §24's runtime-security list, minus the parts that don't exist
/// yet: infinite loop, memory exhaustion, stack exhaustion. (Blocked host
/// and blocked redirect live in `fetch_test.dart`; forged storage namespace
/// and invalid stream URL have nothing to test against yet.)
void main() {
  group('wall-clock budget', () {
    test('an infinite loop is interrupted, not left to hang', () {
      final engine = JsEngine(
        scriptTimeout: const Duration(milliseconds: 200),
      );
      try {
        expect(
          () => engine.eval('while (true) {}'),
          throwsA(isA<JsEvalException>()),
        );
      } finally {
        engine.dispose();
      }
    });

    test('the engine still works after interrupting a script', () {
      final engine = JsEngine(
        scriptTimeout: const Duration(milliseconds: 200),
      );
      try {
        expect(
          () => engine.eval('for (;;) {}'),
          throwsA(isA<JsEvalException>()),
        );
        // The expired deadline must not poison the next call.
        expect(engine.eval('1 + 1'), '2');
      } finally {
        engine.dispose();
      }
    });

    test('a script well under budget is untouched', () {
      final engine = JsEngine(
        scriptTimeout: const Duration(milliseconds: 500),
      );
      try {
        // Real work, but nowhere near the budget.
        expect(engine.eval('''
          let n = 0;
          for (let i = 0; i < 200000; i++) n += i;
          n
        '''), '19999900000');
      } finally {
        engine.dispose();
      }
    });

    test('each entry gets a fresh budget, so repeated evals never starve', () {
      final engine = JsEngine(
        scriptTimeout: const Duration(milliseconds: 300),
      );
      try {
        for (var i = 0; i < 5; i++) {
          // An IIFE, not a bare `let` — successive evals share one global
          // scope, so a top-level `let` would collide with itself.
          expect(
            engine.eval('(() => { let x = 0; for (let i=0;i<50000;i++) x++; return x; })()'),
            '50000',
          );
        }
      } finally {
        engine.dispose();
      }
    });

    test('zero disables the budget', () {
      final engine = JsEngine(scriptTimeout: Duration.zero);
      try {
        // Would be interrupted under any finite budget this test could wait
        // for; completes because there is none.
        expect(engine.eval('let x = 0; for (let i=0;i<3000000;i++) x++; x'),
            '3000000');
      } finally {
        engine.dispose();
      }
    });
  });

  group('memory limit', () {
    test('allocating past the limit throws instead of exhausting the host',
        () {
      final engine = JsEngine(memoryLimitBytes: 1024 * 1024);
      try {
        expect(
          () => engine.eval('''
            const a = [];
            for (;;) a.push(new Array(10000).fill(0));
          '''),
          throwsA(isA<JsEvalException>()),
        );
      } finally {
        engine.dispose();
      }
    });

    test('ordinary allocation under the limit is unaffected', () {
      final engine = JsEngine(memoryLimitBytes: 64 * 1024 * 1024);
      try {
        expect(engine.eval('new Array(10000).fill(7).length'), '10000');
      } finally {
        engine.dispose();
      }
    });
  });

  group('stack limit', () {
    test('unbounded recursion throws rather than crashing the process', () {
      final engine = JsEngine();
      try {
        expect(
          () => engine.eval('(function f() { return f(); })()'),
          throwsA(isA<JsEvalException>()),
        );
      } finally {
        engine.dispose();
      }
    });

    test('reasonable recursion depth still works', () {
      final engine = JsEngine();
      try {
        expect(
          engine.eval('(function f(n) { return n <= 0 ? 0 : 1 + f(n-1); })(500)'),
          '500',
        );
      } finally {
        engine.dispose();
      }
    });
  });

  group('limits and fetch together', () {
    late HttpServer server;

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        // Slower than the script budget on purpose — see the test below.
        await Future<void>.delayed(const Duration(milliseconds: 400));
        request.response
          ..statusCode = 200
          ..write('slow but fine');
        await request.response.close();
      });
    });

    tearDown(() => server.close(force: true));

    test(
      'host round-trip time is not charged against the script budget',
      () async {
        // The server takes ~400ms, well past this 150ms *script* budget —
        // but that time is spent waiting in Dart, not running JS, so the
        // script must survive it. This is the distinction between
        // scriptTimeout and fetchTimeout.
        final engine = JsEngine(
          scriptTimeout: const Duration(milliseconds: 150),
          fetchTimeout: const Duration(seconds: 5),
        );
        try {
          final url = 'http://${server.address.address}:${server.port}/slow';
          final result = await engine.evalAsync(
            'fetch(${jsonEncode(url)}).then(r => r.body)',
          );
          expect(result, '"slow but fine"');
        } finally {
          engine.dispose();
        }
      },
    );

    test('a runaway continuation after a fetch is still interrupted', () async {
      final engine = JsEngine(
        scriptTimeout: const Duration(milliseconds: 300),
        fetchTimeout: const Duration(seconds: 5),
      );
      try {
        final url = 'http://${server.address.address}:${server.port}/slow';
        await expectLater(
          engine.evalAsync(
            'fetch(${jsonEncode(url)}).then(() => { while (true) {} })',
          ),
          throwsA(isA<JsEvalException>()),
        );
      } finally {
        engine.dispose();
      }
    });
  });
}
