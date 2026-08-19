import 'package:flutter/material.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';

import '../theme/tokens.dart';
import 'media_card.dart';

class MediaGroup {
  const MediaGroup({required this.label, required this.items});

  final String? label;

  final List<MediaItem> items;
}

class MediaGrid extends StatelessWidget {
  const MediaGrid({
    super.key,
    required this.items,
    required this.onTap,
    this.scrollable = true,
    this.controller,
    this.showGroupHeaders = false,
    this.columns,
  });

  final List<MediaItem> items;

  final ValueChanged<MediaItem> onTap;

  final bool scrollable;

  final ScrollController? controller;

  final bool showGroupHeaders;

  final int? columns;

  static int columnsFor(double width) => (width ~/ 300).clamp(2, 6);

  static double _rowExtent() => 172;

  static List<MediaGroup> groupsOf(List<MediaItem> items) {
    final groups = <MediaGroup>[];
    for (final item in items) {
      if (groups.isNotEmpty && groups.last.label == item.group) {
        groups.last.items.add(item);
      } else {
        groups.add(MediaGroup(label: item.group, items: [item]));
      }
    }
    return groups;
  }

  static bool _posterMode(List<MediaItem> items) =>
      items.any((item) => item.poster != null);

  SliverGridDelegate _delegate(double width, bool posterMode) {
    final count = columns ?? columnsFor(width);
    return posterMode
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
            mainAxisExtent: _rowExtent(),
          );
  }

  @override
  Widget build(BuildContext context) {
    final posterMode = _posterMode(items);
    final groups = showGroupHeaders ? groupsOf(items) : const <MediaGroup>[];
    final sectioned = groups.any((group) => group.label != null);

    return LayoutBuilder(
      builder: (context, constraints) {
        if (!sectioned) {
          return GridView.builder(
            controller: scrollable ? controller : null,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            shrinkWrap: !scrollable,
            physics: scrollable ? null : const NeverScrollableScrollPhysics(),
            gridDelegate: _delegate(constraints.maxWidth, posterMode),
            itemCount: items.length,
            itemBuilder: (context, i) =>
                MediaCard(item: items[i], onTap: () => onTap(items[i])),
          );
        }

        return CustomScrollView(
          controller: scrollable ? controller : null,
          shrinkWrap: !scrollable,
          physics: scrollable ? null : const NeverScrollableScrollPhysics(),
          slivers: [
            for (final group in groups) ...[
              if (group.label != null)
                SliverToBoxAdapter(child: GroupHeader(label: group.label!)),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                sliver: SliverGrid(
                  gridDelegate: _delegate(constraints.maxWidth, posterMode),
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => MediaCard(
                      item: group.items[i],
                      onTap: () => onTap(group.items[i]),
                      showSubtitle: group.label == null,
                    ),
                    childCount: group.items.length,
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class GroupHeader extends StatelessWidget {
  const GroupHeader({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.md,
      AppSpacing.md,
      AppSpacing.md,
      AppSpacing.sm,
    ),
    child: Text(
      label,
      style: AppTypography.titleSm.copyWith(color: AppColors.onDarkSoft),
    ),
  );
}
