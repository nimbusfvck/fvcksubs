import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_storage/fvcksubs_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('source priority defaults empty and round-trips provider ids', () async {
    const store = SharedPreferencesSourcePriorityStore();

    expect(await store.load(), isEmpty);
    await store.save(['nimora.cricfy', 'nimora.kora']);

    expect(await store.load(), ['nimora.cricfy', 'nimora.kora']);
  });
}
