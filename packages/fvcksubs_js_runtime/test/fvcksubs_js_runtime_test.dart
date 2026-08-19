import 'package:test/test.dart';

import 'package:fvcksubs_js_runtime/fvcksubs_js_runtime.dart';

void main() {
  late JsEngine engine;

  setUp(() => engine = JsEngine());
  tearDown(() => engine.dispose());

  test('evaluates arithmetic', () {
    expect(engine.eval('1 + 1'), '2');
  });

  test('round-trips an object through JSON', () {
    expect(
      engine.eval('({a: 1, b: [true, null, "x"]})'),
      '{"a":1,"b":[true,null,"x"]}',
    );
  });

  test('falls back to ToString for undefined', () {
    expect(engine.eval('undefined'), 'undefined');
  });

  test('a thrown script error surfaces as a catchable exception', () {
    expect(
      () => engine.eval('null.x'),
      throwsA(
        isA<JsEvalException>().having(
          (e) => e.message,
          'message',
          contains('TypeError'),
        ),
      ),
    );
  });

  test('a syntax error surfaces as a catchable exception, not a crash', () {
    expect(() => engine.eval('this is not js'), throwsA(isA<JsEvalException>()));
  });

  test('state persists across eval calls on the same engine', () {
    engine.eval('globalThis.count = 1');
    expect(engine.eval('++count'), '2');
  });

  test('a fresh engine does not see another engine\'s state', () {
    engine.eval('globalThis.marker = 42');
    final other = JsEngine();
    try {
      expect(other.eval('typeof marker'), '"undefined"');
    } finally {
      other.dispose();
    }
  });

  group('host function', () {
    test('__host_call reaches the registered Dart function', () {
      final calls = <String>[];
      engine.setHostFunction((name, argsJson) {
        calls.add('$name:$argsJson');
        return '{"ok":true}';
      });

      final result = engine.eval('__host_call("ping", JSON.stringify({n: 1}))');

      expect(calls, ['ping:{"n":1}']);
      expect(result, '"{\\"ok\\":true}"');
    });

    test('calling __host_call with none registered throws', () {
      expect(
        () => engine.eval('__host_call("x", "")'),
        throwsA(isA<JsEvalException>()),
      );
    });

    test('setHostFunction(null) clears a previously registered function', () {
      engine.setHostFunction((name, argsJson) => 'x');
      engine.setHostFunction(null);
      expect(
        () => engine.eval('__host_call("x", "")'),
        throwsA(isA<JsEvalException>()),
      );
    });
  });

  test('using an engine after dispose throws, not crashes', () {
    final disposable = JsEngine();
    disposable.dispose();
    expect(() => disposable.eval('1'), throwsStateError);
  });
}
