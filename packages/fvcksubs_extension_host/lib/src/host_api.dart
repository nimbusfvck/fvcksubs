import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_js_runtime/fvcksubs_js_runtime.dart';
import 'package:pointycastle/export.dart';

import 'extension_storage.dart';

/// The synchronous half of the extension host API — `crypto` and `codec`.
///
/// PLAN.md §18 splits the host API in two: `fetch` is async and has its own
/// bridge, everything else is synchronous. These ride the engine's generic
/// `__host_call(name, argsJson)` hook, which is exactly the synchronous pipe
/// that needs.
///
/// **Binary crosses the boundary as base64.** The bridge carries JSON
/// strings, and adding a second binary channel to the FFI would buy little:
/// these primitives are called a handful of times per request, not per byte.
/// So a "byte string" in extension JS is always base64, and the encode/decode
/// steps are themselves primitives.
///
/// **Failures travel inside the JSON**, as `{"error": ...}` rather than as a
/// thrown native error — the same constraint M10 hit with `fetch`, where
/// `NativeCallable` cannot carry an exceptional return for a pointer-returning
/// callback. The JS wrapper turns that back into a thrown `Error`, so from
/// the bundle's side it reads as an ordinary exception.
abstract final class HostApi {
  /// Installs the host API into [engine]: registers the dispatcher and
  /// evaluates the JS wrapper that exposes it as `host.crypto`/`host.codec`.
  ///
  /// Call before evaluating any bundle.
  static void install(JsEngine engine, {ExtensionStorage? storage}) {
    engine.setHostFunction(
      storage == null
          ? dispatch
          : (name, argsJson) => dispatchWith(storage, name, argsJson),
    );
    engine.eval(prelude);
  }

  /// [dispatch], plus the `storage.*` calls, which need somewhere to put
  /// things and so cannot be static like the rest.
  ///
  /// A bundle running on a host that passed no storage still sees
  /// `host.storage`; its calls just fail, which is why the prelude's wrapper
  /// turns a read into `null` and a write into a no-op. Persistence is a
  /// cache an extension may use, never one it may rely on.
  static String dispatchWith(
    ExtensionStorage storage,
    String name,
    String argsJson,
  ) {
    if (!name.startsWith('storage.')) return dispatch(name, argsJson);
    try {
      final args = (jsonDecode(argsJson) as Map).cast<String, Object?>();
      final key = args['key'];
      if (key is! String || key.isEmpty) {
        throw ArgumentError('$name: "key" must be a non-empty string');
      }
      return jsonEncode({
        'value': switch (name) {
          'storage.read' => storage.read(key),
          'storage.write' => _write(storage, key, args),
          'storage.delete' => _deleteFrom(storage, key),
          _ => throw ArgumentError('unknown host function "$name"'),
        },
      });
    } catch (e) {
      return jsonEncode({'error': '$e'});
    }
  }

  static Object? _write(
    ExtensionStorage storage,
    String key,
    Map<String, Object?> args,
  ) {
    final value = args['value'];
    if (value is! String) {
      throw ArgumentError('storage.write: "value" must be a string');
    }
    final ttlMs = args['ttlMs'];
    storage.write(
      key,
      value,
      ttl: ttlMs is num && ttlMs > 0
          ? Duration(milliseconds: ttlMs.toInt())
          : null,
    );
    return null;
  }

  static Object? _deleteFrom(ExtensionStorage storage, String key) {
    storage.delete(key);
    return null;
  }

  /// Handles one `__host_call`. Returns a JSON envelope: `{"value": ...}` on
  /// success, `{"error": "..."}` on failure — never throws into native code.
  static String dispatch(String name, String argsJson) {
    try {
      final args = (jsonDecode(argsJson) as Map).cast<String, Object?>();
      return jsonEncode({'value': _invoke(name, args)});
    } catch (e) {
      return jsonEncode({'error': '$e'});
    }
  }

