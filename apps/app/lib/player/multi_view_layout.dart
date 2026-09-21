part of 'multi_view_page.dart';

const String _addEventLayoutId = '__multi_view_add_event__';

Widget _buildResponsiveLayout(
  _MultiViewPageState state,
  AppScope scope,
  BoxConstraints constraints,
  int maxSlots,
) {
  final contentWidth = (constraints.maxWidth - AppSpacing.md * 2)
      .clamp(0.0, double.infinity)
      .toDouble();
  final viewportHeight = (constraints.maxHeight - AppSpacing.md * 2)
      .clamp(0.0, double.infinity)
      .toDouble();
  final gap = AppSpacing.md;
  final addEvent = state._entries.length < maxSlots;
  final pinned =
      state._pinnedKey != null &&
      constraints.maxWidth >= _largeMultiViewBreakpoint;
  final rects = <Object, Rect>{};

  if (pinned) {
    final pinnedKey = state._pinnedKey!;
    final pinnedWidth = (contentWidth - gap) * 2 / 3;
    final sideWidth = contentWidth - gap - pinnedWidth;
    final sideCount = state._entries.length - 1 + (addEvent ? 1 : 0);
    final sideHeight = sideCount == 0
        ? viewportHeight
        : ((viewportHeight - gap * (sideCount - 1))
                  .clamp(0.0, double.infinity)
                  .toDouble()) /
              sideCount;
    final pinnedHeight = viewportHeight;
    rects[pinnedKey] = Rect.fromLTWH(0, 0, pinnedWidth, pinnedHeight);

    var sideIndex = 0;
    for (final entry in state._entries) {
      if (entry.key == pinnedKey) continue;
      rects[entry.key] = Rect.fromLTWH(
        pinnedWidth + gap,
        sideIndex * (sideHeight + gap),
        sideWidth,
        sideHeight,
      );
      sideIndex++;
    }
    if (addEvent) {
      rects[_addEventLayoutId] = Rect.fromLTWH(
        pinnedWidth + gap,
        sideIndex * (sideHeight + gap),
        sideWidth,
        sideHeight,
      );
      sideIndex++;
    }
    return _multiViewLayoutShell(
      state,
      scope,
      rects,
      contentWidth,
      viewportHeight,
      maxSlots,
    );
  }

  // Large multi-view supports up to eight players, so keep four columns
  // available across the large breakpoint. That guarantees eight players
  // fit in two rows instead of falling into a third row on medium desktops.
  final maxColumns = constraints.maxWidth >= _largeMultiViewBreakpoint
      ? 4
      : constraints.maxWidth >= 700
      ? 2
      : 1;
  final itemCount = state._entries.length + (addEvent ? 1 : 0);
  // Size the grid from all visible slots, including Add. This keeps three
  // players plus Add as a balanced 2x2 grid, then grows to 3x2 and 4x2/3x3
  // as more events are added, subject to the available screen width.
  final preferredColumns = itemCount <= 4
      ? 2
      : itemCount <= 6
      ? 3
      : 4;
  final columns = preferredColumns < maxColumns ? preferredColumns : maxColumns;
  final tileWidth = (contentWidth - gap * (columns - 1)) / columns;
  final rows = (itemCount + columns - 1) ~/ columns;
  final tileHeight =
      ((viewportHeight - gap * (rows - 1))
          .clamp(0.0, double.infinity)
          .toDouble()) /
      rows;
  for (var index = 0; index < state._entries.length; index++) {
    final row = index ~/ columns;
    final column = index % columns;
    rects[state._entries[index].key] = Rect.fromLTWH(
      column * (tileWidth + gap),
      row * (tileHeight + gap),
      tileWidth,
      tileHeight,
    );
  }
  if (addEvent) {
    final row = state._entries.length ~/ columns;
    final column = state._entries.length % columns;
    rects[_addEventLayoutId] = Rect.fromLTWH(
      column * (tileWidth + gap),
      row * (tileHeight + gap),
      tileWidth,
      tileHeight,
    );
  }
  return _multiViewLayoutShell(
    state,
    scope,
    rects,
    contentWidth,
    viewportHeight,
    maxSlots,
  );
}

Widget _multiViewLayoutShell(
  _MultiViewPageState state,
  AppScope scope,
  Map<Object, Rect> rects,
  double contentWidth,
  double contentHeight,
  int maxSlots,
) => Padding(
  padding: const EdgeInsets.all(AppSpacing.md),
  child: SizedBox(
    width: contentWidth,
    height: contentHeight,
    child: CustomMultiChildLayout(
      delegate: _MultiViewLayoutDelegate(rects),
      children: [
        for (var index = 0; index < state._entries.length; index++)
          LayoutId(
            key: ValueKey(state._entries[index].key),
            id: state._entries[index].key,
            child: state._buildEntryTile(index, scope),
          ),
        if (rects.containsKey(_addEventLayoutId))
          LayoutId(
            key: const ValueKey(_addEventLayoutId),
            id: _addEventLayoutId,
            child: _AddEventTile(
              loading: state._adding,
              onTap: state._addEvent,
              maxSlots: maxSlots,
            ),
          ),
      ],
    ),
  ),
);

class _MultiViewLayoutDelegate extends MultiChildLayoutDelegate {
  _MultiViewLayoutDelegate(this.rects);

  final Map<Object, Rect> rects;

  @override
  void performLayout(Size size) {
    for (final entry in rects.entries) {
      if (!hasChild(entry.key)) continue;
      layoutChild(entry.key, BoxConstraints.tight(entry.value.size));
      positionChild(entry.key, entry.value.topLeft);
    }
  }

  @override
  bool shouldRelayout(_MultiViewLayoutDelegate oldDelegate) => true;
}
