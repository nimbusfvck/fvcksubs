import 'package:flutter/material.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';

import '../theme/tokens.dart';
import '../widgets/clickable.dart';
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
  });

  final List<CatalogSectionV2> sections;
  final ValueChanged<VersionedMediaItem> onTap;
  final void Function(VersionedMediaItem item, Object heroTag)? onTapWithHero;
  final bool scrollable;
  final ScrollController? controller;
  final bool showSectionHeaders;
  final int? columns;

  List<VersionedMediaItem> get _items => [
    for (final section in sections) ...section.items,
  ];

  bool get _portraitMode =>
      _items.any((entry) => entry.item.artwork?.portrait != null);

  bool get _matchBannerMode =>
      _items.any((entry) => isMatchBannerItem(entry.item));

  SliverGridDelegate _delegate(double width) {
    final count = columns ?? (width ~/ 300).clamp(2, 6);
    return _portraitMode
        ? SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: count,
            crossAxisSpacing: AppSpacing.md,
            mainAxisSpacing: AppSpacing.md,
            childAspectRatio: 0.6,
          )
        : _matchBannerMode
        ? SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: count,
            crossAxisSpacing: AppSpacing.md,
            mainAxisSpacing: AppSpacing.md,
            mainAxisExtent: matchBannerCardHeight,
          )
        : SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: count,
            crossAxisSpacing: AppSpacing.md,
            mainAxisSpacing: AppSpacing.md,
            mainAxisExtent: 172,
          );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
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
          gridDelegate: _delegate(constraints.maxWidth),
          itemCount: items.length,
          itemBuilder: (_, index) {
            final envelope = items[index];
            final heroTag = Object();
            return MediaCardV2(
              item: envelope.item,
              heroTag: onTapWithHero == null ? null : heroTag,
              onTap: () => onTapWithHero == null
                  ? onTap(envelope)
                  : onTapWithHero!(envelope, heroTag),
            );
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
                gridDelegate: _delegate(constraints.maxWidth),
                delegate: SliverChildBuilderDelegate((_, index) {
                  final envelope = section.items[index];
                  final heroTag = Object();
                  return MediaCardV2(
                    item: envelope.item,
                    heroTag: onTapWithHero == null ? null : heroTag,
                    onTap: () => onTapWithHero == null
                        ? onTap(envelope)
                        : onTapWithHero!(envelope, heroTag),
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
