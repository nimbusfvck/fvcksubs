import 'dart:ui' show ImageFilter;

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
      Color(0xD0000000),
      Color(0x7A000000),
      Color(0x1A000000),
      Color(0x00000000),
      Color(0x00000000),
      Color(0x50101010),
      Color(0xB0101010),
      Color(0xF0101010),
      Color(0xFF101010),
    ],
    stops: [0, 0.05, 0.09, 0.12, 0.52, 0.60, 0.74, 0.90, 1],
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
        const _HeroBottomBlur(),
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

class _HeroBottomBlur extends StatelessWidget {
  const _HeroBottomBlur();

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.bottomCenter,
    child: FractionallySizedBox(
      widthFactor: 1,
      heightFactor: 0.44,
      child: ClipRect(
        child: ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (bounds) => const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, Colors.black, Colors.black],
            stops: [0, 0.60, 1],
          ).createShader(bounds),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: const ColoredBox(color: Colors.transparent),
          ),
        ),
      ),
    ),
  );
}
