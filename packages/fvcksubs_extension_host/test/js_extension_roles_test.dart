@TestOn('vm')
library;

import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';
import 'package:test/test.dart';

/// The roles beyond `catalog`, driven from JS.
///
/// The protocol types decode the same way whichever runtime produced them —
/// `StreamSource.fromJson`, `PlayableStream.fromJson` — so a JS extension
/// needs no bespoke decoding path. These check the plumbing carries each
/// role's shape intact, including the ones with real consequences
/// (`enabledProviders` reaching the bundle, DRM surviving the crossing).
void main() {
  Manifest manifestWith(List<String> roles, {int apiVersion = 1}) =>
      Manifest.parse({
        'apiVersion': apiVersion,
        'id': 'roles',
        'name': 'roles',
        'version': '1.0.0',
        'runtime': 'js',
        'categories': ['live'],
        'providers': [
          {
            'id': 'roles.p',
            'roles': roles,
            if (roles.contains('catalog'))
              'catalogs': [
                {
                  'id': 'c',
                  'name': 'C',
                  'category': 'live',
                  'kind': 'liveEvent',
                },
              ],
          },
        ],
        'permissions': {'hosts': <String>[]},
      });

  MediaItem item() => const MediaItem(
    ref: MediaRef(extensionId: 'roles', providerId: 'roles.p', id: '7'),
    kind: MediaKind.liveEvent,
    title: 'Home vs Away',
    participants: [
      Participant(name: 'Home'),
      Participant(name: 'Away'),
    ],
  );

  JsExtension load(
    String bundle, {
    List<String> roles = const ['stream'],
    int apiVersion = 1,
  }) => JsExtension.load(
    manifest: manifestWith(roles, apiVersion: apiVersion),
    source: bundle,
  );

  final itemV2 = EventItemV2(
    ref: const MediaRef(extensionId: 'roles', providerId: 'roles.p', id: 'v2'),
    title: 'V2 event',
    schedule: Schedule(startsAt: DateTime.utc(2026, 8, 19)),
  );

  test('catalogVersioned decodes with the manifest apiVersion', () async {
    final extension = load(
      '''
globalThis.__extension = {
  async catalog() {
    return {
      items: [{
        ref: { extensionId: "roles", providerId: "roles.p", id: "event-1" },
        kind: "liveEvent",
        title: "Scheduled event",
        startsAt: "2026-08-20T10:00:00Z",
        group: "Featured"
      }]
    };
  }
};
''',
      roles: ['catalog'],
    );
    addTearDown(extension.dispose);

    final page = await extension.catalogVersioned(
      const CatalogQuery(providerId: 'roles.p', catalogId: 'c'),
    );

    expect(page.sections.single.title, 'Featured');
    expect(page.items.single.item, isA<EventItemV2>());
    expect(page.items.single.requiresLegacyRequest, isTrue);
  });

  test('sources: the whole item and the enabled set reach the bundle', () {
    final extension = load('''
globalThis.__extension = {
  async sources(args) {
    return {
      sources: [
        {
          id: "s1",
          label: args.item.title + " / " + args.item.participants.length,
          provider: (args.enabledProviders || []).join(","),
        },
      ],
    };
  },
};
''');
    addTearDown(extension.dispose);

    expect(
      extension.sources(item(), enabledProviders: {'roles.a', 'roles.b'}),
      completion(
        equals(const [
          StreamSource(
            id: 's1',
            label: 'Home vs Away / 2',
            provider: 'roles.a,roles.b',
          ),
        ]),
      ),
    );
  });

  test('sources: a null enabled set is absent, not an empty list', () async {
    // The protocol distinguishes them: null means "no toggle exists yet, use
    // everything", empty means "everything is switched off".
    final extension = load('''
globalThis.__extension = {
  async sources(args) {
    return {
      sources: [{ id: "s", label: String(args.enabledProviders === undefined) }],
    };
  },
};
''');
    addTearDown(extension.dispose);

    final sources = await extension.sources(item());
    expect(sources.single.label, 'true');

    final withEmpty = await extension.sources(item(), enabledProviders: {});
    expect(withEmpty.single.label, 'false');
  });

  test('resolve: a stream with DRM survives the crossing', () {
    final extension = load('''
globalThis.__extension = {
  async resolve(args) {
    return {
      url: "https://cdn.example/" + args.sourceId + ".mpd",
      format: "dash",
      headers: { Referer: "https://example" },
      drm: { scheme: "clearKey", clearKeyJson: '{"keys":[]}' },
    };
  },
};
''');
    addTearDown(extension.dispose);

    expect(
      extension.resolve('abc'),
      completion(
        isA<PlayableStream>()
            .having((s) => s.url, 'url', 'https://cdn.example/abc.mpd')
            .having((s) => s.format, 'format', StreamFormat.dash)
            .having((s) => s.headers['Referer'], 'header', 'https://example')
            .having((s) => s.drm?.scheme, 'drm', DrmScheme.clearKey),
      ),
    );
  });

  test('search and meta cross intact', () async {
    final extension = load(
      '''
globalThis.__extension = {
  async search(args) {
    return {
      items: [{
        ref: { extensionId: "roles", providerId: "roles.p", id: args.query },
        kind: "liveEvent",
        title: "hit for " + args.query,
      }],
    };
  },
  async meta(args) {
    return {
      item: {
        ref: args.ref,
        kind: "liveEvent",
        title: "detail " + args.ref.id,
      },
      description: "about it",
    };
  },
};
''',
      roles: ['search', 'meta'],
    );
    addTearDown(extension.dispose);

    final page = await extension.search('sochi');
    expect(page.items.single.title, 'hit for sochi');

    final detail = await extension.meta(
      const MediaRef(extensionId: 'roles', providerId: 'roles.p', id: '9'),
    );
    expect(detail.item.title, 'detail 9');
    expect(detail.description, 'about it');
  });

  test('externalSubtitles: the whole item reaches the bundle', () async {
    final extension = load(
      '''
globalThis.__extension = {
  async subtitles(args) {
    return {
      subtitles: [
        { language: "id", url: "https://x/" + args.item.ref.id + ".srt", label: "Indonesian" },
      ],
    };
  },
};
''',
      roles: ['subtitles'],
    );
    addTearDown(extension.dispose);

    final tracks = await extension.externalSubtitles(item());
    expect(tracks, [
      isA<SubtitleTrack>()
          .having((t) => t.language, 'language', 'id')
          .having((t) => t.url, 'url', 'https://x/7.srt')
          .having((t) => t.label, 'label', 'Indonesian'),
    ]);
  });

  test('protocol v2 detail, sources, and subtitles cross intact', () async {
    final extension = load(
      '''
globalThis.__extension = {
  async meta(args) {
    return {
      item: { ref: args.ref, kind: "video", title: "V2 detail" },
      facts: [{ label: "Year", value: "2026" }]
    };
  },
  async sources(args) {
    return { sources: [{ id: "v2-source", label: args.item.kind }] };
  },
  async subtitles(args) {
    return { subtitles: [{ language: "en", url: "https://x/" + args.item.kind + ".vtt" }] };
  }
};
''',
      roles: ['meta', 'stream', 'subtitles'],
      apiVersion: 2,
    );
    addTearDown(extension.dispose);

    final detail = await extension.metaV2(itemV2.ref);
    expect(detail.item, isA<VideoItemV2>());
    expect(detail.facts.single.value, '2026');
    expect((await extension.sourcesV2(itemV2)).single.label, 'event');
    expect(
      (await extension.externalSubtitlesV2(itemV2)).single.url,
      'https://x/event.vtt',
    );
  });

  test('a role returning the wrong shape fails loudly', () {
    final extension = load('''
globalThis.__extension = { async sources(args) { return { nope: 1 }; } };
''');
    addTearDown(extension.dispose);

    expect(
      extension.sources(item()),
      throwsA(
        isA<JsExtensionException>().having(
          (e) => e.message,
          'message',
          contains('did not return a "sources" list'),
        ),
      ),
    );
  });

  test('a role the bundle never defined fails, rather than hanging', () {
    final extension = load('globalThis.__extension = {};');
    addTearDown(extension.dispose);

    expect(extension.resolve('x'), throwsA(isA<JsExtensionException>()));
  });
}
