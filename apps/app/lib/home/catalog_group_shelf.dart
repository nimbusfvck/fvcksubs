import 'package:flutter/material.dart';

import '../catalog/catalog_screen.dart';
import 'catalog_grid_section.dart';
import 'catalog_grouping.dart';
import 'catalog_shelf.dart';
import 'grouped_header.dart';
import '../widgets/centered_content.dart';

class CatalogGroupShelf extends StatefulWidget {
  const CatalogGroupShelf({
    super.key,
    required this.group,
    required this.category,
    required this.scrollController,
    this.sliver = false,
  });

  final HomeCatalogGroup group;
  final String category;
  final ScrollController scrollController;
  final bool sliver;

  @override
  State<CatalogGroupShelf> createState() => _CatalogGroupShelfState();
}

class _CatalogGroupShelfState extends State<CatalogGroupShelf> {
  int _selectedIndex = 0;

  HomeCatalogOption get _selected => widget.group.options[_selectedIndex];

  void _select(int index) {
    if (index == _selectedIndex) return;
    setState(() => _selectedIndex = index);
  }

  void _openCatalog() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => CatalogScreen(
        binding: _selected.binding,
        category: widget.category,
        title: _selected.binding.catalog.name,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final binding = _selected.binding;
    final header = GroupedHeader(
      title: widget.group.title,
      options: [for (final option in widget.group.options) option.label],
      selectedIndex: _selectedIndex,
      onSelected: _select,
      onSeeMore: _openCatalog,
    );
    final key = ValueKey(
      '${binding.extensionId}/${binding.extension.manifest.version}/'
      '${binding.catalog.id}',
    );

    if (widget.sliver) {
      return SliverMainAxisGroup(
        slivers: [
          SliverToBoxAdapter(child: CenteredContent(child: header)),
          if (binding.catalog.expanded)
            CatalogGridSection(
              key: key,
              binding: binding,
              category: widget.category,
              scrollController: widget.scrollController,
              showCatalogTitle: false,
              sliver: true,
            )
          else
            SliverToBoxAdapter(
              child: CenteredContent(
                child: CatalogShelf(
                  key: key,
                  binding: binding,
                  category: widget.category,
                  showCatalogHeader: false,
                ),
              ),
            ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        if (binding.catalog.expanded)
          CatalogGridSection(
            key: key,
            binding: binding,
            category: widget.category,
            scrollController: widget.scrollController,
            showCatalogTitle: false,
          )
        else
          CatalogShelf(
            key: key,
            binding: binding,
            category: widget.category,
            showCatalogHeader: false,
          ),
      ],
    );
  }
}
