import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_app/utils/user_facing_error.dart';

void main() {
  test('maps transport errors without exposing implementation details', () {
    final message = userFacingErrorMessage(
      Exception('DioException [connection error]'),
      resource: 'repository',
    );

    expect(
      message,
      'Could not connect to the repository. Check your connection and URL.',
    );
    expect(message, isNot(contains('DioException')));
  });

  test('uses the resource name in validation errors', () {
    expect(
      userFacingErrorMessage(
        Exception('malformed JSON response'),
        resource: 'catalog',
      ),
      'The catalog format is invalid. Use a valid JSON file.',
    );
  });
}
