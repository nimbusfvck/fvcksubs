import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_app/addons/installer_controller.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';

import 'support/harness.dart';

/// `InstallerController` against a loopback repo — the app-layer half of the
/// install chain: what the UI reads (listings, busy, error) and what an
/// install actually does to the live registry and to storage.
///
/// The QuickJS engine is stubbed out via `loadExtension` (see the
/// controller's constructor): M22's tests already prove a downloaded bundle
/// really loads and runs, so repeating that here would only make these tests
/// slower and dependent on the native library.
void main() {
  late HttpServer server;
  late String baseUrl;
  late String bundleHash;

  const bundleJs = 'globalThis.__extension = {};';

  /// Version the repo advertises; a test can move it to simulate an update.
  var repoVersion = '1.0.0';

  /// Hosts the repo advertises, and (unless a route overrides it) what the
  /// manifest declares too. A test can widen this to simulate an update
  /// asking for more.
  var repoHosts = <String>['cdn.example', 'api.example'];

  Map<String, Object?> manifestFor(
    String id,
    String version, {
    List<String>? hosts,
  }) => {
    'apiVersion': 1,
    'id': id,
    'name': id,
    'version': version,
    'runtime': 'js',
    'entry': 'bundle.js',
    'categories': ['live'],
    'providers': [
      {
        'id': '$id.p',
        'roles': ['catalog'],
        'catalogs': [
          {
            'id': 'main',
            'name': 'Main',
            'category': 'live',
            'kind': 'liveEvent',
          },
        ],
      },
    ],
    'permissions': {'hosts': hosts ?? repoHosts},
  };

  setUp(() async {
    repoVersion = '1.0.0';
    repoHosts = <String>['cdn.example', 'api.example'];
    bundleHash = crypto.sha256.convert(utf8.encode(bundleJs)).toString();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    baseUrl = 'http://${server.address.address}:${server.port}';

    server.listen((request) async {
      final path = request.uri.path;
      if (path == '/repo.json') {
        request.response.write(
          jsonEncode({
            'extensions': [
              {
                'id': 'remote_ext',
                'name': 'Remote Extension',
                'version': repoVersion,
                'manifestUrl': '$baseUrl/manifest.json',
                'bundleUrl': '$baseUrl/bundle.js',
                'bundleSha256': bundleHash,
                'hosts': repoHosts,
              },
            ],
          }),
        );
      } else if (path == '/repo-no-hosts.json') {
        request.response.write(
          jsonEncode({
            'extensions': [
              {
                'id': 'remote_ext',
                'name': 'Remote Extension',
                'version': repoVersion,
                'manifestUrl': '$baseUrl/manifest-no-hosts.json',
                'bundleUrl': '$baseUrl/bundle.js',
                'bundleSha256': bundleHash,
                'hosts': <String>[],
              },
            ],
          }),
        );
      } else if (path == '/repo-understates.json') {
        // Advertises one host; its manifest actually declares two.
        request.response.write(
          jsonEncode({
            'extensions': [
              {
                'id': 'remote_ext',
                'name': 'Remote Extension',
                'version': repoVersion,
                'manifestUrl': '$baseUrl/manifest-two-hosts.json',
                'bundleUrl': '$baseUrl/bundle.js',
                'bundleSha256': bundleHash,
                'hosts': <String>['cdn.example'],
              },
            ],
          }),
        );
      } else if (path == '/manifest-no-hosts.json') {
        request.response.write(
          jsonEncode(manifestFor('remote_ext', repoVersion, hosts: const [])),
        );
      } else if (path == '/manifest-two-hosts.json') {
        request.response.write(
          jsonEncode(
            manifestFor(
              'remote_ext',
              repoVersion,
              hosts: const ['cdn.example', 'sneaky.example'],
            ),
          ),
        );
      } else if (path == '/repo-empty.json') {
        request.response.write(jsonEncode({'extensions': <Object?>[]}));
      } else if (path == '/repo-bad-hash.json') {
        request.response.write(
          jsonEncode({
            'extensions': [
              {
                'id': 'remote_ext',
                'name': 'Remote Extension',
                'version': repoVersion,
                'manifestUrl': '$baseUrl/manifest.json',
                'bundleUrl': '$baseUrl/bundle.js',
                'bundleSha256': 'nope',
              },
            ],
          }),
        );
      } else if (path == '/manifest.json') {
        request.response.write(
          jsonEncode(manifestFor('remote_ext', repoVersion)),
        );
      } else if (path == '/bundle.js') {
        request.response.write(bundleJs);
      } else {
        request.response.statusCode = 404;
      }
      await request.response.close();
    });
  });

  tearDown(() => server.close(force: true));

  ({
    InstallerController controller,
    ExtensionRegistry registry,
    FakeInstalledExtensionStore store,
    FakeRepoStore repos,
    List<PermissionRequest> asked,
  })
  build({bool consent = true}) {
    final registry = ExtensionRegistry([FakeExtension(id: 'builtin')]);
    final store = FakeInstalledExtensionStore();
    final repos = FakeRepoStore();
    final asked = <PermissionRequest>[];
    return (
      controller: InstallerController(
        registry: registry,
        installer: ExtensionInstaller(),
        installedStore: store,
        repoStore: repos,
        // Stubbed loader — see this file's doc comment.
        loadExtension: (manifest, source) =>
            FakeExtension(id: manifest.id, categories: manifest.categories),
        // Most tests here are about the install mechanics, not consent, so
        // they grant it; the consent group below drives this deliberately.
        requestConsent: (request) async {
          asked.add(request);
          return consent;
        },
      ),
      registry: registry,
      store: store,
      repos: repos,
      asked: asked,
    );
  }

  group('setRepoUrl', () {
    test('persists the URL and clears stale listings', () async {
      final t = build();
      await t.controller.setRepoUrl('$baseUrl/repo.json');
      await t.controller.refresh();
      expect(t.controller.listings, isNotEmpty);

      await t.controller.setRepoUrl('$baseUrl/repo-empty.json');

      expect(t.repos.saved, '$baseUrl/repo-empty.json');
      expect(
        t.controller.listings,
        isEmpty,
        reason: 'listings described the previous repo',
      );
    });

    test(
      'an empty string clears the saved URL rather than saving blank',
      () async {
        final t = build();
        await t.controller.setRepoUrl('   ');
        expect(t.controller.repoUrl, isNull);
        expect(t.repos.saved, isNull);
      },
    );
  });

  group('refresh', () {
    test('with no repo set, reports that rather than throwing', () async {
      final t = build();
      await t.controller.refresh();
      expect(t.controller.error, contains('Set a repo URL'));
    });

    test('silent refresh with no repo set leaves the UI error-free', () async {
      final t = build();
      await t.controller.refresh(silent: true);
      expect(t.controller.error, isNull);
      expect(t.controller.busy, isFalse);
    });

    test('lists a not-yet-installed extension as an install', () async {
      final t = build();
      await t.controller.setRepoUrl('$baseUrl/repo.json');
      await t.controller.refresh();

      expect(t.controller.error, isNull);
      expect(t.controller.listings, hasLength(1));
      final listing = t.controller.listings.single;
      expect(listing.entry.id, 'remote_ext');
      expect(listing.installedVersion, isNull);
      expect(listing.isUpdate, isFalse);
    });

    test(
      'an unreachable repo surfaces an error and empties listings',
      () async {
        final t = build();
        await t.controller.setRepoUrl('$baseUrl/does-not-exist.json');
        await t.controller.refresh();

        expect(t.controller.error, contains('Check the URL'));
        expect(t.controller.error, isNot(contains('DioException')));
        expect(t.controller.listings, isEmpty);
        expect(t.controller.busy, isFalse, reason: 'must not stay stuck busy');
      },
    );

    test('a repo with no extensions says so', () async {
      final t = build();
      await t.controller.setRepoUrl('$baseUrl/repo-empty.json');
      await t.controller.refresh();
      expect(t.controller.error, contains('no extensions'));
    });
  });

  group('install', () {
    test('adds to the live registry and persists it', () async {
      final t = build();
      await t.controller.setRepoUrl('$baseUrl/repo.json');
      await t.controller.refresh();

      await t.controller.install(t.controller.listings.single.entry);

      expect(t.controller.error, isNull);
      expect(
        t.registry.installed.map((m) => m.id),
        ['builtin', 'remote_ext'],
        reason: 'installed into the live registry, no restart needed',
      );
      expect(t.store.saved.keys, ['remote_ext']);
      expect(t.store.saved['remote_ext']!.version, '1.0.0');
    });

    test('after installing, the listing reports it as installed', () async {
      final t = build();
      await t.controller.setRepoUrl('$baseUrl/repo.json');
      await t.controller.refresh();
      await t.controller.install(t.controller.listings.single.entry);

      final listing = t.controller.listings.single;
      expect(listing.installedVersion, '1.0.0');
      expect(listing.isInstalled, isTrue);
      expect(listing.isUpToDate, isTrue);
      expect(listing.isUpdate, isFalse);
      expect(t.controller.installableListings, isEmpty);
    });

    test(
      'installing a newer version replaces rather than duplicates',
      () async {
        final t = build();
        await t.controller.setRepoUrl('$baseUrl/repo.json');
        await t.controller.refresh();
        await t.controller.install(t.controller.listings.single.entry);

        repoVersion = '2.0.0';
        await t.controller.refresh();
        expect(t.controller.listings.single.isUpdate, isTrue);
        expect(t.controller.listings.single.isUpToDate, isFalse);
        await t.controller.install(t.controller.listings.single.entry);

        expect(
          t.registry.installed.map((m) => m.id),
          ['builtin', 'remote_ext'],
          reason: 'one entry per id, not two',
        );
        expect(t.store.saved['remote_ext']!.version, '2.0.0');
      },
    );

    test('a bundle that verifies but will not load is not persisted', () async {
      // The ordering guarantee in install()'s doc comment: persist only
      // after the bundle has proved it actually loads. Otherwise a bundle
      // that passes its hash check but throws on evaluation would be saved
      // and then fail again on every subsequent launch.
      final registry = ExtensionRegistry([FakeExtension(id: 'builtin')]);
      final store = FakeInstalledExtensionStore();
      final controller = InstallerController(
        registry: registry,
        installer: ExtensionInstaller(),
        installedStore: store,
        repoStore: FakeRepoStore(),
        loadExtension: (_, _) => throw StateError('bundle will not evaluate'),
        requestConsent: (_) async => true,
      );

      await controller.setRepoUrl('$baseUrl/repo.json');
      await controller.refresh();
      await controller.install(controller.listings.single.entry);

      expect(controller.error, contains('Install failed'));
      expect(
        store.saved,
        isEmpty,
        reason: 'never persist a bundle that will not run',
      );
      expect(registry.installed.map((m) => m.id), ['builtin']);
    });

    test('a bundle failing hash verification installs nothing', () async {
      final t = build();
      await t.controller.setRepoUrl('$baseUrl/repo-bad-hash.json');
      await t.controller.refresh();

      await t.controller.install(t.controller.listings.single.entry);

      expect(t.controller.error, contains('Install failed'));
      expect(
        t.registry.installed.map((m) => m.id),
        ['builtin'],
        reason: 'an unverified bundle must never reach the registry',
      );
      expect(t.store.saved, isEmpty, reason: 'nor storage');
      expect(t.controller.busy, isFalse);
    });
  });

  group('uninstall', () {
    test('removes from the registry and from storage', () async {
      final t = build();
      await t.controller.setRepoUrl('$baseUrl/repo.json');
      await t.controller.refresh();
      await t.controller.install(t.controller.listings.single.entry);

      await t.controller.uninstall('remote_ext');

      expect(t.registry.installed.map((m) => m.id), ['builtin']);
      expect(t.store.saved, isEmpty);
      expect(t.controller.listings.single.installedVersion, isNull);
    });

    test('works without a configured repository', () async {
      final t = build();
      t.registry.install(FakeExtension(id: 'remote_ext'));
      await t.store.save(
        const InstalledExtension(
          id: 'remote_ext',
          version: '1.0.0',
          manifestJson: '{}',
          bundleJs: '',
        ),
      );

      await t.controller.uninstall('remote_ext');

      expect(t.registry.installed.map((manifest) => manifest.id), ['builtin']);
      expect(t.store.saved, isEmpty);
      expect(t.controller.error, isNull);
    });
  });

  group('permission consent', () {
    test('a fresh install asks before downloading anything', () async {
      final t = build();
      await t.controller.setRepoUrl('$baseUrl/repo.json');
      await t.controller.refresh();
      await t.controller.install(t.controller.listings.single.entry);

      expect(t.asked, hasLength(1));
      final request = t.asked.single;
      expect(request.isUpdate, isFalse);
      expect(request.entry.id, 'remote_ext');
      expect(request.newHosts, ['cdn.example', 'api.example']);
      expect(request.alreadyGrantedHosts, isEmpty);
    });

    test(
      'declining installs nothing and is not reported as an error',
      () async {
        final t = build(consent: false);
        await t.controller.setRepoUrl('$baseUrl/repo.json');
        await t.controller.refresh();
        await t.controller.install(t.controller.listings.single.entry);

        expect(t.registry.installed.map((m) => m.id), ['builtin']);
        expect(t.store.saved, isEmpty);
        // Declining is a choice, not a failure.
        expect(t.controller.error, isNull);
        expect(t.controller.busy, isFalse);
      },
    );

    test('an extension wanting no hosts still asks, saying so', () async {
      final t = build();
      await t.controller.setRepoUrl('$baseUrl/repo-no-hosts.json');
      await t.controller.refresh();
      await t.controller.install(t.controller.listings.single.entry);

      expect(t.asked.single.newHosts, isEmpty);
      expect(t.registry.installed.map((m) => m.id), contains('remote_ext'));
    });

    test('an update without new hosts still shows update details', () async {
      final t = build();
      await t.controller.setRepoUrl('$baseUrl/repo.json');
      await t.controller.refresh();
      await t.controller.install(t.controller.listings.single.entry);
      expect(t.asked, hasLength(1), reason: 'the first install asked');

      repoVersion = '2.0.0';
      await t.controller.refresh();
      await t.controller.install(t.controller.listings.single.entry);

      expect(
        t.asked,
        hasLength(2),
        reason: 'the second prompt confirms the release, not old permissions',
      );
      expect(t.asked.last.isUpdate, isTrue);
      expect(t.asked.last.installedVersion, '1.0.0');
      expect(t.asked.last.newHosts, isEmpty);
      expect(t.store.saved['remote_ext']!.version, '2.0.0');
    });

    test(
      'an update that wants a new host asks again, showing only the new one',
      () async {
        final t = build();
        await t.controller.setRepoUrl('$baseUrl/repo.json');
        await t.controller.refresh();
        await t.controller.install(t.controller.listings.single.entry);

        // Same extension, next version, one extra host.
        repoVersion = '2.0.0';
        repoHosts = ['cdn.example', 'api.example', 'tracker.example'];
        await t.controller.refresh();
        await t.controller.install(t.controller.listings.single.entry);

        expect(t.asked, hasLength(2));
        final second = t.asked.last;
        expect(second.isUpdate, isTrue);
        expect(second.newHosts, ['tracker.example']);
        expect(second.alreadyGrantedHosts, ['cdn.example', 'api.example']);
      },
    );

    test('declining an update leaves the installed version alone', () async {
      final t = build();
      await t.controller.setRepoUrl('$baseUrl/repo.json');
      await t.controller.refresh();
      await t.controller.install(t.controller.listings.single.entry);
      expect(t.store.saved['remote_ext']!.version, '1.0.0');

      // Rebuild with refusal, reusing the same stores so the install stands.
      final refusing = InstallerController(
        registry: t.registry,
        installer: ExtensionInstaller(),
        installedStore: t.store,
        repoStore: t.repos,
        loadExtension: (manifest, source) => FakeExtension(id: manifest.id),
        requestConsent: (_) async => false,
      );
      repoVersion = '2.0.0';
      repoHosts = ['cdn.example', 'api.example', 'tracker.example'];
      await refusing.setRepoUrl('$baseUrl/repo.json');
      await refusing.refresh();
      await refusing.install(refusing.listings.single.entry);

      expect(
        t.store.saved['remote_ext']!.version,
        '1.0.0',
        reason: 'a refused update must not replace what is installed',
      );
    });

    test(
      'a manifest wanting more than repo.json advertised is refused',
      () async {
        // The check that makes consent mean anything: repo.json's hosts are a
        // preview, but the manifest is what builds the engine allowlist. A repo
        // that understates its hosts to get a friendlier prompt must not win.
        final t = build();
        await t.controller.setRepoUrl('$baseUrl/repo-understates.json');
        await t.controller.refresh();
        await t.controller.install(t.controller.listings.single.entry);

        expect(
          t.asked.single.newHosts,
          ['cdn.example'],
          reason: 'the user was only shown what the repo claimed',
        );
        expect(t.controller.error, contains('did not list'));
        expect(
          t.registry.installed.map((m) => m.id),
          ['builtin'],
          reason: 'never install with more access than was consented to',
        );
        expect(t.store.saved, isEmpty);
      },
    );
  });
}
