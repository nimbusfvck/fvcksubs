import 'package:equatable/equatable.dart';

import '../json_util.dart';

/// One opaque subdivision returned by a catalog response.
class SubCategory extends Equatable {
  /// Creates a subcategory.
  const SubCategory({required this.id, required this.name});

  /// Decodes a subcategory.
  factory SubCategory.fromJson(Map<String, Object?> json) =>
      SubCategory(id: json['id']! as String, name: json['name']! as String);

  /// Opaque subcategory identifier.
  final String id;
  /// Display name.
  final String name;

  /// Encodes this subcategory.
  Map<String, Object?> toJson() => {'id': id, 'name': name};

  @override
  List<Object?> get props => [id, name];
}

/// Arguments for a catalog request.
class CatalogQuery extends Equatable {
  /// Creates a catalog request.
  const CatalogQuery({
    required this.providerId,
    required this.catalogId,
    this.category,
    this.page,
    this.filters = const {},
    this.subCategory,
  });

  /// Decodes a catalog request.
  factory CatalogQuery.fromJson(Map<String, Object?> json) => CatalogQuery(
    providerId: json['providerId'] as String,
    catalogId: json['catalogId'] as String,
    category: json['category'] as String?,
    page: json['page'] as String?,
    filters: stringMap(json['filters']),
    subCategory: json['subCategory'] as String?,
  );

  /// Provider owning the catalog.
  final String providerId;
  /// Catalog identifier.
  final String catalogId;
  /// Optional category filter.
  final String? category;
  /// Opaque pagination cursor.
  final String? page;
  /// Provider-defined filters.
  final Map<String, String> filters;
  /// Optional subcategory identifier.
  final String? subCategory;

  /// Encodes this request.
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
