import 'dart:async';

import 'package:flutter/material.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';

import '../app_scope.dart';

/// Shows the card action menu without changing the card's normal tap action.
void showMediaCardActions(
  BuildContext context,
  MediaItemV2 item, {
  required VoidCallback onViewDetails,
}) {
  final library = AppScope.of(context).libraryController;
  final isFavorite = library.isFavorite(item.ref);

  unawaited(
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                isFavorite ? Icons.check : Icons.add,
              ),
              title: Text(
                isFavorite ? 'Remove from favorites' : 'Add to favorites',
              ),
              onTap: () {
                library.toggleFavorite(item);
                Navigator.of(sheetContext).pop();
              },
            ),
            ListTile(
              leading: const Icon(Icons.info_outline_rounded),
              title: const Text('View details'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                onViewDetails();
              },
            ),
          ],
        ),
      ),
    ),
  );
}
