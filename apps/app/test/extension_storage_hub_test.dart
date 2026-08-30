import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_app/addons/extension_storage_hub.dart';

/// An [ExtensionStorageStore] that keeps rows in memory and counts writes,
/// standing in for sembast so these tests need no disk.
class FakeExtensionStorageStore implements ExtensionStorageStore {
  final Map<String, Map<String, Object?>> rows = {};
  int writes = 0;

  @override
  Future<Map<String, Map<String, Object?>>> loadAll() async => {...rows};

  @override
  Future<void> write(String extensionId, Map<String, Object?> snapshot) async {
    writes++;
    rows[extensionId] = snapshot;
  }

  @override
  Future<void> remove(String extensionId) async => rows.remove(extensionId);
}

void main() {
  test('a written value survives into the next hub, like a restart', () async {
    final store = FakeExtensionStorageStore();
    ExtensionStorageHub(store: store)
        .forExtension('nimora')
        .write('events', '[1,2]');
    await pumpEventQueue();

    final next = ExtensionStorageHub(store: store, initial: await store.loadAll());
    expect(next.forExtension('nimora').read('events'), '[1,2]');
  });

  test('extensions cannot read each other\'s keys', () async {
    final store = FakeExtensionStorageStore();
    final hub = ExtensionStorageHub(store: store);
    hub.forExtension('nimora').write('events', 'mine');
    await pumpEventQueue();

    expect(hub.forExtension('other').read('events'), isNull);
    // ...and one extension's write leaves no row behind for the other.
    expect(store.rows.keys, ['nimora']);
  });

  test('the same extension always gets the same store', () {
    final hub = ExtensionStorageHub(store: FakeExtensionStorageStore());
    hub.forExtension('nimora').write('k', 'v');
    expect(hub.forExtension('nimora').read('k'), 'v');
  });

  test('several writes in a row are flushed once', () async {
    final store = FakeExtensionStorageStore();
    final storage = ExtensionStorageHub(store: store).forExtension('nimora');
    storage.write('a', '1');
    storage.write('b', '2');
    storage.write('c', '3');
    await pumpEventQueue();

    expect(store.writes, 1);
    expect((store.rows['nimora'] ?? const {}).keys, ['a', 'b', 'c']);
  });

  test('an expired value does not come back after a restart', () async {
    final store = FakeExtensionStorageStore();
    ExtensionStorageHub(store: store)
        .forExtension('nimora')
        .write('events', 'stale', ttl: const Duration(milliseconds: 30));
    await Future<void>.delayed(const Duration(milliseconds: 60));

    final next = ExtensionStorageHub(store: store, initial: await store.loadAll());
    expect(next.forExtension('nimora').read('events'), isNull);
  });

  test('uninstalling forgets the extension\'s cache', () async {
    final store = FakeExtensionStorageStore();
    final hub = ExtensionStorageHub(store: store);
    hub.forExtension('nimora').write('events', 'mine');
    await pumpEventQueue();

    await hub.remove('nimora');
    expect(store.rows, isEmpty);
    expect(hub.forExtension('nimora').read('events'), isNull);
  });

  test('with no store at all, storage still works for the session', () async {
    final hub = ExtensionStorageHub();
    hub.forExtension('nimora').write('k', 'v');
    await pumpEventQueue();
    expect(hub.forExtension('nimora').read('k'), 'v');
  });
}
