import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:test/test.dart';

void main() {
  group('ExtensionRepoEntry', () {
    Map<String, Object?> entryJson({List<String>? hosts}) => {
      'id': 'example_extension',
      'name': 'fvck (JS)',
      'version': '0.2.0',
      'manifestUrl': 'https://cdn.example/example_extension/manifest.json',
      'bundleUrl': 'https://cdn.example/example_extension/bundle.js',
      'bundleSha256': 'abc123',
      'hosts': ?hosts,
    };

    test('round-trips through fromJson/toJson', () {
      final entry = ExtensionRepoEntry.fromJson(
        entryJson(hosts: ['cdn-a.example', 'cdn-b.example']),
      );
      expect(entry.id, 'example_extension');
      expect(entry.name, 'fvck (JS)');
      expect(entry.version, '0.2.0');
      expect(
        entry.manifestUrl,
        'https://cdn.example/example_extension/manifest.json',
      );
      expect(
        entry.bundleUrl,
        'https://cdn.example/example_extension/bundle.js',
      );
      expect(entry.bundleSha256, 'abc123');
      expect(entry.hosts, ['cdn-a.example', 'cdn-b.example']);

      final roundTripped = ExtensionRepoEntry.fromJson(entry.toJson());
      expect(roundTripped, entry);
    });

    test('hosts defaults to empty when absent', () {
      final entry = ExtensionRepoEntry.fromJson(entryJson());
      expect(entry.hosts, isEmpty);
    });

    test('throws ExtensionRepoException on a missing required field', () {
      final json = entryJson()..remove('bundleSha256');
      expect(
        () => ExtensionRepoEntry.fromJson(json),
        throwsA(isA<ExtensionRepoException>()),
      );
    });

    test('equality is by value', () {
      expect(
        ExtensionRepoEntry.fromJson(entryJson()),
        ExtensionRepoEntry.fromJson(entryJson()),
      );
    });
  });

  group('ExtensionRepo', () {
    test('parses a list of entries', () {
      final repo = ExtensionRepo.fromJson({
        'extensions': [
          {
            'id': 'a',
            'name': 'A',
            'version': '1.0.0',
            'manifestUrl': 'https://x/a/manifest.json',
            'bundleUrl': 'https://x/a/bundle.js',
            'bundleSha256': 'aaa',
          },
          {
            'id': 'b',
            'name': 'B',
            'version': '1.0.0',
            'manifestUrl': 'https://x/b/manifest.json',
            'bundleUrl': 'https://x/b/bundle.js',
            'bundleSha256': 'bbb',
          },
        ],
      });
      expect(repo.extensions.map((e) => e.id), ['a', 'b']);
    });

    test('an empty repo parses to an empty list, not an error', () {
      expect(ExtensionRepo.fromJson({'extensions': []}).extensions, isEmpty);
    });

    test('throws ExtensionRepoException when "extensions" is missing', () {
      expect(
        () => ExtensionRepo.fromJson({}),
        throwsA(isA<ExtensionRepoException>()),
      );
    });

    test('round-trips through toJson', () {
      final repo = ExtensionRepo.fromJson({
        'extensions': [
          {
            'id': 'a',
            'name': 'A',
            'version': '1.0.0',
            'manifestUrl': 'https://x/a/manifest.json',
            'bundleUrl': 'https://x/a/bundle.js',
            'bundleSha256': 'aaa',
          },
        ],
      });
      expect(ExtensionRepo.fromJson(repo.toJson()), repo);
    });
  });

  group('optional metadata', () {
    test('description/author/iconUrl round-trip when present', () {
      final entry = ExtensionRepoEntry.fromJson({
        'id': 'a',
        'name': 'A',
        'version': '1.0.0',
        'manifestUrl': 'https://x/a/manifest.json',
        'bundleUrl': 'https://x/a/bundle.js',
        'bundleSha256': 'aaa',
        'description': 'Does a thing.',
        'author': 'Someone',
        'iconUrl': 'https://x/a/icon.png',
      });

      expect(entry.description, 'Does a thing.');
      expect(entry.author, 'Someone');
      expect(entry.iconUrl, 'https://x/a/icon.png');
      expect(ExtensionRepoEntry.fromJson(entry.toJson()), entry);
    });

    test('all three are optional — absent means null, not an error', () {
      final entry = ExtensionRepoEntry.fromJson({
        'id': 'a',
        'name': 'A',
        'version': '1.0.0',
        'manifestUrl': 'https://x/a/manifest.json',
        'bundleUrl': 'https://x/a/bundle.js',
        'bundleSha256': 'aaa',
      });

      expect(entry.description, isNull);
      expect(entry.author, isNull);
      expect(entry.iconUrl, isNull);
      expect(entry.toJson().containsKey('description'), isFalse);
    });
  });
}
