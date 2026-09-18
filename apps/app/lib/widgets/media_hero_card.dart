import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';

import '../catalog/artwork_cache.dart';
import '../theme/tokens.dart';
import 'media_hero_flexible_space.dart';
import 'media_hero_layout.dart';

/// Shared visual frame for prominent media on Home and Detail.
class MediaHeroCard extends StatefulWidget {
  const MediaHeroCard({
    super.key,
    required this.item,
    required this.foreground,
    this.preview,
    this.showGradient = true,
    this.overlayGradient,
    this.bottomBlurSigma = 20,
    this.bottomBlurHeightFactor = 0.44,
    this.bottomBlurFadeStop = 0.60,
    this.artworkDim = 0,
    this.artworkAlignment = Alignment.topCenter,
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

  static const detailGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0x00000000),
      Color(0x08000000),
      Color(0x30000000),
      Color(0x80101010),
      Color(0xC8101010),
      Color(0xF0101010),
      Color(0xFA101010),
      Color(0xFF101010),
      Color(0xFF101010),
    ],
    stops: [0, 0.16, 0.30, 0.42, 0.56, 0.70, 0.88, 0.98, 1],
  );

  final MediaItemV2 item;
  final Widget foreground;
  final Widget? preview;
  final bool showGradient;
  final Gradient? overlayGradient;
  final double bottomBlurSigma;
  final double bottomBlurHeightFactor;
  final double bottomBlurFadeStop;
  final double artworkDim;
  final Alignment artworkAlignment;
  final Widget? fallback;
  final Object? heroTag;

  @override
  State<MediaHeroCard> createState() => _MediaHeroCardState();
}

class _MediaHeroCardState extends State<MediaHeroCard> {
  Timer? _backdropTimer;
  int _backdropIndex = 0;

  @override
  void dispose() {
    _backdropTimer?.cancel();
    super.dispose();
  }

  List<ImageRef> _landscapes() {
    final artwork = widget.item.artwork;
    if (artwork == null) return const [];
    final images = <ImageRef>[];
    if (artwork.landscape != null) images.add(artwork.landscape!);
    for (final image in artwork.backdrops) {
      if (!images.any((existing) => existing.url == image.url)) {
        images.add(image);
      }
    }
    return images;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _backdropTimer ??= Timer.periodic(const Duration(seconds: 8), (_) {
      if (!mounted) return;
      final count = _landscapes().length;
      if (count < 2) return;
      setState(() => _backdropIndex = (_backdropIndex + 1) % count);
    });
  }

  @override
  Widget build(BuildContext context) {
    final artworkData = widget.item.artwork;
    final landscapes = _landscapes();
    final image = MediaHeroLayout.isLargeScreen(context)
        ? (landscapes.isNotEmpty
              ? landscapes[_backdropIndex % landscapes.length]
              : artworkData?.portrait)
        : artworkData?.portrait ?? artworkData?.landscape;
    final fallbackArtwork =
        widget.fallback ??
        const ColoredBox(color: AppColors.surfaceDarkElevated);
    Widget artwork = image == null
        ? fallbackArtwork
        : CachedNetworkImage(
            key: ValueKey(image.url),
            imageUrl: image.url,
            fit: BoxFit.cover,
            alignment: widget.artworkAlignment,
            fadeInDuration: Duration.zero,
            memCacheWidth: artworkCacheDimension(
              context,
              MediaQuery.sizeOf(context).width,
            ),
            placeholder: (_, _) =>
                const ColoredBox(color: AppColors.surfaceDarkElevated),
            errorWidget: (_, _, _) => fallbackArtwork,
          );
    if (image != null && widget.heroTag != null) {
      artwork = Hero(tag: widget.heroTag!, child: artwork);
    }
    final backdrop = Stack(
      fit: StackFit.expand,
      children: [
        artwork,
        if (widget.artworkDim > 0)
          ColoredBox(color: Colors.black.withValues(alpha: widget.artworkDim)),
        if (widget.preview case final preview?) Positioned.fill(child: preview),
        if (widget.showGradient)
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: widget.overlayGradient ?? MediaHeroCard.gradient,
            ),
          ),
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
              offset: Offset(0, mediaHeroParallaxOffset(context, collapse)),
              child: backdrop,
            ),
          ),
        ),
        widget.foreground,
      ],
    );
  }
}

class MediaHeroBottomBlur extends StatelessWidget {
  const MediaHeroBottomBlur({
    required this.sigma,
    required this.heightFactor,
    required this.fadeStop,
  });

  final double sigma;
  final double heightFactor;
  final double fadeStop;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.bottomCenter,
    child: FractionallySizedBox(
      widthFactor: 1,
      heightFactor: heightFactor,
      child: ClipRect(
        child: ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, Colors.black, Colors.black],
            stops: [0, fadeStop, 1],
          ).createShader(bounds),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
            child: const ColoredBox(color: Colors.transparent),
          ),
        ),
      ),
    ),
  );
}
