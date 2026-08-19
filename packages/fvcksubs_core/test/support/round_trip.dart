import 'dart:convert';

import 'package:test/test.dart';

/// Asserts that [value] survives a full JSON round trip unchanged.
///
/// This is the core of the conformance suite: it proves a type's `toJson` and
/// `fromJson` agree, and — by routing through `jsonEncode`/`jsonDecode` — that
/// the encoded form is real JSON (no `DateTime`, enum, or nested object leaking
/// through unserialized). The same helper will run against the JS host's output
/// in Fase 2.
void expectRoundTrips<T>(
  T value, {
  required Map<String, Object?> Function(T) toJson,
  required T Function(Map<String, Object?>) fromJson,
}) {
  final encoded = jsonEncode(toJson(value));
  final decoded = fromJson(jsonDecode(encoded) as Map<String, Object?>);
  expect(decoded, equals(value));
}