  static Object? _invoke(String name, Map<String, Object?> args) {
    String arg(String key) {
      final value = args[key];
      if (value is! String) {
        throw ArgumentError('$name: "$key" must be a string');
      }
      return value;
    }

    return switch (name) {
      // --- codec ---
      // UTF-8 decode is a primitive rather than JS's own because the
      // malformed-input behaviour has to match the Dart adapters exactly:
      // an invalid sequence becomes U+FFFD, never an error and never a lone
      // surrogate. That keeps a decoded string's UTF-16 code units identical
      // on both sides, which is what lets code-unit-level transforms (like
      // Cricfy's `flip`) live in JS at all.
      'codec.base64ToText' => utf8.decode(
        _base64(arg('value')),
        allowMalformed: true,
      ),
      'codec.textToBase64' => base64.encode(utf8.encode(arg('value'))),
      'codec.hexToBase64' => base64.encode(_fromHex(arg('value'))),
      'codec.base64ToHex' => _toHex(_base64(arg('value'))),

      // --- crypto ---
      'crypto.sha256' => base64.encode(
        crypto.sha256.convert(_base64(arg('value'))).bytes,
      ),
      'crypto.hmacSha256' => base64.encode(
        crypto.Hmac(
          crypto.sha256,
          _base64(arg('key')),
        ).convert(_base64(arg('value'))).bytes,
      ),
      'crypto.xor' => base64.encode(_xor(_base64(arg('a')), _base64(arg('b')))),
      'crypto.aesCbcDecrypt' => _aesCbcDecrypt(
        key: _base64(arg('key')),
        iv: _base64(arg('iv')),
        data: _base64(arg('data')),
      ),
      'crypto.aesGcmDecrypt' => _aesGcmDecrypt(
        key: _base64(arg('key')),
        nonce: _base64(arg('nonce')),
        data: _base64(arg('data')),
      ),

      // --- match ---
      'match.resolve' => _resolveMatch(args),

      _ => throw ArgumentError('unknown host function "$name"'),
    };
  }

  /// Runs the shared event matcher (PLAN.md §12) over JS-supplied candidates.
  ///
  /// The split here is the point: the **algorithm** is the host's, so every
  /// extension matches the same fixture the same way; the **vertical
  /// knowledge** — aliases, stop tokens, ambiguous-alone words — arrives as
  /// a `NormalizationProfile` from the extension, because only it knows what
  /// "man utd" means. `NormalizationProfile` was already JSON-shaped and
  /// documented as data an extension carries, so this needed no new concept.
  ///
  /// Candidates cross as `{teamA, teamB, startsAt?}` and the winner comes
  /// back as an **index**, not a payload: an extension's payload is its own
  /// object (a channel, a link) and has no business being serialized through
  /// the host just to be handed straight back.
  static Object? _resolveMatch(Map<String, Object?> args) {
    final queryJson = (args['query']! as Map).cast<String, Object?>();
    final candidatesJson = (args['candidates']! as List)
        .map((e) => (e as Map).cast<String, Object?>())
        .toList();

    final resolver = EventMatchResolver(
      profile: args['profile'] == null
          ? NormalizationProfile.empty
          : NormalizationProfile.fromJson(
              (args['profile']! as Map).cast<String, Object?>(),
            ),
      timeWindow: args['timeWindowMinutes'] == null
          ? const Duration(minutes: 45)
          : Duration(minutes: (args['timeWindowMinutes']! as num).toInt()),
      minTeamScore: (args['minTeamScore'] as num?)?.toDouble() ?? 0.86,
    );

    final result = resolver.resolve<int>(
      query: MatchQuery(
        teamA: queryJson['teamA']! as String,
        teamB: queryJson['teamB']! as String,
        teamAShort: queryJson['teamAShort'] as String?,
        teamBShort: queryJson['teamBShort'] as String?,
        kickoff: _dateOf(queryJson['kickoff']),
      ),
      candidates: [
        for (var i = 0; i < candidatesJson.length; i++)
          EventCandidate<int>(
            teamA: candidatesJson[i]['teamA']! as String,
            teamB: candidatesJson[i]['teamB']! as String,
            startsAt: _dateOf(candidatesJson[i]['startsAt']),
            payload: i,
          ),
      ],
    );

    if (result == null) return null;
    return {'index': result.payload, 'confidence': result.confidence};
  }

