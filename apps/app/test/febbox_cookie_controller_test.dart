import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_app/settings/febbox_cookie_controller.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';

class _FakeFebboxCookieStore implements FebboxCookieStore {
  String? value;
  var writes = 0;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String? value) async {
    writes++;
    this.value = value;
  }
}

void main() {
  test('normalizes a copied ui cookie without retaining other pairs', () {
    expect(
      normalizeFebboxCookie('  ui=private-value; other=discarded  '),
      'private-value',
    );
    expect(normalizeFebboxCookie('private-value'), 'private-value');
    expect(normalizeFebboxCookie('   '), isNull);
  });

  test('save and clear update secure store and reload callback', () async {
    final store = _FakeFebboxCookieStore();
    final changes = <String?>[];
    final controller = FebboxCookieController(
      store: store,
      onChanged: (value) async => changes.add(value),
    );

    expect(await controller.save('ui=first-value'), isTrue);
    expect(store.value, 'first-value');
    expect(controller.cookie, 'first-value');
    expect(changes, ['first-value']);

    expect(await controller.clear(), isTrue);
    expect(store.value, isNull);
    expect(controller.hasCookie, isFalse);
    expect(changes, ['first-value', null]);
    expect(store.writes, 2);
  });

  test('rejects a multiline value without writing it', () async {
    final store = _FakeFebboxCookieStore();
    final controller = FebboxCookieController(store: store);

    expect(await controller.save('first\nsecond'), isFalse);
    expect(store.writes, 0);
    expect(controller.error, 'Cookie must be a single line.');
  });

  test('prelude targets the Nimora extension, not unrelated extensions', () {
    final nimora = Manifest.parse({
      'apiVersion': 2,
      'id': 'nimora',
      'name': 'Nimora',
      'version': '1.0.0',
      'runtime': 'js',
      'entry': 'bundle.js',
      'providers': [
        {
          'id': 'nimora.showbox',
          'roles': ['stream'],
        },
      ],
      'permissions': {
        'hosts': <String>['example.test'],
      },
    });
    final unrelated = Manifest.parse({
      'apiVersion': 2,
      'id': 'other',
      'name': 'Other',
      'version': '1.0.0',
      'runtime': 'js',
      'entry': 'bundle.js',
      'providers': [
        {
          'id': 'other.streams',
          'roles': ['stream'],
        },
      ],
      'permissions': {
        'hosts': <String>['example.test'],
      },
    });

    expect(
      febboxExtensionPrelude(nimora, 'test-cookie'),
      contains('__showboxUiCookie'),
    );
    expect(febboxExtensionPrelude(unrelated, 'test-cookie'), isEmpty);
  });
}
