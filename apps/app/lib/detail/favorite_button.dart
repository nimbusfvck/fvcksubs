import 'package:flutter/material.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';

import '../app_scope.dart';
import '../theme/tokens.dart';

class FavoriteButton extends StatelessWidget {
  const FavoriteButton({super.key, required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context).libraryController;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final favorited = controller.isFavorite(item.ref);
        return IconButton(
          icon: Icon(favorited ? Icons.favorite : Icons.favorite_border),
          color: favorited ? AppColors.liveAccent : null,
          tooltip: favorited ? 'Remove from favorites' : 'Add to favorites',
          onPressed: () => controller.toggleFavorite(item),
        );
      },
    );
  }
}
