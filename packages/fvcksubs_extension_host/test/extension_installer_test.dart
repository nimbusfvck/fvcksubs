import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';
import 'package:test/test.dart';

/// `ExtensionInstaller` end to end against a loopback server: fetch
/// `repo.json`, decide what needs installing, download + hash-verify, and —
/// the proof this isn't just plumbing — actually load the result through
/// `JsExtension` and call its `catalog()`.
void main() {
  late HttpServer server;
  late String baseUrl;

  const manifestJson = {
    'apiVersion': 1,
    'id': 'test_ext',
    'name': 'Test Extension',
    'version': '0.2.0',
    'runtime': 'js',
    'entry': 'bundle.js',
    'categories': ['live'],
    'providers': [
      {
        'id': 'test_ext.items',
        'roles': ['catalog'],
        'catalogs': [
          {
            'id': 'main',
            'name': 'Main',
            'category': 'live',
            'kind': 'liveEvent',
            'display': 'row',
          },
        ],
      },
    ],
    'permissions': {'hosts': <String>[]},
  };
  const bundleJs =
      'globalThis.__extension = { '
      'catalog: async () => ({ items: [{ '
      'ref: { extensionId: "test_ext", providerId: "test_ext.items", id: "1" }, '
      'kind: "liveEvent", title: "Hello from the installed bundle" '
      '}] }) };';

  late String bundleHash;

  setUp(() async {
    bundleHash = crypto.sha256.convert(utf8.encode(bundleJs)).toString();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    baseUrl = 'http://${server.address.address}:${server.port}';

    server.listen((request) async {
      final path = request.uri.path;
      request.response.headers.contentType = ContentType.json;
      if (path == '/repo.json') {
        request.response.write(
          jsonEncode({
            'extensions': [
              {
                'id': 'test_ext',
                'name': 'Test Extension',
                'version': '0.2.0',
                'manifestUrl': '$baseUrl/ext/manifest.json',
                'bundleUrl': '$baseUrl/ext/bundle.js',
                'bundleSha256': bundleHash,
              },
            ],
          }),
        );
      } else if (path == '/ext/manifest.json') {
        request.response.write(jsonEncode(manifestJson));
      } else if (path == '/ext/bundle.js') {
        request.response.write(bundleJs);
      } else if (path == '/repo-bad-hash.json') {
        request.response.write(
          jsonEncode({
            'extensions': [
              {
                'id': 'test_ext',
                'name': 'Test Extension',
                'version': '0.2.0',
                'manifestUrl': '$baseUrl/ext/manifest.json',
                'bundleUrl': '$baseUrl/ext/bundle.js',
                'bundleSha256': 'not-the-real-hash',
              },
            ],
          }),
        );
      } else if (path == '/repo-wrong-id.json') {
        request.response.write(
          jsonEncode({
            'extensions': [
              {
                'id': 'a-different-id',
                'name': 'Test Extension',
                'version': '0.2.0',
                'manifestUrl': '$baseUrl/ext/manifest.json',
                'bundleUrl': '$baseUrl/ext/bundle.js',
                'bundleSha256': bundleHash,
              },
            ],
          }),
        );
      } else {
        request.response.statusCode = 404;
      }
      await request.response.close();
    });
  });

  tearDown(() => server.close(force: true));

  test('fetchRepo parses repo.json into ExtensionRepoEntry values', () async {
    final installer = ExtensionInstaller();
    final repo = await installer.fetchRepo('$baseUrl/repo.json');

    expect(repo.extensions, hasLength(1));
    expect(repo.extensions.single.id, 'test_ext');
    expect(repo.extensions.single.version, '0.2.0');
    expect(repo.extensions.single.bundleSha256, bundleHash);
  });

  group('checkForUpdates', () {
    late ExtensionRepo repo;

    setUp(() async {
      repo = await ExtensionInstaller().fetchRepo('$baseUrl/repo.json');
    });

    test('an extension not yet installed is included', () {
      final updates = ExtensionInstaller().checkForUpdates(repo, {});
      expect(updates.map((e) => e.id), ['test_ext']);
    });

    test('the same version already installed is excluded', () {
      final updates = ExtensionInstaller().checkForUpdates(repo, {
        'test_ext': '0.2.0',
      });
      expect(updates, isEmpty);
    });

    test('an older installed version is included as an update', () {
      final updates = ExtensionInstaller().checkForUpdates(repo, {
        'test_ext': '0.1.0',
      });
      expect(updates.map((e) => e.id), ['test_ext']);
    });

    test('a newer installed version (ahead of the repo) is excluded', () {
      final updates = ExtensionInstaller().checkForUpdates(repo, {
        'test_ext': '0.9.0',
      });
      expect(updates, isEmpty);
    });

    test('version comparison is numeric per segment, not lexicographic', () {
      // "0.10.0" must read as newer than "0.9.0" — a naive string compare
      // would get this backwards.
      final tenRepo = ExtensionRepo.fromJson({
        'extensions': [
          {
            'id': 'test_ext',
            'name': 'Test Extension',
            'version': '0.10.0',
            'manifestUrl': '$baseUrl/ext/manifest.json',
            'bundleUrl': '$baseUrl/ext/bundle.js',
            'bundleSha256': bundleHash,
          },
        ],
      });
      final updates = ExtensionInstaller().checkForUpdates(tenRepo, {
        'test_ext': '0.9.0',
      });
      expect(updates, hasLength(1));
    });
  });

  group('download', () {
    test('succeeds, hash-verifies, and returns a loadable InstalledExtension', () async {
      final installer = ExtensionInstaller();
      final repo = await installer.fetchRepo('$baseUrl/repo.json');
      final installed = await installer.download(repo.extensions.single);

      expect(installed.id, 'test_ext');
      expect(installed.version, '0.2.0');
      expect(jsonDecode(installed.manifestJson), manifestJson);
      expect(installed.bundleJs, bundleJs);

      // The actual proof: this isn't just text moved around, it's a
      // genuinely loadable extension.
      final manifest = Manifest.parse(
        jsonDecode(installed.manifestJson) as Map<String, Object?>,
      );
      final extension = JsExtension.load(
        manifest: manifest,
        source: installed.bundleJs,
      );
      addTearDown(extension.dispose);

      final page = await extension.catalog(
        const CatalogQuery(providerId: 'test_ext.items', catalogId: 'main'),
      );
      expect(page.items, hasLength(1));
      expect(page.items.single.title, 'Hello from the installed bundle');
    });

    test('a bundle that does not match the declared hash is rejected', () async {
      final installer = ExtensionInstaller();
      final repo = await installer.fetchRepo('$baseUrl/repo-bad-hash.json');

      await expectLater(
        installer.download(repo.extensions.single),
        throwsA(isA<ExtensionInstallException>()),
      );
    });

    test('a manifest whose id does not match the repo entry is rejected', () async {
      final installer = ExtensionInstaller();
      final repo = await installer.fetchRepo('$baseUrl/repo-wrong-id.json');

      await expectLater(
        installer.download(repo.extensions.single),
        throwsA(isA<ExtensionInstallException>()),
      );
    });
  });
}
