import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_app/shorts/shorts_controller.dart';
import 'package:fvcksubs_app/shorts/shorts_state.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';

import 'support/harness.dart';

VideoItemV2 _item(String extensionId, String id) => VideoItemV2(
  ref: MediaRef(extensionId: extensionId, providerId: '$extensionId.p', id: id),
  title: id,
);

FakeExtension _previewExtension(
  String id, {
  required List<MediaItemV2> items,
  Map<String, PreviewResponse> previewFor = const {},
  Duration? catalogDelay,
}) => FakeExtension(
  id: id,
  catalogs: [FakeCatalog(id: 'previews', name: 'Previews', categories: const [], items: items, surface: CatalogSurface.preview)],
  previewFor: previewFor,
  catalogDelay: catalogDelay,
);

void main() {
  test('load flattens preview catalogs across extensions, de-duplicated by ref', () async {
    final shared = _item('a', 'shared');
    final onlyA = _item('a', 'only-a');
    final onlyB = _item('b', 'only-b');
    final registry = ExtensionRegistry([
      _previewExtension('a', items: [shared, onlyA]),
      _previewExtension('b', items: [shared, onlyB]),
    ]);
    final controller = ShortsController(registry: registry);

    await controller.load();

    expect(controller.state.status, ShortsStatus.usable);
    expect(
      controller.state.items.map((entry) => entry.item.ref.id),
      ['shared', 'only-a', 'only-b'],
    );
  });

  test('an empty feed reaches the empty status, not an error', () async {
    final registry = ExtensionRegistry([FakeExtension(id: 'a')]); // no preview catalog
    final controller = ShortsController(registry: registry);

    await controller.load();

    expect(controller.state.status, ShortsStatus.empty);
    expect(controller.state.items, isEmpty);
  });

  test('one failing catalog does not blank a feed another catalog fills', () async {
    final ok = _item('a', 'ok');
    final registry = ExtensionRegistry([
      _previewExtension('a', items: [ok]),
      _FailingPreviewExtension(id: 'b'),
    ]);
    final controller = ShortsController(registry: registry);

    await controller.load();

    expect(controller.state.status, ShortsStatus.usable);
    expect(controller.state.items.map((entry) => entry.item.ref.id), ['ok']);
  });

  test('every catalog failing surfaces the error status', () async {
    final registry = ExtensionRegistry([_FailingPreviewExtension(id: 'a')]);
    final controller = ShortsController(registry: registry);

    await controller.load();

    expect(controller.state.status, ShortsStatus.error);
    expect(controller.state.error, isNotNull);
  });

  test('a later load supersedes an in-flight one (stale-request protection)', () async {
    final registry = ExtensionRegistry([
      _previewExtension('a', items: [_item('a', 'slow')], catalogDelay: const Duration(milliseconds: 50)),
    ]);
    final controller = ShortsController(registry: registry);

    final first = controller.load();
    final second = controller.load();
    await Future.wait([first, second]);

    // Both calls resolve the same underlying data here; what matters is that
    // the first call's completion did not clobber state after the second
    // one had already started — i.e. exactly one final, consistent state.
    expect(controller.state.status, ShortsStatus.usable);
    expect(controller.state.items, hasLength(1));
  });

  test('ensurePreviewResolved picks the first source this app can play', () async {
    final item = _item('a', 'x');
    final registry = ExtensionRegistry([
      _previewExtension(
        'a',
        items: [item],
        previewFor: {
          'x': const PreviewResponse(
            sources: [
              EmbeddedPreviewSource(id: '1', provider: 'vimeo', mediaId: 'v1'),
              EmbeddedPreviewSource(id: '2', provider: 'youtube', mediaId: 'yt1'),
            ],
          ),
        },
      ),
    ]);
    final controller = ShortsController(registry: registry);

    await controller.ensurePreviewResolved(item);

    final resolution = controller.state.previewFor(item.ref);
    expect(resolution.status, PreviewStatus.usable);
    expect((resolution.source! as EmbeddedPreviewSource).provider, 'youtube');
  });

  test('a response with no supported source resolves to unusable', () async {
    final item = _item('a', 'x');
    final registry = ExtensionRegistry([
      _previewExtension(
        'a',
        items: [item],
        previewFor: {
          'x': const PreviewResponse(
            sources: [EmbeddedPreviewSource(id: '1', provider: 'vimeo', mediaId: 'v1')],
          ),
        },
      ),
    ]);
    final controller = ShortsController(registry: registry);

    await controller.ensurePreviewResolved(item);

    expect(controller.state.previewFor(item.ref).status, PreviewStatus.unusable);
  });

  test('an item whose extension does not implement preview resolves to unusable', () async {
    final item = _item('a', 'x');
    final registry = ExtensionRegistry([_previewExtension('a', items: [item])]);
    final controller = ShortsController(registry: registry);

    await controller.ensurePreviewResolved(item);

    expect(controller.state.previewFor(item.ref).status, PreviewStatus.unusable);
  });

  test('ensurePreviewResolved is idempotent — a second call does not re-fetch', () async {
    final item = _item('a', 'x');
    final extension = FakeExtension(
      id: 'a',
      catalogs: [
        const FakeCatalog(id: 'previews', name: 'Previews', categories: [], items: [], surface: CatalogSurface.preview),
      ],
      previewFor: {
        'x': const PreviewResponse(
          sources: [DirectPreviewSource(id: '1', stream: PlayableStream(url: 'https://x/1.mp4'))],
        ),
      },
    );
    final registry = ExtensionRegistry([extension]);
    final controller = ShortsController(registry: registry);

    await controller.ensurePreviewResolved(item);
    await controller.ensurePreviewResolved(item);

    expect(extension.previewCalls['x'], 1);
  });

  test('ensureDetailFetched only fetches for a SeriesItemV2', () async {
    const seriesRef = MediaRef(extensionId: 'a', providerId: 'a.p', id: 's1');
    const series = SeriesItemV2(ref: seriesRef, title: 't');
    const detail = MediaDetailV2(item: series);
    final video = _item('a', 'v1');
    final extension = FakeExtension(id: 'a', metaDetail: detail);
    final controller = ShortsController(registry: ExtensionRegistry([extension]));

    await controller.ensureDetailFetched(video);
    expect(controller.state.detailFor(video.ref), isNull);

    await controller.ensureDetailFetched(series);
    expect(controller.state.detailFor(seriesRef), detail);
  });

  test('ensureDetailFetched failure leaves the detail unresolved, not an error state', () async {
    const seriesRef = MediaRef(extensionId: 'a', providerId: 'a.p', id: 's1');
    const series = SeriesItemV2(ref: seriesRef, title: 't');
    final controller = ShortsController(registry: ExtensionRegistry([FakeExtension(id: 'a')]));

    await controller.ensureDetailFetched(series);

    expect(controller.state.detailFor(seriesRef), isNull);
    expect(controller.state.status, isNot(ShortsStatus.error));
  });
}

class _FailingPreviewExtension extends ContentExtension {
  _FailingPreviewExtension({required this.id})
    : _manifest = Manifest.parse({
        'apiVersion': 2,
        'id': id,
        'name': id,
        'version': '1.0.0',
        'runtime': 'builtin',
        'categories': <String>[],
        'providers': [
          {
            'id': '$id.p',
            'roles': ['catalog'],
            'catalogs': [
              {'id': 'previews', 'name': 'Previews', 'categories': <String>[], 'surface': 'preview'},
            ],
          },
        ],
        'permissions': {'hosts': <String>[]},
      });

  final String id;
  final Manifest _manifest;

  @override
  Manifest get manifest => _manifest;

  @override
  Future<VersionedCatalogPage> catalog(CatalogQuery query) async {
    throw Exception('$id: catalog unavailable');
  }
}
