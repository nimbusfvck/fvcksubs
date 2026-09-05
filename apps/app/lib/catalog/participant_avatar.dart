import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'artwork_cache.dart';

class ParticipantAvatar extends StatelessWidget {
  const ParticipantAvatar({super.key, this.imageUrl, this.size = 28});

  final String? imageUrl;

  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    clipBehavior: Clip.antiAlias,
    decoration: const BoxDecoration(
      shape: BoxShape.circle,
      color: AppColors.surfaceDarkHighest,
    ),
    child: imageUrl == null
        ? _Fallback(size: size)
        : CachedNetworkImage(
            imageUrl: imageUrl!,
            fit: BoxFit.contain,
            fadeInDuration: Duration.zero,
            memCacheWidth: artworkCacheDimension(context, size),
            placeholder: (context, url) => const SizedBox.shrink(),
            errorWidget: (context, url, error) => _Fallback(size: size),
          ),
  );
}

class _Fallback extends StatelessWidget {
  const _Fallback({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) => Center(
    child: Icon(
      Icons.circle_outlined,
      size: size * 0.55,
      color: AppColors.onDarkSoft,
    ),
  );
}
