import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:test/test.dart';

void main() {
  test('provider locale metadata round-trips', () {
    const provider = ProviderDecl(
      id: 'nimora.example',
      roles: [ProviderRole.stream],
      name: 'Example',
      locales: ProviderLocales(countries: ['ID'], languages: ['id']),
    );

    final decoded = ProviderDecl.fromJson(provider.toJson());
    expect(decoded.locales.countries, ['ID']);
    expect(decoded.locales.languages, ['id']);
  });

  test('provider locale metadata is optional for older manifests', () {
    final provider = ProviderDecl.fromJson({
      'id': 'legacy.example',
      'roles': ['stream'],
    });

    expect(provider.locales, const ProviderLocales());
    expect(provider.toJson().containsKey('locales'), isFalse);
  });
}
