/// Reads the moment a signed playback URL stops being accepted.
///
/// Live providers hand out URLs that are only valid until a wall-clock
/// instant baked into the query string, not for a span measured from when
/// playback starts. Once that instant passes, every playlist reload and
/// every segment answers 403 — and libmpv reacts by sitting in
/// `paused-for-cache` forever rather than failing, so nothing downstream
/// notices. Reading the deadline out of the URL lets playback re-resolve
/// *before* the stream dies instead of recovering after it.
///
/// Only absolute deadlines are understood. A relative lifetime (AWS SigV4's
/// `X-Amz-Expires`) is combined with its `X-Amz-Date` issue time; on its own
/// it says nothing about when the clock started.
library;

/// Query parameters carrying an absolute expiry, in the order they are tried.
///
/// `txTime` is Tencent Cloud Live's, and is hexadecimal. The rest are decimal
/// Unix seconds, and are common across CDN signing schemes.
const _absoluteSecondsKeys = <String>[
  'exp',
  'expire',
  'expires',
  'expiry',
  'valid_until',
  'validto',
  'e',
];

const _hexSecondsKeys = <String>['txtime'];

/// Returns when [url] stops being accepted, or `null` when it carries no
/// deadline this understands.
///
/// A deadline already in the past is still returned: the caller decides
/// whether to treat it as expired, and silently dropping it would hide a
/// stream that is dead on arrival.
DateTime? streamExpiry(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return null;

  final params = <String, String>{};
  uri.queryParameters.forEach((key, value) {
    params[key.toLowerCase()] = value;
  });
  if (params.isEmpty) return null;

  for (final key in _hexSecondsKeys) {
    final seconds = int.tryParse(params[key] ?? '', radix: 16);
    if (seconds != null && seconds > 0) return _fromUnixSeconds(seconds);
  }

  for (final key in _absoluteSecondsKeys) {
    final raw = params[key];
    if (raw == null) continue;
    final seconds = int.tryParse(raw);
    // Reject values that are not plausibly a Unix timestamp: `e=1` is a page
    // number far more often than it is 1970.
    if (seconds != null && seconds > _minPlausibleUnixSeconds) {
      return _fromUnixSeconds(seconds);
    }
  }

  return _sigV4Expiry(params);
}

/// The earliest expiry treated as a real timestamp — 2001-09-09.
///
/// Below this a "seconds" value is far more likely to be an unrelated small
/// integer that happens to share a parameter name.
const int _minPlausibleUnixSeconds = 1000000000;

DateTime _fromUnixSeconds(int seconds) =>
    DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);

/// AWS SigV4 presigned URLs, as used by S3 and Cloudflare R2.
///
/// The lifetime is relative, so it only yields a deadline when paired with
/// the `X-Amz-Date` the signature was issued at.
DateTime? _sigV4Expiry(Map<String, String> params) {
  final lifetime = int.tryParse(params['x-amz-expires'] ?? '');
  if (lifetime == null || lifetime <= 0) return null;
  final issued = _parseAmzDate(params['x-amz-date']);
  if (issued == null) return null;
  return issued.add(Duration(seconds: lifetime));
}

/// Parses AWS's basic-format ISO 8601 stamp, `20260829T131034Z`.
DateTime? _parseAmzDate(String? value) {
  final text = value ?? '';
  if (text.length != 16 || text[8] != 'T' || text[15] != 'Z') return null;
  final expanded =
      '${text.substring(0, 4)}-${text.substring(4, 6)}-${text.substring(6, 8)}'
      'T${text.substring(9, 11)}:${text.substring(11, 13)}:'
      '${text.substring(13, 15)}Z';
  return DateTime.tryParse(expanded)?.toUtc();
}

/// How long [url] stays valid from [now], or `null` when it carries no
/// deadline this understands.
///
/// Returns [Duration.zero] rather than a negative span for a URL that has
/// already expired, so callers can treat "expired" and "expiring now" alike.
Duration? streamTimeToExpiry(String url, {DateTime? now}) {
  final expiry = streamExpiry(url);
  if (expiry == null) return null;
  final remaining = expiry.difference(now?.toUtc() ?? DateTime.now().toUtc());
  return remaining.isNegative ? Duration.zero : remaining;
}

/// How long before the deadline playback should swap in a fresh URL.
///
/// Re-resolving takes a round trip through the extension, so the swap is
/// armed early enough to complete while the current URL still works. Short
/// windows keep a proportional margin instead of a fixed one, which would
/// consume the whole window.
Duration renewalDelayFor(
  Duration timeToExpiry, {
  Duration margin = const Duration(seconds: 45),
  Duration minimum = const Duration(seconds: 5),
}) {
  final effectiveMargin = timeToExpiry ~/ 2 < margin
      ? timeToExpiry ~/ 2
      : margin;
  final delay = timeToExpiry - effectiveMargin;
  return delay < minimum ? minimum : delay;
}
