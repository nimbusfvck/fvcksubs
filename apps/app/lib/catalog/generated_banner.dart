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

int _paletteIndex(String name) => name.hashCode.abs() % _bannerPalette.length;

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
      : BannerPattern.values[key.hashCode.abs() % BannerPattern.values.length];
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

class _Crest extends StatelessWidget {
  const _Crest({required this.imageUrl, required this.size});

  final String? imageUrl;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: imageUrl == null
        ? _CrestFallback(size: size)
        : CachedNetworkImage(
            imageUrl: imageUrl!,
            fit: BoxFit.contain,
            fadeInDuration: Duration.zero,
            placeholder: (context, url) => const SizedBox.shrink(),
            errorWidget: (context, url, error) => _CrestFallback(size: size),
          ),
  );
}

class _CrestFallback extends StatelessWidget {
  const _CrestFallback({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) => Center(
    child: Icon(
      Icons.shield_outlined,
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
