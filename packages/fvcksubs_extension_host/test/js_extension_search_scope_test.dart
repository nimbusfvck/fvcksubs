@TestOn('vm')
library;

import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';
import 'package:test/test.dart';

/// The search scope has to survive the trip into JS: a bundle that fans out
/// internally routes on it, so an argument silently dropped at the boundary
/// would look exactly like a provider with nothing to say.
void main() {
  final manifest = Manifest.parse({
    'apiVersion': 2,
    'id': 'scoped',
    'name': 'scoped',
    'version': '1.0.0',
    'runtime': 'js',
    'categories': ['anime'],
    'providers': [
      {
        'id': 'scoped.p',
        'roles': ['search'],
        'searchCategories': ['anime'],
      },
    ],
    'permissions': {'hosts': <String>[]},
  });

  /// Echoes back what the host passed, as the title of a single result.
  const bundle = '''
globalThis.__extension = {
  async search(args) {
    return { sections: [{ id: "main", items: [{
      ref: { extensionId: "scoped", providerId: "scoped.p", id: "echo" },
      kind: "video",
      title: `\${args.query}|\${"category" in args ? args.category : "<absent>"}`,
    }] }] };
  },
};
''';

  late JsExtension extension;

  setUp(() => extension = JsExtension.load(manifest: manifest, source: bundle));
  tearDown(() => extension.dispose());

  Future<String> echo({String? category}) async {
    final page = await extension.search('one piece', category: category);
    return page.items.single.item.title;
  }

  test('the chosen scope reaches the bundle', () async {
    expect(await echo(category: 'anime'), 'one piece|anime');
  });

  test('an unscoped search passes no scope at all', () async {
    // Absent, not null: a bundle written before scopes existed branches on
    // the key being there, and must keep behaving as it always did.
    expect(await echo(), 'one piece|<absent>');
  });
}
