import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';

import '../theme/tokens.dart';
import 'catalog_status_badges.dart';

const List<Color> _bannerPalette = [
  Color(0xFF4338CA), // indigo
  Color(0xFF047857), // emerald
  Color(0xFF1D4ED8), // blue
  Color(0xFF6D28D9), // violet
  Color(0xFFB45309), // amber
  Color(0xFF0F766E), // teal
  Color(0xFFA21CAF), // fuchsia
  Color(0xFFBE123C), // rose
];

const _fnvOffsetBasis = 2166136261;
const _fnvPrime = 16777619;
const _positiveHashMask = 0x7fffffff;

int _stableHash(String value) {
  var hash = _fnvOffsetBasis;
  for (final unit in value.codeUnits) {
    hash = ((hash ^ unit) * _fnvPrime) & _positiveHashMask;
  }
  return hash;
}

int _paletteIndex(String name) => _stableHash(name) % _bannerPalette.length;

Color? _parseHex(String? hex) {
  if (hex == null) return null;
  final cleaned = hex.startsWith('#') ? hex.substring(1) : hex;
  if (cleaned.length != 6) return null;
  final value = int.tryParse(cleaned, radix: 16);
  return value == null ? null : Color(0xFF000000 | value);
}

Color _legibleFill(Color raw) {
  final t = (1 - raw.computeLuminance()).clamp(0.35, 0.85);
  return Color.lerp(AppColors.surfaceDark, raw, t)!;
}

const double _minSeparation = 0.22;

double _separation(Color a, Color b) {
  final dr = a.r - b.r;
  final dg = a.g - b.g;
  final db = a.b - b.b;
  return math.sqrt(dr * dr + dg * dg + db * db);
}

Color _separated(Color home, Color away) {
  if (_separation(home, away) >= _minSeparation) return away;

  final lighter = Color.lerp(away, Colors.white, 0.30)!;
  final darker = Color.lerp(away, Colors.black, 0.42)!;
  final canLighten =
      lighter.computeLuminance() < 0.5 &&
      _separation(home, lighter) > _separation(home, darker);
  return canLighten ? lighter : darker;
}

class GeneratedBanner extends StatelessWidget {
  const GeneratedBanner({
    super.key,
    required this.participants,
    this.status = ScheduleState.unknown,
  });

  final List<Participant> participants;

  final ScheduleState status;

  @visibleForTesting
  static (Color, Color) fillsFor(List<Participant> participants) {
    final home = participants[0];
    final away = participants[1];
    final homeIndex = _paletteIndex(home.name);
    var awayIndex = _paletteIndex(away.name);
    if (awayIndex == homeIndex) {
      awayIndex = (awayIndex + 1) % _bannerPalette.length;
    }

    final homeFill = _legibleFill(
      _parseHex(home.color) ?? _bannerPalette[homeIndex],
    );
    final awayFill = _legibleFill(
      _parseHex(away.color) ?? _bannerPalette[awayIndex],
    );
    return (homeFill, _separated(homeFill, awayFill));
  }

  @override
  Widget build(BuildContext context) {
    final (homeColor, awayColor) = fillsFor(participants);

    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        final crestSize = math.min(height * 0.5, 60.0);

        return Stack(
          fit: StackFit.expand,
          children: [
            CustomPaint(
              painter: _BannerArtwork(home: homeColor, away: awayColor),
            ),
            Row(
              children: [
                Expanded(
                  child: Center(
                    child: _Crest(
                      imageUrl: participants[0].logo?.url,
                      size: crestSize,
                    ),
                  ),
                ),
                SizedBox(width: height * 0.2),
                Expanded(
                  child: Center(
                    child: _Crest(
                      imageUrl: participants[1].logo?.url,
                      size: crestSize,
                    ),
                  ),
                ),
              ],
            ),
            if (status == ScheduleState.live)
              const Positioned(
                left: AppSpacing.xs,
                top: AppSpacing.xs,
                child: LiveBadge(),
              )
            else if (status == ScheduleState.scheduled)
              const Positioned(
                left: AppSpacing.xs,
                top: AppSpacing.xs,
                child: UpcomingBadge(),
              ),
          ],
        );
      },
    );
  }
}

/// Full-bleed fallback artwork for a live channel or scheduled event.
///
/// The background is deterministic for the same item. Participant colors and
/// logos are used when present; otherwise the title-derived palette keeps the
/// artwork useful without provider-specific assets.
class GeneratedLiveArtwork extends StatelessWidget {
  const GeneratedLiveArtwork({
    super.key,
    required this.seed,
    this.participants = const [],
    this.logo,
  });

  final String seed;
  final List<Participant> participants;
  final ImageRef? logo;

