import 'package:equatable/equatable.dart';

import '../content/media_item_version_adapter.dart';
import 'catalog.dart' show SubCategory;

/// An explicit catalog section in protocol version 2.
class CatalogSectionV2 extends Equatable {
  /// Creates a section.
  const CatalogSectionV2({required this.id, required this.items, this.title});

  /// Decodes a section and its version-2 items.
  factory CatalogSectionV2.fromJson(Map<String, Object?> json) {
    _expectKeys(json, const {'id', 'title', 'items'}, 'catalog section');
    final id = json['id'];
    final title = json['title'];
    final items = json['items'];
    if (id is! String || id.isEmpty) {
      throw const FormatException('catalog section.id must be non-empty');
    }
    if (title != null && title is! String) {
      throw const FormatException('catalog section.title must be a string');
    }
    if (items is! List) {
      throw const FormatException('catalog section.items must be a list');
    }
    return CatalogSectionV2(
      id: id,
      title: title as String?,
      items: [
        for (final item in items)
          VersionedMediaItem.fromProtocolJson(
            (item as Map).cast<String, Object?>(),
            apiVersion: 2,
          ),
      ],
    );
  }

  /// Stable section ID owned by the extension.
  final String id;

  /// Optional section heading.
  final String? title;

  /// Items in display order.
  final List<VersionedMediaItem> items;

  /// Encodes this section.
  Map<String, Object?> toJson() => {
    'id': id,
    if (title != null) 'title': title,
    'items': items.map((value) => value.item.toJson()).toList(),
  };

  @override
  List<Object?> get props => [id, title, items];
}

/// Catalog page normalized into the protocol-version-2 shape.
class VersionedCatalogPage extends Equatable {
  /// Creates a normalized page.
  const VersionedCatalogPage({
    required this.sections,
    this.nextPage,
    this.subCategories = const [],
  });

  /// Decodes a page according to the extension's declared API version.
  factory VersionedCatalogPage.fromProtocolJson(
    Map<String, Object?> json, {
    required int apiVersion,
  }) {
    if (apiVersion != 2) {
      throw FormatException('Unsupported catalog apiVersion: $apiVersion');
    }
    return VersionedCatalogPage._fromV2Json(json);
  }

  factory VersionedCatalogPage._fromV2Json(Map<String, Object?> json) {
    _expectKeys(json, const {
      'sections',
      'nextPage',
      'subCategories',
    }, 'catalog page');
    final sections = json['sections'];
    final nextPage = json['nextPage'];
    final subCategories = json['subCategories'];
    if (sections is! List) {
      throw const FormatException('catalog page.sections must be a list');
    }
    if (nextPage != null && nextPage is! String) {
      throw const FormatException('catalog page.nextPage must be a string');
    }
    if (subCategories != null && subCategories is! List) {
      throw const FormatException('catalog page.subCategories must be a list');
    }
    return VersionedCatalogPage(
      sections: [
        for (final section in sections)
          CatalogSectionV2.fromJson((section as Map).cast<String, Object?>()),
      ],
      nextPage: nextPage as String?,
      subCategories: [
        for (final value in (subCategories as List?) ?? const [])
          SubCategory.fromJson((value as Map).cast<String, Object?>()),
      ],
    );
  }

  /// Sections in display order.
  final List<CatalogSectionV2> sections;

  /// Opaque cursor for the next page.
  final String? nextPage;

  /// Optional secondary catalog choices.
  final List<SubCategory> subCategories;

  /// All items in section order.
  Iterable<VersionedMediaItem> get items =>
      sections.expand((section) => section.items);

  /// Encodes the normalized version-2 wire shape.
  Map<String, Object?> toJson() => {
    'sections': sections.map((value) => value.toJson()).toList(),
    if (nextPage != null) 'nextPage': nextPage,
    if (subCategories.isNotEmpty)
      'subCategories': subCategories.map((value) => value.toJson()).toList(),
  };

  @override
  List<Object?> get props => [sections, nextPage, subCategories];
}

void _expectKeys(Map<String, Object?> json, Set<String> allowed, String path) {
  for (final key in json.keys) {
    if (!allowed.contains(key)) {
      throw FormatException('$path contains unsupported field "$key"');
    }
  }
}
