import 'package:flutter/material.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';

import '../player/workflow/play_item.dart';
import 'detail_page_v2.dart';

void openDetails(
  BuildContext context,
  MediaItemV2 item, {
  Object? heroTag,
  ContentRating contentRating = ContentRating.unknown,
}) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      settings: const RouteSettings(name: 'detail'),
      builder: (_) => DetailPageV2(
        item: item,
        heroTag: heroTag,
        contentRating: contentRating,
      ),
    ),
  );
}

void openVersionedItem(
  BuildContext context,
  VersionedMediaItem item, {
  Object? heroTag,
  ContentRating contentRating = ContentRating.unknown,
}) {
  final current = item.item;
  if (current is VideoItemV2 || current is SeriesItemV2) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'detail'),
        builder: (_) => DetailPageV2(
          item: current,
          heroTag: heroTag,
          contentRating: contentRating,
        ),
      ),
    );
    return;
  }
  playItemV2(context, current, contentRating: contentRating);
}
