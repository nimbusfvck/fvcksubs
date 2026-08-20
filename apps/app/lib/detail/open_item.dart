import 'package:flutter/material.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';

import '../player/play_item.dart';
import 'detail_page.dart';

void openItem(BuildContext context, MediaItem item) {
  final isVod = item.kind == MediaKind.movie || item.kind == MediaKind.series;
  if (!isVod) {
    playItem(context, item);
    return;
  }
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      settings: const RouteSettings(name: 'detail'),
      builder: (_) => DetailPage(item: item),
    ),
  );
}
