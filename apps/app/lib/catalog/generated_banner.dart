import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';

import '../theme/tokens.dart';
import 'media_card.dart';

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

enum BannerPattern {
  sunburst,

  chevrons,

  stripes,

  halftone,

  arcs;

  static BannerPattern forKey(String? key) => key == null
      ? BannerPattern.sunburst
      : BannerPattern.values[_stableHash(key) % BannerPattern.values.length];
}

class GeneratedBanner extends StatelessWidget {
  const GeneratedBanner({
    super.key,
    required this.participants,
    this.status = LiveStatus.unknown,
    this.patternKey,
  });

  final List<Participant> participants;

  final LiveStatus status;

  final String? patternKey;

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
    final pattern = BannerPattern.forKey(patternKey);

    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        final crestSize = math.min(height * 0.5, 60.0);

        return Stack(
          fit: StackFit.expand,
          children: [
            CustomPaint(
              painter: _BannerArtwork(
                home: homeColor,
                away: awayColor,
                pattern: pattern,
              ),
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
            if (status == LiveStatus.live)
              const Positioned(
                left: AppSpacing.xs,
                top: AppSpacing.xs,
                child: LiveBadge(),
              )
            else if (status == LiveStatus.scheduled)
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
/// logos are used when present; otherwise the title-derived palette and a
/// broadcast mark keep the artwork useful without provider-specific assets.
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
  ribbons,
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
    if (visible.isEmpty) {
      final size = math.min(scale * 0.3, 128.0);
      return _LiveIdentityTile(
        imageUrl: logo?.url,
        fallbackIcon: Icons.live_tv_outlined,
        size: size,
        angle: -0.04,
      );
    }

    final count = visible.length;
    final widthPerTile = availableWidth / (count * 1.25 + 0.6);
    final tileSize = math.min(math.min(scale * 0.3, widthPerTile), 128.0);
    const angles = [-0.07, 0.05, -0.035];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var index = 0; index < visible.length; index++)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: tileSize * 0.045),
            child: _LiveIdentityTile(
              imageUrl:
                  visible[index].logo?.url ?? (index == 0 ? logo?.url : null),
              fallbackIcon: Icons.shield_outlined,
              size: tileSize,
              angle: angles[index],
            ),
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
    required this.angle,
  });

  final String? imageUrl;
  final IconData fallbackIcon;
  final double size;
  final double angle;

  @override
  Widget build(BuildContext context) => Transform.rotate(
    angle: angle,
    child: Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.14),
      decoration: BoxDecoration(
        color: AppColors.surfaceDark.withValues(alpha: 0.38),
        borderRadius: BorderRadius.circular(size * 0.26),
        border: Border.all(color: AppColors.onDark.withValues(alpha: 0.16)),
        boxShadow: [
          BoxShadow(
            color: AppColors.surfaceDark.withValues(alpha: 0.24),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: _Crest(
        imageUrl: imageUrl,
        size: size * 0.72,
        fallbackIcon: fallbackIcon,
        showFallbackWhileLoading: true,
      ),
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
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [start, end, AppColors.surfaceDark],
          stops: const [0, 0.58, 1],
        ).createShader(rect),
    );

    switch (motif) {
      case _LiveArtworkMotif.orbit:
        _paintOrbit(canvas, size);
      case _LiveArtworkMotif.ribbons:
        _paintRibbons(canvas, size);
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

  void _paintRibbons(Canvas canvas, Size size) {
    final first = Path()
      ..moveTo(-size.width * 0.12, size.height * 0.24)
      ..cubicTo(
        size.width * 0.2,
        size.height * 0.02,
        size.width * 0.62,
        size.height * 0.46,
        size.width * 1.12,
        size.height * 0.16,
      )
      ..lineTo(size.width * 1.12, size.height * 0.34)
      ..cubicTo(
        size.width * 0.62,
        size.height * 0.64,
        size.width * 0.2,
        size.height * 0.2,
        -size.width * 0.12,
        size.height * 0.42,
      )
      ..close();
    canvas.drawPath(
      first,
      Paint()..color = AppColors.onDark.withValues(alpha: 0.09),
    );

    final second = Path()
      ..moveTo(-size.width * 0.15, size.height * 0.68)
      ..quadraticBezierTo(
        size.width * 0.45,
        size.height * 0.42,
        size.width * 1.12,
        size.height * 0.78,
      )
      ..lineTo(size.width * 1.12, size.height)
      ..quadraticBezierTo(
        size.width * 0.45,
        size.height * 0.64,
        -size.width * 0.15,
        size.height * 0.9,
      )
      ..close();
    canvas.drawPath(second, Paint()..color = primary.withValues(alpha: 0.2));
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
    this.showFallbackWhileLoading = false,
  });

  final String? imageUrl;
  final double size;
  final IconData fallbackIcon;
  final bool showFallbackWhileLoading;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: imageUrl == null
        ? _CrestFallback(size: size, icon: fallbackIcon)
        : CachedNetworkImage(
            imageUrl: imageUrl!,
            fit: BoxFit.contain,
            fadeInDuration: Duration.zero,
            placeholder: (context, url) => showFallbackWhileLoading
                ? _CrestFallback(size: size, icon: fallbackIcon)
                : const SizedBox.shrink(),
            errorWidget: (context, url, error) =>
                _CrestFallback(size: size, icon: fallbackIcon),
          ),
  );
}

class _CrestFallback extends StatelessWidget {
  const _CrestFallback({required this.size, required this.icon});

  final double size;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Center(
    child: Icon(
      icon,
      size: size * 0.8,
      color: AppColors.onDark.withValues(alpha: 0.55),
    ),
  );
}