  @visibleForTesting
  static (Color, Color) fillsFor(
    String seed, {
    List<Participant> participants = const [],
  }) {
    if (participants.length >= 2) {
      return GeneratedBanner.fillsFor(participants);
    }

    final participant = participants.isEmpty ? null : participants.first;
    final primaryKey = participant?.name ?? seed;
    final primaryIndex = _paletteIndex(primaryKey);
    var secondaryIndex = _paletteIndex('$seed:secondary');
    if (secondaryIndex == primaryIndex) {
      secondaryIndex = (secondaryIndex + 1) % _bannerPalette.length;
    }

    final primary = _legibleFill(
      _parseHex(participant?.color) ?? _bannerPalette[primaryIndex],
    );
    final secondary = _legibleFill(_bannerPalette[secondaryIndex]);
    return (primary, _separated(primary, secondary));
  }

  @override
  Widget build(BuildContext context) {
    final (primary, secondary) = fillsFor(seed, participants: participants);
    final motif = _LiveArtworkMotif.forKey(seed);

    return ExcludeSemantics(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final shortestSide = math.min(
            constraints.maxWidth,
            constraints.maxHeight,
          );
          final scale = shortestSide.isFinite ? shortestSide : 320.0;

          return Stack(
            fit: StackFit.expand,
            children: [
              CustomPaint(
                painter: _LiveBackdropArtwork(
                  primary: primary,
                  secondary: secondary,
                  motif: motif,
                ),
              ),
              Center(
                child: _LiveIdentity(
                  participants: participants,
                  logo: logo,
                  availableWidth: constraints.maxWidth,
                  scale: scale,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

enum _LiveArtworkMotif {
  orbit,
  bubbles,
  tiles;

  static _LiveArtworkMotif forKey(String key) =>
      _LiveArtworkMotif.values[_stableHash(key) %
          _LiveArtworkMotif.values.length];
}

class _LiveIdentity extends StatelessWidget {
  const _LiveIdentity({
    required this.participants,
    required this.logo,
    required this.availableWidth,
    required this.scale,
  });

  final List<Participant> participants;
  final ImageRef? logo;
  final double availableWidth;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final visible = participants.take(3).toList(growable: false);
    final imageUrls = <String>[];
    for (var index = 0; index < visible.length; index++) {
      final participantUrl = visible[index].logo?.url.trim();
      final fallbackUrl = index == 0 ? logo?.url.trim() : null;
      final imageUrl = (participantUrl?.isNotEmpty ?? false)
          ? participantUrl
          : (fallbackUrl?.isNotEmpty ?? false)
          ? fallbackUrl
          : null;
      if (imageUrl != null) imageUrls.add(imageUrl);
    }
    if (visible.isEmpty) {
      final imageUrl = logo?.url.trim();
      if (imageUrl?.isNotEmpty ?? false) imageUrls.add(imageUrl!);
    }
    if (imageUrls.isEmpty) return const SizedBox.shrink();

    final count = imageUrls.length;
    final widthPerLogo = availableWidth / (count + 0.8);
    final logoSizeFactor = count == 2 ? 0.38 : 0.32;
    final logoSize = math.min(
      math.min(scale * logoSizeFactor, widthPerLogo),
      172.0,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var index = 0; index < imageUrls.length; index++)
          _LiveIdentityTile(
            imageUrl: imageUrls[index],
            fallbackIcon: Icons.shield_outlined,
            size: logoSize,
            index: index,
          ),
      ],
    );
  }
}

class _LiveIdentityTile extends StatelessWidget {
  const _LiveIdentityTile({
    required this.imageUrl,
    required this.fallbackIcon,
    required this.size,
    required this.index,
  });

  final String? imageUrl;
  final IconData fallbackIcon;
  final double size;
  final int index;

  @override
  Widget build(BuildContext context) => SizedBox(
    key: ValueKey('live-identity-logo-$index'),
    width: size,
    height: size,
    child: _Crest(
      imageUrl: imageUrl,
      size: size,
      fallbackIcon: fallbackIcon,
      fallbackIconScale: 0.58,
      showFallbackWhileLoading: true,
    ),
  );
}

class _LiveBackdropArtwork extends CustomPainter {
  const _LiveBackdropArtwork({
    required this.primary,
    required this.secondary,
    required this.motif,
  });

  final Color primary;
  final Color secondary;
  final _LiveArtworkMotif motif;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final start = Color.lerp(AppColors.surfaceDark, primary, 0.82)!;
    final end = Color.lerp(AppColors.surfaceDark, secondary, 0.68)!;
    final middle = Color.lerp(start, end, 0.5)!;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [start, middle, end],
        ).createShader(rect),
    );

    switch (motif) {
      case _LiveArtworkMotif.orbit:
        _paintOrbit(canvas, size);
      case _LiveArtworkMotif.bubbles:
        _paintBubbles(canvas, size);
      case _LiveArtworkMotif.tiles:
        _paintTiles(canvas, size);
    }
  }

  void _paintOrbit(Canvas canvas, Size size) {
    final shortest = math.min(size.width, size.height);
    final center = Offset(size.width * 0.74, size.height * 0.34);
    canvas.drawCircle(
      center,
      shortest * 0.42,
      Paint()..color = secondary.withValues(alpha: 0.22),
    );
    canvas.drawCircle(
      center,
      shortest * 0.29,
      Paint()
        ..color = AppColors.onDark.withValues(alpha: 0.1)
        ..style = PaintingStyle.stroke
        ..strokeWidth = shortest * 0.025,
    );
    canvas.drawCircle(
      Offset(size.width * 0.18, size.height * 0.22),
      shortest * 0.055,
      Paint()..color = AppColors.onDark.withValues(alpha: 0.32),
    );
  }

  void _paintBubbles(Canvas canvas, Size size) {
    final shortest = math.min(size.width, size.height);
    final paint = Paint()..color = AppColors.onDark.withValues(alpha: 0.1);
    final bubbles = [
      (Offset(size.width * 0.16, size.height * 0.18), shortest * 0.11),
      (Offset(size.width * 0.82, size.height * 0.22), shortest * 0.17),
      (Offset(size.width * 0.75, size.height * 0.78), shortest * 0.08),
      (Offset(size.width * 0.18, size.height * 0.76), shortest * 0.05),
    ];
    for (final (center, radius) in bubbles) {
      canvas.drawCircle(center, radius, paint);
      canvas.drawCircle(
        center,
        radius * 0.62,
        Paint()
          ..color = primary.withValues(alpha: 0.12)
          ..style = PaintingStyle.stroke
          ..strokeWidth = radius * 0.12,
      );
    }
  }

  void _paintTiles(Canvas canvas, Size size) {
    final shortest = math.min(size.width, size.height);
    final paint = Paint()..color = AppColors.onDark.withValues(alpha: 0.08);

    void tile(Offset center, double width, double height, double angle) {
      canvas
        ..save()
        ..translate(center.dx, center.dy)
        ..rotate(angle)
        ..drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset.zero, width: width, height: height),
            Radius.circular(height * 0.34),
          ),
          paint,
        )
        ..restore();
    }

    tile(
      Offset(size.width * 0.14, size.height * 0.2),
      shortest * 0.5,
      shortest * 0.16,
      -0.42,
    );
    tile(
      Offset(size.width * 0.84, size.height * 0.34),
      shortest * 0.68,
      shortest * 0.22,
      0.32,
    );
    tile(
      Offset(size.width * 0.28, size.height * 0.78),
      shortest * 0.38,
      shortest * 0.12,
      0.22,
    );
  }

  @override
  bool shouldRepaint(covariant _LiveBackdropArtwork oldDelegate) =>
      oldDelegate.primary != primary ||
      oldDelegate.secondary != secondary ||
      oldDelegate.motif != motif;
}

