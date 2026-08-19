import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_storage/fvcksubs_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('load returns null before anything is saved', () async {
    expect(await SharedPreferencesRepoStore().load(), isNull);
  });

  test('save then load round-trips', () async {
    final store = SharedPreferencesRepoStore();
    await store.save('https://cdn.example/repo.json');
    expect(await store.load(), 'https://cdn.example/repo.json');
  });

  test('the URL is trimmed on the way in', () async {
    final store = SharedPreferencesRepoStore();
    await store.save('  https://cdn.example/repo.json  ');
    expect(await store.load(), 'https://cdn.example/repo.json');
  });

  test('saving null clears it', () async {
    final store = SharedPreferencesRepoStore();
    await store.save('https://cdn.example/repo.json');
    await store.save(null);
    expect(await store.load(), isNull);
  });

  test('saving whitespace clears rather than storing blank', () async {
    final store = SharedPreferencesRepoStore();
    await store.save('https://cdn.example/repo.json');
    await store.save('   ');
    expect(await store.load(), isNull);
  });

  test('a fresh instance reads what an earlier one wrote', () async {
    await SharedPreferencesRepoStore().save('https://cdn.example/repo.json');
    expect(
      await SharedPreferencesRepoStore().load(),
      'https://cdn.example/repo.json',
    );
  });
}