  static DateTime? _dateOf(Object? value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value)?.toUtc();
  }

  /// XOR of [a] and [b], truncated to the shorter — a keystream shorter than
  /// its input is a real pattern (Cricfy derives a 16-byte key by masking the
  /// first 16 bytes of a SHA-256), so this is not an error.
  static Uint8List _xor(Uint8List a, Uint8List b) {
    final length = a.length < b.length ? a.length : b.length;
    final out = Uint8List(length);
    for (var i = 0; i < length; i++) {
      out[i] = a[i] ^ b[i];
    }
    return out;
  }

  /// AES-CBC + PKCS7 decrypt. Returns `null` (JSON `null`, not an error) when
  /// the input can't be decrypted — callers here legitimately try several
  /// keys in turn, so a wrong key is a normal outcome, not a failure.
  static String? _aesCbcDecrypt({
    required Uint8List key,
    required Uint8List iv,
    required Uint8List data,
  }) {
    if (data.isEmpty || data.length % 16 != 0) return null;
    try {
      final cipher =
          PaddedBlockCipherImpl(PKCS7Padding(), CBCBlockCipher(AESEngine()))
            ..init(
              false,
              PaddedBlockCipherParameters<CipherParameters, CipherParameters>(
                ParametersWithIV<KeyParameter>(KeyParameter(key), iv),
                null,
              ),
            );
      return base64.encode(cipher.process(data));
    } catch (_) {
      return null;
    }
  }

  /// AES-GCM decrypt, 128-bit tag. [data] is ciphertext with the tag
  /// concatenated on the end — the `javax.crypto`/Kotlin convention Vidrock's
  /// payload follows, so no reshaping is needed on the JS side beyond
  /// splitting the leading 12-byte nonce off the payload. No AAD.
  ///
  /// Same null-on-failure contract as [_aesCbcDecrypt]: a wrong key fails tag
  /// verification, which is a normal outcome here, not an error.
  static String? _aesGcmDecrypt({
    required Uint8List key,
    required Uint8List nonce,
    required Uint8List data,
  }) {
    if (data.length < 16) return null;
    try {
      final cipher = GCMBlockCipher(AESEngine())
        ..init(
          false,
          AEADParameters(KeyParameter(key), 128, nonce, Uint8List(0)),
        );
      return base64.encode(cipher.process(data));
    } catch (_) {
      return null;
    }
  }

  /// Lenient base64: whitespace stripped, padding completed. The upstreams
  /// these extensions talk to are not careful about either.
  static Uint8List _base64(String value) {
    final stripped = value.replaceAll(RegExp(r'[\r\n\t ]'), '');
    final remainder = stripped.length % 4;
    final padded = remainder == 0 ? stripped : stripped + '=' * (4 - remainder);
    return base64.decode(base64.normalize(padded));
  }

  static Uint8List _fromHex(String hex) {
    if (hex.length.isOdd) throw ArgumentError('hex has an odd length');
    final out = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }

  static String _toHex(Uint8List bytes) =>
      [for (final b in bytes) b.toRadixString(16).padLeft(2, '0')].join();

  /// The JS side of the API, evaluated into every extension engine.
  ///
  /// Kept as a string rather than a shipped `.js` asset because it is *host*
  /// code, not extension code — it must be identical for every bundle and
  /// must not be something an installer could swap.
  static const String prelude = r'''
(() => {
  function call(name, args) {
    const raw = __host_call(name, JSON.stringify(args));
    const result = JSON.parse(raw);
    if (result.error !== undefined) {
      throw new Error(name + ': ' + result.error);
    }
    return result.value;
  }

  // Binary is base64 everywhere in this API — see HostApi's doc comment.
  globalThis.host = {
    codec: {
      base64ToText: (value) => call('codec.base64ToText', { value }),
      textToBase64: (value) => call('codec.textToBase64', { value }),
      hexToBase64: (value) => call('codec.hexToBase64', { value }),
      base64ToHex: (value) => call('codec.base64ToHex', { value }),
    },
    crypto: {
      sha256: (value) => call('crypto.sha256', { value }),
      hmacSha256: (key, value) => call('crypto.hmacSha256', { key, value }),
      xor: (a, b) => call('crypto.xor', { a, b }),
      // Returns null when the data will not decrypt under this key, so a
      // caller can try the next one.
      aesCbcDecrypt: (key, iv, data) =>
        call('crypto.aesCbcDecrypt', { key, iv, data }),
      // Same null-on-failure contract as aesCbcDecrypt. `data` carries the
      // 16-byte GCM tag concatenated on the end.
      aesGcmDecrypt: (key, nonce, data) =>
        call('crypto.aesGcmDecrypt', { key, nonce, data }),
    },
    // A cache that outlives the engine, when the host has somewhere to put
    // it. Every call swallows its own failure — an extension that asks for
    // storage on a host without it, or writes more than the host allows,
    // carries on with a cache miss instead of failing the role call.
    storage: {
      read: (key) => {
        try {
          return call('storage.read', { key });
        } catch (_) {
          return null;
        }
      },
      // ttlMs is optional; without it the value stays until overwritten,
      // deleted, or the host drops it.
      write: (key, value, ttlMs) => {
        try {
          call('storage.write', { key, value, ttlMs: ttlMs || null });
          return true;
        } catch (_) {
          return false;
        }
      },
      delete: (key) => {
        try {
          call('storage.delete', { key });
          return true;
        } catch (_) {
          return false;
        }
      },
    },
    match: {
      // Finds which of `candidates` is the same fixture as `query`, using the
      // host's shared matcher so every extension agrees. `profile` carries
      // the vertical's own aliases/stop tokens.
      //
      // candidates: [{ teamA, teamB, startsAt? }] (ISO-8601 UTC)
      // returns:    { index, confidence } | null
      resolve: (query, candidates, options) =>
        call('match.resolve', {
          query,
          candidates,
          profile: (options && options.profile) || null,
          timeWindowMinutes: (options && options.timeWindowMinutes) || null,
          minTeamScore: (options && options.minTeamScore) || null,
        }),
    },
  };
})();
''';
}
