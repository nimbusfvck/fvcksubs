import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';

import '../theme/tokens.dart';
import '../widgets/clickable.dart';
import 'artwork_cache.dart';
import 'artwork_placeholder.dart';

class ChannelCard extends StatelessWidget {
  static const double preferredHeight = 144;

  const ChannelCard({
    super.key,
    required this.channel,
    required this.onTap,
    this.onLongPress,
  });

  final ChannelItemV2 channel;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) => Clickable(
    onTap: onTap,
    onLongPress: onLongPress,
    color: Colors.transparent,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.surfaceDarkElevated,
              borderRadius: AppRadius.lg,
              border: Border.all(color: AppColors.outlineDark),
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: LayoutBuilder(
                builder: (context, constraints) => ChannelArtwork(
                  channel: channel,
                  cacheWidth: artworkCacheDimension(
                    context,
                    constraints.maxWidth,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          channel.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: AppTypography.bodySm.copyWith(color: AppColors.onDark),
        ),
      ],
    ),
  );
}

class ChannelArtwork extends StatelessWidget {
  const ChannelArtwork({required this.channel, required this.cacheWidth});

  final ChannelItemV2 channel;
  final int? cacheWidth;

  @override
  Widget build(BuildContext context) {
    final image = channel.artwork?.logo ?? channel.artwork?.portrait;
    if (image == null) {
      return ArtworkPlaceholder(icon: Icons.tv_outlined, title: channel.title);
    }
    return CachedNetworkImage(
      imageUrl: image.url,
      fit: BoxFit.contain,
      memCacheWidth: cacheWidth,
      fadeInDuration: Duration.zero,
      placeholder: (_, _) => const ArtworkPlaceholder(icon: Icons.tv_outlined),
      errorWidget: (_, _, _) =>
          const ArtworkPlaceholder(icon: Icons.tv_outlined),
    );
  }
}
