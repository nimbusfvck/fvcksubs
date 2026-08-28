@TestOn('vm')
library;

import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';
import 'package:test/test.dart';

/// Preview is the one optional role the host must probe for before calling —
/// most bundles (every one written before Shorts existed) never define it at
/// all, and that must not look like a broken extension.
void main() {
  final manifest = Manifest.parse({
    'apiVersion': 2,
    'id': 'previewy',
    'name': 'previewy',
    'version': '1.0.0',
    'runtime': 'js',
    'categories': ['movie'],
    'providers': [
      {
        'id': 'previewy.p',
        'roles': ['catalog'],
      },
    ],
    'permissions': {'hosts': <String>[]},
  });

  final item = VideoItemV2(
    ref: const MediaRef(
      extensionId: 'previewy',
      providerId: 'previewy.p',
      id: 'movie-1',
    ),
    title: 'Some Movie',
  );

  JsExtension load(String bundle) =>
      JsExtension.load(manifest: manifest, source: bundle);

  test('an embedded YouTube source decodes correctly', () async {
    final extension = load('''
globalThis.__extension = {
  async preview(args) {
    return { sources: [{ id: "yt:abc", type: "embedded", provider: "youtube", mediaId: "abc" }] };
  },
};
''');
    addTearDown(extension.dispose);

    final response = await extension.preview(item);

    expect(response.sources, hasLength(1));
    final source = response.sources.single as EmbeddedPreviewSource;
    expect(source.provider, 'youtube');
    expect(source.mediaId, 'abc');
  });

  test('a direct PlayableStream source decodes correctly', () async {
    final extension = load('''
globalThis.__extension = {
  async preview(args) {
    return { sources: [{
      id: "direct:1",
      type: "direct",
      stream: { url: "https://cdn.example.com/preview.mp4", format: "other" },
    }] };
  },
};
''');
    addTearDown(extension.dispose);

    final response = await extension.preview(item);

    expect(response.sources, hasLength(1));
    final source = response.sources.single as DirectPreviewSource;
    expect(source.stream.url, 'https://cdn.example.com/preview.mp4');
  });

  test('a bundle with no preview defined still loads, and calling it throws', () async {
    final extension = load('''
globalThis.__extension = {
  async catalog(query) {
    return { sections: [] };
  },
};
''');
    addTearDown(extension.dispose);

    expect(() => extension.preview(item), throwsA(isA<UnsupportedError>()));
  });

  test('a malformed result (missing "sources") throws', () async {
    final extension = load('''
globalThis.__extension = {
  async preview(args) {
    return { notSources: [] };
  },
};
''');
    addTearDown(extension.dispose);

    expect(() => extension.preview(item), throwsA(isA<JsExtensionException>()));
  });

  test('an unrecognized embedded provider still decodes', () async {
    final extension = load('''
globalThis.__extension = {
  async preview(args) {
    return { sources: [{ id: "vimeo:1", type: "embedded", provider: "vimeo", mediaId: "12345" }] };
  },
};
''');
    addTearDown(extension.dispose);

    final response = await extension.preview(item);

    final source = response.sources.single as EmbeddedPreviewSource;
    expect(source.provider, 'vimeo');
  });

  test('an empty sources list means no usable preview', () async {
    final extension = load('''
globalThis.__extension = {
  async preview(args) {
    return { sources: [] };
  },
};
''');
    addTearDown(extension.dispose);

    final response = await extension.preview(item);

    expect(response.sources, isEmpty);
  });
}
