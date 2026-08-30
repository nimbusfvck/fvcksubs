import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_storage/fvcksubs_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const item = VideoItemV2(
    ref: MediaRef(
      extensionId: 'example',
      providerId: 'example.catalog',
      id: 'video-1',
    ),
    title: 'Video',
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('malformed top-level data loads as empty', () async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('library.records.v2', '{not-json');

    expect(await SharedPreferencesLibraryStore().load(), isEmpty);
  });

  test('malformed records are skipped while valid records remain', () async {
    final valid = UserMediaState(item: item, favorite: true);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      'library.records.v2',
      jsonEncode([
        valid.toJson(),
        {'item': 'invalid'},
      ]),
    );

    final loaded = await SharedPreferencesLibraryStore().load();

    expect(loaded, {valid.key: valid});
  });
}
