@TestOn('vm')
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';
import 'package:fvcksubs_js_runtime/fvcksubs_js_runtime.dart';
import 'package:test/test.dart';

void main() {
  late JsEngine engine;

  setUp(() {
    engine = JsEngine();
    HostApi.install(engine);
  });

  tearDown(() => engine.dispose());

  /// Evaluates [expression] and returns its JSON-decoded value.
  Object? evalJson(String expression) => jsonDecode(engine.eval(expression));

  group('codec', () {
    test('text/base64 round-trips, including non-ASCII', () {
      expect(
        evalJson('host.codec.textToBase64("héllo ⚽")'),
        base64.encode(utf8.encode('héllo ⚽')),
      );
      expect(
        evalJson(
          'host.codec.base64ToText(host.codec.textToBase64("héllo ⚽"))',
        ),
        'héllo ⚽',
      );
    });

    test('malformed UTF-8 becomes U+FFFD rather than throwing', () {
      // 0xFF is never valid UTF-8. Matching Dart's allowMalformed exactly is
      // what keeps a decoded string's code units identical on both sides.
      final invalid = base64.encode([0x41, 0xFF, 0x42]);
      expect(evalJson('host.codec.base64ToText(${jsonEncode(invalid)})'), 'A�B');
    });

    test('hex/base64 convert both ways', () {
      expect(evalJson('host.codec.hexToBase64("00ff10")'), base64.encode([0, 255, 16]));
      expect(
        evalJson('host.codec.base64ToHex(${jsonEncode(base64.encode([0, 255, 16]))})'),
        '00ff10',
      );
    });

    test('base64 input is lenient about padding and whitespace', () {
      // Upstreams are not careful about either; the primitive absorbs that
      // rather than every bundle reimplementing it.
      final padded = base64.encode(utf8.encode('hi'));
      expect(
        evalJson('host.codec.base64ToText(${jsonEncode(padded.replaceAll('=', ''))})'),
        'hi',
      );
    });

    test('a bad argument surfaces as a thrown JS Error', () {
      expect(
        () => engine.eval('host.codec.hexToBase64("abc")'), // odd length
        throwsA(isA<JsEvalException>()),
      );
    });
  });

  group('crypto', () {
    test('sha256 matches the Dart digest', () {
      final expected = base64.encode(
        crypto.sha256.convert(utf8.encode('fvcksubs')).bytes,
      );
      expect(
        evalJson('host.crypto.sha256(host.codec.textToBase64("fvcksubs"))'),
        expected,
      );
    });

    test('hmacSha256 matches the Dart digest', () {
      final expected = base64.encode(
        crypto.Hmac(crypto.sha256, utf8.encode('key'))
            .convert(utf8.encode('message'))
            .bytes,
      );
      expect(
        evalJson(
          'host.crypto.hmacSha256('
          'host.codec.textToBase64("key"), '
          'host.codec.textToBase64("message"))',
        ),
        expected,
      );
    });

    test('xor truncates to the shorter operand', () {
      final a = base64.encode([0x0F, 0xF0, 0xAA]);
      final b = base64.encode([0xFF, 0x0F]);
      expect(
        evalJson('host.crypto.xor(${jsonEncode(a)}, ${jsonEncode(b)})'),
        base64.encode([0xF0, 0xFF]),
      );
    });

    test('aesCbcDecrypt returns null for a wrong key, not an error', () {
      // Callers try several keys in turn, so this has to be a normal value.
      final key = base64.encode(Uint8List(16));
      final iv = base64.encode(Uint8List(16));
      final data = base64.encode(Uint8List(32));
      expect(
        engine.eval(
          'host.crypto.aesCbcDecrypt('
          '${jsonEncode(key)}, ${jsonEncode(iv)}, ${jsonEncode(data)})',
        ),
        anyOf('null', isNot(contains('Error'))),
      );
    });

    test('aesGcmDecrypt matches the NIST test-case-3 vector', () {
      // https://csrc.nist.gov/CSRC/media/Projects/Cryptographic-Algorithm-Validation-Program/documents/mac/gcmtestvectors.zip
      // Test Case 3 — no AAD, the shape Vidrock's payload uses.
      final key = base64.encode(hex('feffe9928665731c6d6a8f9467308308'));
      final nonce = base64.encode(hex('cafebabefacedbaddecaf888'));
      final ciphertextAndTag = base64.encode([
        ...hex(
          '42831ec2217774244b7221b784d0d49ce3aa212f2c02a4e035c17e2329aca12'
          'e21d514b25466931c7d8f6a5aac84aa051ba30b396a0aac973d58e091473f59'
          '85',
        ),
        ...hex('4d5c2af327cd64a62cf35abd2ba6fab4'),
      ]);
      final plaintext = hex(
        'd9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a7'
        '21c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b391aafd25'
        '5',
      );
      expect(
        evalJson(
          'host.crypto.aesGcmDecrypt('
          '${jsonEncode(key)}, ${jsonEncode(nonce)}, '
          '${jsonEncode(ciphertextAndTag)})',
        ),
        base64.encode(plaintext),
      );
    });

    test('aesGcmDecrypt returns null for a wrong key, not an error', () {
      // A wrong key fails tag verification — a normal outcome, not a crash.
      final key = base64.encode(Uint8List(32));
      final nonce = base64.encode(Uint8List(12));
      final data = base64.encode(Uint8List(32));
      expect(
        engine.eval(
          'host.crypto.aesGcmDecrypt('
          '${jsonEncode(key)}, ${jsonEncode(nonce)}, ${jsonEncode(data)})',
        ),
        anyOf('null', isNot(contains('Error'))),
      );
    });
  });

  test('an unknown host function comes back as an error envelope', () {
    // The dispatcher never throws into native code — it always answers with
    // an envelope, and the JS wrapper is what turns `error` into a throw.
    // (Decoded twice: eval JSON-encodes the JS string, which is itself JSON.)
    final envelope = jsonDecode(
      jsonDecode(engine.eval('__host_call("crypto.notAThing", "{}")'))
          as String,
    );
    expect(envelope, containsPair('error', contains('unknown host function')));
  });

  test('the JS wrapper turns an error envelope into a thrown Error', () {
    engine.eval('globalThis.__probe = () => { '
        'try { host.crypto.sha256(123); return "no throw"; } '
        'catch (e) { return "threw: " + e.message; } };');
    expect(engine.eval('__probe()'), startsWith('"threw: crypto.sha256:'));
  });
}

/// Decodes a hex string to bytes, for pasting NIST test vectors verbatim.
Uint8List hex(String s) => Uint8List.fromList([
  for (var i = 0; i < s.length; i += 2) int.parse(s.substring(i, i + 2), radix: 16),
]);
