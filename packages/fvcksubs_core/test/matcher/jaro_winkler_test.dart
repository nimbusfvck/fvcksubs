import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:test/test.dart';

void main() {
  group('JaroWinkler.similarity', () {
    test('identical strings score 1.0', () {
      expect(JaroWinkler.similarity('Arsenal', 'Arsenal'), 1.0);
    });

    test('an empty string scores 0', () {
      expect(JaroWinkler.similarity('', 'Arsenal'), 0);
      expect(JaroWinkler.similarity('Arsenal', ''), 0);
      expect(JaroWinkler.similarity('', ''), 1.0);
    });

    test('no matching characters scores 0', () {
      expect(JaroWinkler.similarity('abc', 'xyz'), 0);
    });

    test('matches the canonical MARTHA/MARHTA value (~0.961)', () {
      expect(
        JaroWinkler.similarity('MARTHA', 'MARHTA'),
        closeTo(0.9611, 0.001),
      );
    });

    test('a shared prefix scores higher than a shared suffix', () {
      // "manchester united" vs "manchester city": differ at the end, same
      // prefix length. "united manchester" vs "city manchester": differ at
      // the start.
      final sameStartDiffEnd = JaroWinkler.similarity(
        'manchester united',
        'manchester city',
      );
      final diffStartSameEnd = JaroWinkler.similarity(
        'united manchester',
        'city manchester',
      );

      expect(sameStartDiffEnd, greaterThan(diffStartSameEnd));
    });

    test('similarity is symmetric for a pair with no shared prefix', () {
      expect(
        JaroWinkler.similarity('chelsea', 'everton'),
        JaroWinkler.similarity('everton', 'chelsea'),
      );
    });
  });
}
