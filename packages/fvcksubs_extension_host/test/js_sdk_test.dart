@TestOn('vm')
library;

import 'dart:io';

import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';
import 'package:test/test.dart';

void main() {
  final sdk = File('../../sdk/js/fvcksubs.js').readAsStringSync();

  Manifest manifest() => Manifest.parse({
    'apiVersion': 1,
    'id': 'sdk_test',
    'name': 'SDK test',
    'version': '1.0.0',
    'runtime': 'js',
    'categories': ['live'],
    'providers': [
      {
        'id': 'sdk_test.catalog',
        'roles': ['catalog', 'meta'],
        'catalogs': [
          {
            'id': 'main',
            'name': 'Main',
            'categories': ['live'],
            'kind': 'liveEvent',
          },
        ],
      },
      {
        'id': 'sdk_test.good',
        'roles': ['stream'],
      },
      {
        'id': 'sdk_test.bad',
        'roles': ['stream'],
      },
      {
        'id': 'sdk_test.search',
        'roles': ['search'],
      },
      {
        'id': 'sdk_test.subtitles',
        'roles': ['subtitles'],
      },
    ],
    'permissions': {'hosts': <String>[]},
  });

  JsExtension load(String providers) =>
      JsExtension.load(manifest: manifest(), source: '$sdk\n$providers');

  const item = MediaItem(
    ref: MediaRef(
      extensionId: 'sdk_test',
      providerId: 'sdk_test.catalog',
      id: 'event-7',
    ),
    kind: MediaKind.liveEvent,
    title: 'Home vs Away',
  );

  test('catalog and meta route by protocol provider ids', () async {
    final extension = load(r'''
fvcksubs.defineCatalog({
  providerId: 'sdk_test.catalog', catalogId: 'main',
  catalog: (query) => ({ items: [{
    ref: { extensionId: 'sdk_test', providerId: query.providerId, id: '1' },
    kind: 'liveEvent', title: query.catalogId,
  }] }),
});
fvcksubs.defineMeta({
  providerId: 'sdk_test.catalog',
  meta: ({ ref }) => ({ item: { ref, kind: 'liveEvent', title: 'detail ' + ref.id } }),
});
''');
    addTearDown(extension.dispose);

    final page = await extension.catalog(
      const CatalogQuery(providerId: 'sdk_test.catalog', catalogId: 'main'),
    );
    expect(page.items.single.title, 'main');
    expect((await extension.meta(item.ref)).item.title, 'detail event-7');
  });

  test(
    'stream fan-out respects toggles and isolates a failed provider',
    () async {
      final extension = load(r'''
fvcksubs.defineStream({
  providerId: 'sdk_test.bad', providerKey: 'bad',
  sources: () => { throw new Error('upstream down'); },
  resolve: () => { throw new Error('unused'); },
});
fvcksubs.defineStream({
  providerId: 'sdk_test.good', providerKey: 'good',
  sources: ({ item }) => ({ sources: [{
    id: fvcksubs.sourceId('good', { eventId: item.ref.id, quality: 720 }),
    label: 'Good', provider: 'SDK',
  }] }),
  resolve: (sourceId) => {
    const payload = fvcksubs.sourcePayload(sourceId, 'good');
    return { url: 'https://cdn.invalid/' + payload.eventId + '.m3u8', format: 'hls' };
  },
});
''');
      addTearDown(extension.dispose);

      final sources = await extension.sources(
        item,
        enabledProviders: {'sdk_test.good', 'sdk_test.bad'},
      );
      expect(sources, [
        isA<StreamSource>()
            .having((s) => s.label, 'label', 'Good')
            .having((s) => s.providerId, 'providerId', 'sdk_test.good'),
      ]);
      expect(
        (await extension.resolve(sources.single.id)).url,
        contains('event-7.m3u8'),
      );

      expect(
        await extension.sources(item, enabledProviders: {'sdk_test.bad'}),
        isEmpty,
      );
    },
  );

  test('search and subtitle fan-out accept synchronous providers', () async {
    final extension = load(r'''
fvcksubs.defineSearch({
  providerId: 'sdk_test.search',
  search: ({ query, page }) => ({
    items: [{
      ref: { extensionId: 'sdk_test', providerId: 'sdk_test.catalog', id: query },
      kind: 'liveEvent', title: query + ':' + (page || 'first'),
    }],
    nextPage: page ? undefined : 'second',
  }),
});
fvcksubs.defineSubtitles({
  providerId: 'sdk_test.subtitles',
  subtitles: ({ item }) => ({ subtitles: [
    { language: 'id', url: 'https://sub.invalid/' + item.ref.id + '.vtt' },
  ] }),
});
''');
    addTearDown(extension.dispose);

    final first = await extension.search('aew');
    expect(first.items.single.title, 'aew:first');
    expect(first.nextPage, isNotNull);
    final second = await extension.search('aew', page: first.nextPage);
    expect(second.items.single.title, 'aew:second');

    final tracks = await extension.externalSubtitles(item);
    expect(tracks.single.url, 'https://sub.invalid/event-7.vtt');
  });

  test('duplicate stream keys fail while the bundle loads', () {
    expect(
      () => load(r'''
const stream = { sources: () => ({ sources: [] }), resolve: () => ({ url: 'x' }) };
fvcksubs.defineStream({ providerId: 'sdk_test.good', providerKey: 'same', ...stream });
fvcksubs.defineStream({ providerId: 'sdk_test.bad', providerKey: 'same', ...stream });
'''),
      throwsA(isA<JsExtensionException>()),
    );
  });
}
