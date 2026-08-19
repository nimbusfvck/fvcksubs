import 'package:equatable/equatable.dart';

import '../content/media_item.dart';
import '../json_util.dart';

/// One sub-division of a catalog, as it exists *right now*.
///
/// Deliberately **not** declared in the manifest. What a catalog divides into
/// is often a property of today's data, not of the extension: which
/// competitions have matches changes daily, so a manifest-declared list would
/// show empty leagues and miss new ones until the extension was reinstalled.
/// So the extension returns whatever is real at fetch time
/// ([CatalogPage.subCategories]) and the app renders that.
///
/// Distinct from [MediaItem.group], which sections items *within one
/// response*: a group is a heading you scroll past, a subcategory is a
/// narrowing you fetch. A catalog may use either, both, or neither.
class SubCategory extends Equatable {
  /// Creates a subcategory.
  const SubCategory({required this.id, required this.name});

  /// Builds a [SubCategory] from decoded JSON.
  factory SubCategory.fromJson(Map<String, Object?> json) => SubCategory(
    id: json['id']! as String,
    name: json['name']! as String,
  );

  /// Opaque id, echoed back in [CatalogQuery.subCategory]. The app never
  /// interprets it — only the extension knows what it selects.
  final String id;

  /// Display name (`"Premier League"`, `"Trending"`).
  final String name;

  /// Encodes to a JSON map.
  Map<String, Object?> toJson() => {'id': id, 'name': name};

  @override
  List<Object?> get props => [id, name];
}

/// A `catalog` call's arguments.
class CatalogQuery extends Equatable {
  /// Creates a catalog query.
  const CatalogQuery({
    required this.providerId,
    required this.catalogId,
    this.category,
    this.page,
    this.filters = const {},
    this.subCategory,
  });

  /// Builds a [CatalogQuery] from decoded JSON.
  factory CatalogQuery.fromJson(Map<String, Object?> json) => CatalogQuery(
    providerId: json['providerId'] as String,
    catalogId: json['catalogId'] as String,
    category: json['category'] as String?,
    page: json['page'] as String?,
    filters: stringMap(json['filters']),
    subCategory: json['subCategory'] as String?,
  );

  /// Provider being queried.
  final String providerId;

  /// Catalog within the provider.
  final String catalogId;

  /// Which of the catalog's [CatalogDecl.categories] the user is browsing, or
  /// `null` when the caller wants the catalog undivided.
  ///
  /// The first narrowing of the four (category → subCategory → group): a
  /// catalog is the root of everything a provider serves, so without this the
  /// extension would have to guess which slice of it the user is looking at.
  final String? category;

  /// Opaque page cursor from a previous response, or `null` for the first page.
  final String? page;

  /// Filter values keyed by the catalog's declared filter keys.
  final Map<String, String> filters;

  /// Which [SubCategory] the user picked, by [SubCategory.id], or `null` for
  /// the unnarrowed catalog. Only ever an id the extension itself returned.
  ///
  /// Narrows *within* [category] — the ids only mean anything in that context,
  /// which is why both travel together.
  final String? subCategory;

  /// Encodes to a JSON map.
  Map<String, Object?> toJson() => {
    'providerId': providerId,
    'catalogId': catalogId,
    if (category != null) 'category': category,
    if (page != null) 'page': page,
    if (filters.isNotEmpty) 'filters': filters,
    if (subCategory != null) 'subCategory': subCategory,
  };

  @override
  List<Object?> get props => [
    providerId,
    catalogId,
    category,
    page,
    filters,
    subCategory,
  ];
}

/// A `catalog` (or `search`) call's result: a page of items.
class CatalogPage extends Equatable {
  /// Creates a catalog page.
  const CatalogPage({
    required this.items,
    this.nextPage,
    this.subCategories = const [],
  });

  /// Builds a [CatalogPage] from decoded JSON.
  factory CatalogPage.fromJson(Map<String, Object?> json) => CatalogPage(
    items: ((json['items'] as List?) ?? const [])
        .map((e) => MediaItem.fromJson(e as Map<String, Object?>))
        .toList(),
    nextPage: json['nextPage'] as String?,
    subCategories: ((json['subCategories'] as List?) ?? const [])
        .map((e) => SubCategory.fromJson(e as Map<String, Object?>))
        .toList(),
  );

  /// Items on this page.
  final List<MediaItem> items;

  /// Cursor for the next page, or `null` when this is the last.
  final String? nextPage;

  /// Sub-divisions available for this catalog as of this response, or empty
  /// when it has none. Empty is the normal case, not a degraded one — most
  /// catalogs are a single flat list.
  ///
  /// Returned on *every* page, including a narrowed one, so the chips stay
  /// put while the user moves between them rather than vanishing the moment
  /// they pick something.
  final List<SubCategory> subCategories;

  /// Encodes to a JSON map.
  Map<String, Object?> toJson() => {
    'items': items.map((i) => i.toJson()).toList(),
    if (nextPage != null) 'nextPage': nextPage,
    if (subCategories.isNotEmpty)
      'subCategories': subCategories.map((s) => s.toJson()).toList(),
  };

  @override
  List<Object?> get props => [items, nextPage, subCategories];
}
