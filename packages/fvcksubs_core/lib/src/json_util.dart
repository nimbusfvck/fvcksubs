/// Small JSON helpers shared by every protocol type.
///
/// The extension boundary is JSON-only (see PLAN.md, Prinsip #2). These keep
/// encode/decode uniform so a field never silently changes shape between two
/// types.
library;

/// Returns the enum value in [values] whose [Enum.name] equals [name], or
/// [orElse] when none matches.
///
/// Lenient by design: an extension may emit a value this app version doesn't
/// know yet, and for tolerant enums (status, format, DRM scheme) the safe
/// fallback is better than throwing.
T enumByName<T extends Enum>(
  List<T> values,
  Object? name, {
  required T orElse,
}) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  return orElse;
}

/// Like [enumByName] but throws [FormatException] on an unknown [name].
///
/// For enums whose value drives layout choice (e.g. `MediaKind`), an unknown
/// value is a real incompatibility rather than something to paper over —
/// `apiVersion` in the manifest is what guards against it.
T enumByNameStrict<T extends Enum>(List<T> values, Object? name) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  throw FormatException('Unknown $T: $name');
}

/// Encodes a [DateTime] as a UTC ISO-8601 string, or `null`.
String? dateToJson(DateTime? value) => value?.toUtc().toIso8601String();

/// Parses a UTC ISO-8601 string into a [DateTime], or `null`.
DateTime? dateFromJson(Object? value) =>
    value == null ? null : DateTime.parse(value as String).toUtc();

/// Reads a `Map<String, String>` from decoded JSON, defaulting to empty.
Map<String, String> stringMap(Object? value) {
  if (value == null) return const {};
  return (value as Map).map(
    (key, val) => MapEntry(key as String, val as String),
  );
}

/// Reads a `List<String>` from decoded JSON, defaulting to empty.
List<String> stringList(Object? value) {
  if (value == null) return const [];
  return (value as List).cast<String>();
}
