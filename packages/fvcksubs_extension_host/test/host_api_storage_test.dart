@TestOn('vm')
library;

import 'dart:convert';

import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';
import 'package:fvcksubs_js_runtime/fvcksubs_js_runtime.dart';
import 'package:test/test.dart';

void main() {
  late JsEngine engine;
  late MemoryExtensionStorage storage;

  setUp(() {
    engine = JsEngine();
    storage = MemoryExtensionStorage();
    HostApi.install(engine, storage: storage);
  });

  tearDown(() => engine.dispose());

  Object? evalJson(String expression) => jsonDecode(engine.eval(expression));

  test('a written value reads back, and survives a fresh engine', () {
    expect(evalJson('host.storage.write("events", "[1,2,3]")'), true);
    expect(evalJson('host.storage.read("events")'), '[1,2,3]');

    // What the whole primitive exists for: the same store handed to a new
    // engine still has it, the way a persisted one would after a restart.
    final next = JsEngine();
    addTearDown(next.dispose);
    HostApi.install(next, storage: storage);
    expect(jsonDecode(next.eval('host.storage.read("events")')), '[1,2,3]');
  });

  test('an absent key reads as null, not an error', () {
    expect(evalJson('host.storage.read("nothing")'), isNull);
  });

  test('a deleted key is gone', () {
    engine.eval('host.storage.write("k", "v")');
    expect(evalJson('host.storage.delete("k")'), true);
    expect(evalJson('host.storage.read("k")'), isNull);
  });

  test('a value past its ttl reads as absent', () async {
    engine.eval('host.storage.write("k", "v", 40)');
    expect(evalJson('host.storage.read("k")'), 'v');
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(evalJson('host.storage.read("k")'), isNull);
  });

  test('a value over the size limit is refused, not truncated', () {
    final small = JsEngine();
    addTearDown(small.dispose);
    HostApi.install(small, storage: MemoryExtensionStorage(maxValueBytes: 8));

    expect(jsonDecode(small.eval('host.storage.write("k", "123456789")')), false);
    expect(jsonDecode(small.eval('host.storage.read("k")')), isNull);
    expect(jsonDecode(small.eval('host.storage.write("k", "12345678")')), true);
  });

  test('a new key past the entry limit is refused', () {
    final small = JsEngine();
    addTearDown(small.dispose);
    HostApi.install(small, storage: MemoryExtensionStorage(maxEntries: 1));

    expect(jsonDecode(small.eval('host.storage.write("a", "1")')), true);
    expect(jsonDecode(small.eval('host.storage.write("b", "2")')), false);
    // Overwriting a key already held is not a new key, so it still works.
    expect(jsonDecode(small.eval('host.storage.write("a", "3")')), true);
    expect(jsonDecode(small.eval('host.storage.read("a")')), '3');
  });

  test('a host with no storage reports misses instead of throwing', () {
    final bare = JsEngine();
    addTearDown(bare.dispose);
    HostApi.install(bare);

    expect(jsonDecode(bare.eval('typeof host.storage.read')), 'function');
    expect(jsonDecode(bare.eval('host.storage.write("k", "v")')), false);
    expect(jsonDecode(bare.eval('host.storage.read("k")')), isNull);
    expect(jsonDecode(bare.eval('host.storage.delete("k")')), false);
  });

  test('the other host primitives still work alongside storage', () {
    expect(evalJson('host.codec.textToBase64("hi")'), base64.encode([104, 105]));
  });

  group('snapshot/restore', () {
    test('round-trips live entries and drops expired ones', () async {
      engine.eval('host.storage.write("keep", "yes")');
      engine.eval('host.storage.write("gone", "no", 30)');
      await Future<void>.delayed(const Duration(milliseconds: 60));

      final restored = MemoryExtensionStorage()..restore(storage.snapshot());
      expect(restored.read('keep'), 'yes');
      expect(restored.read('gone'), isNull);
    });

    test('ignores entries that are not the shape it wrote', () {
      final restored = MemoryExtensionStorage()
        ..restore({
          'ok': {'value': 'v'},
          'junk': 'not a map',
          'alsoJunk': {'value': 42},
        });
      expect(restored.read('ok'), 'v');
      expect(restored.read('junk'), isNull);
      expect(restored.read('alsoJunk'), isNull);
    });
  });
}
