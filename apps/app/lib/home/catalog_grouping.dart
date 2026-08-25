import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';

/// A group of Home catalogs that share the same content family.
class HomeCatalogGroup {
  const HomeCatalogGroup({required this.title, required this.options});

  final String title;
  final List<HomeCatalogOption> options;
}

class HomeCatalogOption {
  const HomeCatalogOption({required this.binding, required this.label});

  final CatalogBinding binding;
  final String label;
}

class HomeSectionGroup {
  const HomeSectionGroup({required this.title, required this.options});

  final String title;
  final List<HomeSectionOption> options;
}

class HomeSectionOption {
  const HomeSectionOption({required this.section, required this.label});

  final CatalogSectionV2 section;
  final String label;
}

/// Groups catalog names such as "Movies on Netflix" and "Movies on Hulu".
///
/// The shell only groups a family when at least two catalogs use the same
/// `content on service` shape. A lone catalog keeps its original title and
/// remains indistinguishable from the existing Home shelf.
List<HomeCatalogGroup> groupHomeCatalogs(List<CatalogBinding> bindings) {
  final groups = <String, List<HomeCatalogOption>>{};
  final titles = <String, String>{};
  final order = <String>[];

  for (var index = 0; index < bindings.length; index++) {
    final binding = bindings[index];
    final parsed = _parseCatalogName(binding.catalog.name);
    final key = parsed == null
        ? 'single:$index'
        : 'family:${parsed.title.toLowerCase()}';
    if (!groups.containsKey(key)) {
      groups[key] = [];
      order.add(key);
    }
    groups[key]!.add(
      HomeCatalogOption(
        binding: binding,
        label: parsed?.service ?? binding.catalog.name,
      ),
    );
    titles[key] = parsed?.title ?? binding.catalog.name;
  }

  return [
    for (final key in order)
      HomeCatalogGroup(title: titles[key]!, options: groups[key]!),
  ];
}

/// Groups response sections such as "Movies on Netflix" and
/// "Movies on Apple TV" inside one catalog response.
List<HomeSectionGroup> groupHomeSections(List<CatalogSectionV2> sections) {
  final groups = <String, List<HomeSectionOption>>{};
  final titles = <String, String>{};
  final order = <String>[];

  for (var index = 0; index < sections.length; index++) {
    final section = sections[index];
    final parsed = section.title == null
        ? null
        : _parseCatalogName(section.title!);
    final key = parsed == null
        ? 'single:$index'
        : 'family:${parsed.title.toLowerCase()}';
    if (!groups.containsKey(key)) {
      groups[key] = [];
      order.add(key);
    }
    groups[key]!.add(
      HomeSectionOption(
        section: section,
        label: parsed?.service ?? section.title ?? '',
      ),
    );
    titles[key] = parsed?.title ?? section.title ?? '';
  }

  return [
    for (final key in order)
      HomeSectionGroup(title: titles[key]!, options: groups[key]!),
  ];
}

({String title, String service})? _parseCatalogName(String name) {
  final match = RegExp(
    r'^(.+?)\s+on\s+(.+)$',
    caseSensitive: false,
  ).firstMatch(name.trim());
  if (match == null) return null;
  final title = match.group(1)!.trim();
  final service = match.group(2)!.trim();
  if (title.isEmpty || service.isEmpty) return null;
  return (title: title, service: service);
}