class _Crest extends StatelessWidget {
  const _Crest({
    required this.imageUrl,
    required this.size,
    this.fallbackIcon = Icons.shield_outlined,
    this.fallbackIconScale = 0.8,
    this.showFallbackWhileLoading = false,
  });

  final String? imageUrl;
  final double size;
  final IconData fallbackIcon;
  final double fallbackIconScale;
  final bool showFallbackWhileLoading;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: imageUrl == null
        ? _CrestFallback(
            size: size,
            icon: fallbackIcon,
            iconScale: fallbackIconScale,
          )
        : CachedNetworkImage(
            imageUrl: imageUrl!,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
            fadeInDuration: Duration.zero,
            placeholder: (context, url) => showFallbackWhileLoading
                ? _CrestFallback(
                    size: size,
                    icon: fallbackIcon,
                    iconScale: fallbackIconScale,
                  )
                : const SizedBox.shrink(),
            errorWidget: (context, url, error) => _CrestFallback(
              size: size,
              icon: fallbackIcon,
              iconScale: fallbackIconScale,
            ),
          ),
  );
}

class _CrestFallback extends StatelessWidget {
  const _CrestFallback({
    required this.size,
    required this.icon,
    this.iconScale = 0.8,
  });

  final double size;
  final IconData icon;
  final double iconScale;

  @override
  Widget build(BuildContext context) => Center(
    child: Icon(
      icon,
      size: size * iconScale,
      color: AppColors.onDark.withValues(alpha: 0.55),
    ),
  );
}

class _BannerArtwork extends CustomPainter {
  const _BannerArtwork({required this.home, required this.away});

  final Color home;
  final Color away;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [home, away],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant _BannerArtwork oldDelegate) =>
      oldDelegate.home != home || oldDelegate.away != away;
}
