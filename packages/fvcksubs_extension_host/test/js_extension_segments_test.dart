@TestOn('vm')
library;

import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';
import 'package:test/test.dart';

void main() {
  final manifest = Manifest.parse({
    'apiVersion': 2,
    'id': 'segments',
    'name': 'segments',
    'version': '1.0.0',
    'runtime': 'js',
    'categories': ['anime'],
    'providers': [
      {
        'id': 'segments.p',
        'roles': ['segments'],
      },
    ],
    'permissions': {'hosts': <String>[]},
  });

  const bundle = '''
globalThis.__extension = {
  async segments(args) {
    return { segments: [{ type: "intro", startMs: 42000, endMs: 128500 }] };
  },
};
''';

  test('segments role crosses the JS boundary', () async {
    final extension = JsExtension.load(manifest: manifest, source: bundle);
    addTearDown(extension.dispose);

    const item = EpisodeItemV2(
      ref: MediaRef(
        extensionId: 'segments',
        providerId: 'segments.p',
        id: 'e1',
      ),
      title: 'Episode',
      episode: EpisodeIdentity(
        parentRef: MediaRef(
          extensionId: 'segments',
          providerId: 'segments.p',
          id: 's1',
        ),
        groupId: 'season:1',
        position: 1,
      ),
    );

    expect(await extension.playbackSegments(item), const [
      PlaybackSegment(
        type: PlaybackSegmentType.intro,
        startMs: 42000,
        endMs: 128500,
      ),
    ]);
  });
}
