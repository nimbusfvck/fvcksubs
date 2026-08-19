import 'package:flutter/material.dart';
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';

import 'catalog_view.dart';

class CatalogScreen extends StatelessWidget {
  const CatalogScreen({
    super.key,
    required this.binding,
    this.category,
    this.subCategory,
    this.title,
  });

  final CatalogBinding binding;

  final String? category;

  final String? subCategory;

  final String? title;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title ?? binding.catalog.name)),
    body: CatalogView(
      binding: binding,
      category: category,
      initialSubCategory: subCategory,
    ),
  );
}