class _BannerArtwork extends CustomPainter {
  const _BannerArtwork({
    required this.home,
    required this.away,
    required this.pattern,
  });

  final Color home;
  final Color away;
  final BannerPattern pattern;

  static final Paint _ink = Paint()
    ..color = Colors.white.withValues(alpha: 0.075);

  static const double _skewFactor = 0.5;

  static const double _jagFactor = 0.055;

  static const List<double> _jags = [0, 1, -0.65, 0.45, 0];

  List<Offset> _split(Size size) {
    final skew = size.height * _skewFactor;
    final topX = size.width / 2 + skew / 2;
    final jag = size.width * _jagFactor;
    return [
      for (var i = 0; i < _jags.length; i++)
        () {
          final t = i / (_jags.length - 1);
          return Offset(topX - skew * t + jag * _jags[i], size.height * t);
        }(),
    ];
  }

  @override
  void paint(Canvas canvas, Size size) {
    final split = _split(size);
    final center = Offset(size.width / 2, size.height / 2);

    final left = Path()..moveTo(0, 0);
    for (final point in split) {
      left.lineTo(point.dx, point.dy);
    }
    left
      ..lineTo(0, size.height)
      ..close();

    final right = Path()..moveTo(split.first.dx, split.first.dy);
    right
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height);
    for (final point in split.reversed) {
      right.lineTo(point.dx, point.dy);
    }
    right.close();

    canvas.drawPath(left, Paint()..color = home);
    canvas.drawPath(right, Paint()..color = away);

    _paintPattern(canvas, size, left, center, -1);
    _paintPattern(canvas, size, right, center, 1);

    final edge = Path()..moveTo(split.first.dx, split.first.dy);
    for (final point in split.skip(1)) {
      edge.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(
      edge,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.32)
        ..strokeWidth = 1.5
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke,
    );
  }

  void _paintPattern(
    Canvas canvas,
    Size size,
    Path region,
    Offset center,
    int direction,
  ) {
    canvas
      ..save()
      ..clipPath(region);
    switch (pattern) {
      case BannerPattern.sunburst:
        _sunburst(canvas, size, center);
      case BannerPattern.chevrons:
        _chevrons(canvas, size, center, direction);
      case BannerPattern.stripes:
        _stripes(canvas, size, direction);
      case BannerPattern.halftone:
        _halftone(canvas, size, center);
      case BannerPattern.arcs:
        _arcs(canvas, size, center);
    }
    canvas.restore();
  }

  void _sunburst(Canvas canvas, Size size, Offset center) {
    const wedges = 18;
    final radius = size.width + size.height;

    for (var i = 0; i < wedges; i += 2) {
      final from = i * 2 * math.pi / wedges;
      final to = (i + 1) * 2 * math.pi / wedges;
      canvas.drawPath(
        Path()
          ..moveTo(center.dx, center.dy)
          ..lineTo(
            center.dx + radius * math.cos(from),
            center.dy + radius * math.sin(from),
          )
          ..lineTo(
            center.dx + radius * math.cos(to),
            center.dy + radius * math.sin(to),
          )
          ..close(),
        _ink,
      );
    }
  }

  void _chevrons(Canvas canvas, Size size, Offset center, int direction) {
    final paint = Paint()
      ..color = _ink.color
      ..strokeWidth = size.height * 0.055
      ..strokeJoin = StrokeJoin.miter
      ..style = PaintingStyle.stroke;
    final step = size.height * 0.24;
    final reach = size.height * 0.34;

    for (var i = 1; i <= 5; i++) {
      final tip = center.dx + direction * i * step;
      canvas.drawPath(
        Path()
          ..moveTo(tip - direction * reach, center.dy - size.height * 0.6)
          ..lineTo(tip, center.dy)
          ..lineTo(tip - direction * reach, center.dy + size.height * 0.6),
        paint,
      );
    }
  }

  void _stripes(Canvas canvas, Size size, int direction) {
    final skew = size.height * _skewFactor;
    final topX = size.width / 2 + skew / 2;
    final paint = Paint()
      ..color = _ink.color
      ..strokeWidth = size.height * 0.07
      ..style = PaintingStyle.stroke;
    final gap = size.height * 0.19;

    for (var i = 1; i <= 7; i++) {
      final offset = direction * i * gap;
      canvas.drawLine(
        Offset(topX + offset, 0),
        Offset(topX - skew + offset, size.height),
        paint,
      );
    }
  }

  void _halftone(Canvas canvas, Size size, Offset center) {
    final spacing = size.height * 0.15;
    final maxDistance = size.width / 2 + size.height / 2;

    for (var y = spacing / 2; y < size.height; y += spacing) {
      for (var x = spacing / 2; x < size.width; x += spacing) {
        final distance = (Offset(x, y) - center).distance;
        final scale = (1 - distance / maxDistance).clamp(0.25, 1.0);
        canvas.drawCircle(Offset(x, y), spacing * 0.22 * scale, _ink);
      }
    }
  }

  void _arcs(Canvas canvas, Size size, Offset center) {
    final paint = Paint()
      ..color = _ink.color
      ..strokeWidth = size.height * 0.06
      ..style = PaintingStyle.stroke;
    final step = size.height * 0.2;
    final limit = size.width / 2 + size.height / 2;

    for (var radius = step; radius < limit; radius += step) {
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _BannerArtwork oldDelegate) =>
      oldDelegate.home != home ||
      oldDelegate.away != away ||
      oldDelegate.pattern != pattern;
}
