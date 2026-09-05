import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';

import '../detail/open_versioned_item.dart';
import '../theme/breakpoints.dart';
import '../theme/tokens.dart';
import '../widgets/clickable.dart';
import 'media_card_actions.dart';
import 'media_card_v2.dart';
import 'catalog_section_header.dart';

class MediaGridV2 extends StatelessWidget {
  const MediaGridV2({
    super.key,
    required this.sections,
    required this.onTap,
    this.onTapWithHero,
    this.scrollable = true,
    this.controller,
    this.showSectionHeaders = false,
    this.columns,
    this.sliver = false,
  });

  final List<CatalogSectionV2> sections;
  final ValueChanged<VersionedMediaItem> onTap;
  final void Function(VersionedMediaItem item, Object heroTag)? onTapWithHero;
  final bool scrollable;
  final ScrollController? controller;
  final bool showSectionHeaders;
  final int? columns;

  /// Renders slivers for composition inside an existing [CustomScrollView].
  /// This keeps expanded Home catalogs lazy instead of nesting a shrink-wrapped
  /// [GridView] inside the outer scroll view.
  final bool sliver;

  List<VersionedMediaItem> get _items => [
    for (final section in sections) ...section.items,
  ];

  bool get _portraitMode => _items.any(
    (entry) =>
        entry.item.artwork?.portrait != null && entry.item is! EventItemV2,
  );

  SliverGridDelegate _delegate(double width) {
    final minimumTileWidth = _portraitMode ? 160 : 280;
    final count = columns ?? (width ~/ minimumTileWidth).clamp(2, 6);
    return _portraitMode
        ? SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: count,
            crossAxisSpacing: AppSpacing.md,
            mainAxisSpacing: AppSpacing.md,
            childAspectRatio: 0.6,
          )
        : SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: count,
            crossAxisSpacing: AppSpacing.md,
            mainAxisSpacing: AppSpacing.md,
            mainAxisExtent: 172,
          );
  }

  Widget _card(
    BuildContext context,
    VersionedMediaItem envelope, {
    bool showSubtitle = true,
  }) {
    final heroTag = Object();
    return MediaCardV2(
      item: envelope.item,
      showSubtitle: showSubtitle,
      heroTag: onTapWithHero == null ? null : heroTag,
      onTap: () => onTapWithHero == null
          ? onTap(envelope)
          : onTapWithHero!(envelope, heroTag),
      onLongPress: () => showMediaCardActions(
        context,
        envelope.item,
        onViewDetails: () => openDetails(context, envelope.item),
      ),
    );
  }

  Widget _sliverContent(SliverConstraints constraints) {
    final sideInset = math
        .max(
          0,
          (constraints.crossAxisExtent - AppBreakpoints.maxContentWidth) / 2,
        )
        .toDouble();
    final horizontalPadding = AppSpacing.md + sideInset;
    final contentWidth = constraints.crossAxisExtent - horizontalPadding * 2;

    Widget gridFor(
      List<VersionedMediaItem> items, {
      bool showSubtitle = true,
    }) => SliverPadding(
      padding: EdgeInsets.symmetric(
        horizontal: horizontalPadding,
        vertical: Clickable.ringBleed,
      ),
      sliver: SliverGrid(
        gridDelegate: _delegate(contentWidth),
        delegate: SliverChildBuilderDelegate(
          (context, index) =>
              _card(context, items[index], showSubtitle: showSubtitle),
          childCount: items.length,
        ),
      ),
    );

    if (!showSectionHeaders) return gridFor(_items);
    return SliverMainAxisGroup(
      slivers: [
        for (final section in sections) ...[
          if (section.title != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.only(left: sideInset, right: sideInset),
                child: CatalogSectionHeader(label: section.title!),
              ),
            ),
          gridFor(section.items, showSubtitle: section.title == null),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (sliver) {
      return SliverLayoutBuilder(
        builder: (context, constraints) => _sliverContent(constraints),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!showSectionHeaders) {
          final items = _items;
          return GridView.builder(
            controller: scrollable ? controller : null,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: Clickable.ringBleed,
            ),
            shrinkWrap: !scrollable,
            physics: scrollable ? null : const NeverScrollableScrollPhysics(),
            gridDelegate: _delegate(constraints.maxWidth - AppSpacing.md * 2),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final envelope = items[index];
              return _card(context, envelope);
            },
          );
        }

        return CustomScrollView(
          controller: scrollable ? controller : null,
          shrinkWrap: !scrollable,
          physics: scrollable ? null : const NeverScrollableScrollPhysics(),
          slivers: [
            for (final section in sections) ...[
              if (section.title != null)
                SliverToBoxAdapter(
                  child: CatalogSectionHeader(label: section.title!),
                ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: Clickable.ringBleed,
                ),
                sliver: SliverGrid(
                  gridDelegate: _delegate(
                    constraints.maxWidth - AppSpacing.md * 2,
                  ),
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final envelope = section.items[index];
                    return _card(
                      context,
                      envelope,
                      showSubtitle: section.title == null,
                    );
                  }, childCount: section.items.length),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
