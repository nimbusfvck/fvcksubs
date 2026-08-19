import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_storage/fvcksubs_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  InstalledExtension fixture({
    String id = 'example_extension',
    String version = '0.1.0',
  }) => InstalledExtension(
    id: id,
    version: version,
    manifestJson: '{"id":"$id"}',
    bundleJs: 'globalThis.__extension = {};',
  );

  test('loadAll returns empty before anything is saved', () async {
    final store = SharedPreferencesInstalledExtensionStore();
    expect(await store.loadAll(), isEmpty);
  });

  test('save then loadAll round-trips', () async {
    final store = SharedPreferencesInstalledExtensionStore();
    await store.save(fixture());

    final all = await store.loadAll();
    expect(all.keys, ['example_extension']);
    expect(all['example_extension'], fixture());
  });

  test('saving again with the same id replaces, not duplicates', () async {
    final store = SharedPreferencesInstalledExtensionStore();
    await store.save(fixture(version: '0.1.0'));
    await store.save(fixture(version: '0.2.0'));

    final all = await store.loadAll();
    expect(all, hasLength(1));
    expect(all['example_extension']!.version, '0.2.0');
  });

  test('two different extensions coexist', () async {
    final store = SharedPreferencesInstalledExtensionStore();
    await store.save(fixture(id: 'a'));
    await store.save(fixture(id: 'b'));

    final all = await store.loadAll();
    expect(all.keys.toSet(), {'a', 'b'});
  });

  test('remove drops one extension, leaves the others', () async {
    final store = SharedPreferencesInstalledExtensionStore();
    await store.save(fixture(id: 'a'));
    await store.save(fixture(id: 'b'));
    await store.remove('a');

    final all = await store.loadAll();
    expect(all.keys, ['b']);
  });

  test(
    'removing an id that was never saved is a no-op, not an error',
    () async {
      final store = SharedPreferencesInstalledExtensionStore();
      await store.save(fixture(id: 'a'));
      await store.remove('does-not-exist');

      expect(await store.loadAll(), hasLength(1));
    },
  );

  test(
    'a store instance persists across two loadAll calls (real backing)',
    () async {
      final writer = SharedPreferencesInstalledExtensionStore();
      await writer.save(fixture());

      // A fresh instance reads the same SharedPreferences-backed data — this
      // is the actual persistence contract, not just in-memory state on one
      // object.
      final reader = SharedPreferencesInstalledExtensionStore();
      expect(await reader.loadAll(), {'example_extension': fixture()});
    },
  );
}
