import 'package:flutter/material.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';

import 'open_item.dart';

void openVersionedItem(BuildContext context, VersionedMediaItem item) {
  final legacy = item.legacyItem;
  if (legacy != null) {
    openItem(context, legacy);
    return;
  }
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('This item requires protocol v2 playback.')),
  );
}
