/// Jaro-Winkler string similarity.
///
/// Tolerant of small typos and transpositions, and weights matches at the
/// start of the string more heavily — good for team names, which usually
/// differ near the end (e.g. "Manchester United" vs "Manchester City").
abstract final class JaroWinkler {
  /// Max prefix length that can boost the score (standard Winkler).
  static const int _maxPrefixLength = 4;

  /// Scaling weight for the prefix bonus (standard Winkler).
  static const double _scalingFactor = 0.1;

  /// Computes Jaro-Winkler similarity between [a] and [b], range 0..1.
  static double similarity(String a, String b) {
    if (a == b) return 1;
    if (a.isEmpty || b.isEmpty) return 0;

    final jaro = _jaro(a, b);
    if (jaro == 0) return 0;

    var prefixLength = 0;
    final maxPrefix = a.length < b.length ? a.length : b.length;
    while (prefixLength < maxPrefix &&
        prefixLength < _maxPrefixLength &&
        a[prefixLength] == b[prefixLength]) {
      prefixLength++;
    }

    return jaro + prefixLength * _scalingFactor * (1 - jaro);
  }

  static double _jaro(String a, String b) {
    final aLen = a.length;
    final bLen = b.length;

    final matchDistance = (aLen > bLen ? aLen : bLen) ~/ 2 - 1;
    final aMatched = List<bool>.filled(aLen, false);
    final bMatched = List<bool>.filled(bLen, false);

    var matches = 0;
    for (var i = 0; i < aLen; i++) {
      final start = (i - matchDistance).clamp(0, bLen);
      final end = (i + matchDistance + 1).clamp(0, bLen);
      for (var j = start; j < end; j++) {
        if (bMatched[j] || a[i] != b[j]) continue;
        aMatched[i] = true;
        bMatched[j] = true;
        matches++;
        break;
      }
    }

    if (matches == 0) return 0;

    var transpositions = 0;
    var bIndex = 0;
    for (var i = 0; i < aLen; i++) {
      if (!aMatched[i]) continue;
      while (!bMatched[bIndex]) {
        bIndex++;
      }
      if (a[i] != b[bIndex]) transpositions++;
      bIndex++;
    }

    final m = matches.toDouble();
    return (m / aLen + m / bLen + (m - transpositions / 2) / m) / 3;
  }
}
