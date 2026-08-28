import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:test/test.dart';

import '../support/round_trip.dart';

void main() {
  test('EmbeddedPreviewSource round-trips', () {
    const source = EmbeddedPreviewSource(
      id: 'yt:dQw4w9WgXcQ',
      provider: 'youtube',
      mediaId: 'dQw4w9WgXcQ',
    );
    expectRoundTrips(
      source,
      toJson: (s) => s.toJson(),
      fromJson: PreviewSource.fromJson,
    );
  });

  test('DirectPreviewSource round-trips', () {
    const source = DirectPreviewSource(
      id: 'direct:1',
      stream: PlayableStream(
        url: 'https://cdn.example.com/trailer.mp4',
        format: StreamFormat.other,
      ),
    );
    expectRoundTrips(
      source,
      toJson: (s) => s.toJson(),
      fromJson: PreviewSource.fromJson,
    );
  });

  test('PreviewResponse with mixed sources round-trips', () {
    const response = PreviewResponse(
      sources: [
        EmbeddedPreviewSource(
          id: 'yt:abc',
          provider: 'youtube',
          mediaId: 'abc',
        ),
        DirectPreviewSource(
          id: 'direct:1',
          stream: PlayableStream(url: 'https://cdn.example.com/a.m3u8'),
        ),
      ],
    );
    expectRoundTrips(
      response,
      toJson: (r) => r.toJson(),
      fromJson: PreviewResponse.fromJson,
    );
  });

  test('an empty PreviewResponse round-trips', () {
    const response = PreviewResponse();
    expectRoundTrips(
      response,
      toJson: (r) => r.toJson(),
      fromJson: PreviewResponse.fromJson,
    );
    expect(response.sources, isEmpty);
  });

  test('an unrecognized embedded provider still decodes', () {
    final source = PreviewSource.fromJson({
      'id': 'vimeo:1',
      'type': 'embedded',
      'provider': 'vimeo',
      'mediaId': '12345',
    });
    expect(source, isA<EmbeddedPreviewSource>());
    expect((source as EmbeddedPreviewSource).provider, 'vimeo');
  });

  test('an unrecognized source type throws', () {
    expect(
      () => PreviewSource.fromJson({'id': 'x', 'type': 'iframe'}),
      throwsFormatException,
    );
  });

  test('a source without an id throws', () {
    expect(
      () => PreviewSource.fromJson({
        'type': 'embedded',
        'provider': 'youtube',
        'mediaId': 'abc',
      }),
      throwsFormatException,
    );
  });

  test('an embedded source missing mediaId throws', () {
    expect(
      () => PreviewSource.fromJson({
        'id': 'yt:abc',
        'type': 'embedded',
        'provider': 'youtube',
      }),
      throwsFormatException,
    );
  });

  test('a direct source missing stream throws', () {
    expect(
      () => PreviewSource.fromJson({'id': 'direct:1', 'type': 'direct'}),
      throwsFormatException,
    );
  });

  test('a preview response whose sources is not a list throws', () {
    expect(
      () => PreviewResponse.fromJson({'sources': 'nope'}),
      throwsFormatException,
    );
  });
}
