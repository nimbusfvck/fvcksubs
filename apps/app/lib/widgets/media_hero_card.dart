import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';

import '../catalog/artwork_cache.dart';
import '../theme/tokens.dart';
import 'media_hero_flexible_space.dart';

/// Shared visual frame for prominent media on Home and Detail.
class MediaHeroCard extends StatelessWidget {
  const MediaHeroCard({
    super.key,
    required this.item,
    required this.foreground,
    this.preview,
    this.fallback,
    this.heroTag,
  });

  static const gradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xD9000000),
      Color(0x40000000),
      Color(0xF0101010),
      Color(0xFF101010),
    ],
    stops: [0, 0.24, 0.58, 1],
  );

  final MediaItemV2 item;
  final Widget foreground;
  final Widget? preview;
  final Widget? fallback;
  final Object? heroTag;

  @override
  Widget build(BuildContext context) {
    final image = item.artwork?.portrait ?? item.artwork?.landscape;
    final fallbackArtwork =
        fallback ?? const ColoredBox(color: AppColors.surfaceDarkElevated);
    Widget artwork = image == null
        ? fallbackArtwork
        : CachedNetworkImage(
            imageUrl: image.url,
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
            fadeInDuration: Duration.zero,
            memCacheWidth: artworkCacheDimension(
              context,
              MediaQuery.sizeOf(context).width,
            ),
            placeholder: (_, _) =>
                const ColoredBox(color: AppColors.surfaceDarkElevated),
            errorWidget: (_, _, _) => fallbackArtwork,
          );
    if (image != null && heroTag != null) {
      artwork = Hero(tag: heroTag!, child: artwork);
    }
    final backdrop = Stack(
      fit: StackFit.expand,
      children: [
        artwork,
        if (preview case final preview?) Positioned.fill(child: preview),
        const DecoratedBox(decoration: BoxDecoration(gradient: gradient)),
      ],
    );
    final collapse = MediaHeroCollapseScope.of(context);
    return Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.hardEdge,
      children: [
        Positioned.fill(
          child: ClipRect(
            child: Transform.translate(
              offset: Offset(0, -collapse * 0.28),
              child: backdrop,
            ),
          ),
        ),
        foreground,
      ],
    );
  }
}
