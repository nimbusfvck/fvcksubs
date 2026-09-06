import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_app/player/data/subtitle_translate_service.dart';

void main() {
  test('joins translated segments from the Google response', () {
    const body = '[[["Halo ","Hello",null],["dunia","world",null]],null]';

    expect(SubtitleTranslateService.parseTranslatedBody(body), 'Halo dunia');
  });

  test('rejects an HTML rate-limit response', () {
    expect(
      SubtitleTranslateService.parseTranslatedBody('<html>blocked</html>'),
      isNull,
    );
  });

  test('reads a Lingva REST response and rejects API errors', () {
    expect(
      SubtitleTranslateService.parseLingvaBody(
        '{"translation":"Halo dunia","info":{}}',
      ),
      'Halo dunia',
    );
    expect(
      SubtitleTranslateService.parseLingvaBody('{"error":"rate limited"}'),
      isNull,
    );
  });

  test('reads a MyMemory fallback response and rejects API errors', () {
    expect(
      SubtitleTranslateService.parseMyMemoryBody(
        '{"responseData":{"translatedText":"Halo dunia"},'
        '"responseStatus":200}',
      ),
      'Halo dunia',
    );
    expect(
      SubtitleTranslateService.parseMyMemoryBody(
        '{"responseData":{"translatedText":"quota"},'
        '"responseStatus":403}',
      ),
      isNull,
    );
  });
}
