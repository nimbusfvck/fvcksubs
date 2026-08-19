import 'package:flutter/material.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';

import 'open_item.dart';
import '../player/play_item.dart';
import 'detail_page_v2.dart';

void openVersionedItem(BuildContext context, VersionedMediaItem item) {
  final legacy = item.legacyItem;
  if (legacy != null) {
    openItem(context, legacy);
    return;
  }
  final current = item.item;
  if (current is SeriesItemV2) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => DetailPageV2(item: current)),
    );
    return;
  }
  playItemV2(context, current);
}
