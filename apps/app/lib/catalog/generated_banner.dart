import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';

import '../theme/tokens.dart';
import 'artwork_cache.dart';

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
    this.eventName = '',
    this.brandAboveParticipants = false,
    this.centerContent = false,
    this.participantLogoSize = 24,
    this.showMatchup = true,
    this.showBrand = true,
    this.branding,
  });

  final List<Participant> participants;

  /// Competition or event name used when a supplied brand is unavailable.
  final String eventName;

  /// Places the brand above the participant logos for Featured Hero artwork.
  final bool brandAboveParticipants;

  /// Centers the participant and matchup group for Featured Hero artwork.
  final bool centerContent;

  /// Controls the rendered size of participant logos.
  final double participantLogoSize;

  /// Hides the matchup text when the owning hero renders the title separately.
  final bool showMatchup;

  /// Whether to render the competition brand in the artwork.
  final bool showBrand;

  final EventBranding? branding;

  @visibleForTesting
  static (Color, Color) fillsFor(
    List<Participant> participants, {
    EventBranding? branding,
  }) {
    final home = participants[0];
    final away = participants[1];
    final homeIndex = _paletteIndex(home.name);
    var awayIndex = _paletteIndex(away.name);
    if (awayIndex == homeIndex) {
      awayIndex = (awayIndex + 1) % _bannerPalette.length;
    }

    final homeFill = _legibleFill(
      _parseHex(branding?.primaryColor) ??
          _parseHex(home.color) ??
          _bannerPalette[homeIndex],
    );
    final awayFill = _legibleFill(
      _parseHex(branding?.secondaryColor) ??
          _parseHex(away.color) ??
          _bannerPalette[awayIndex],
    );
    return (homeFill, _separated(homeFill, awayFill));
  }

  @override
  Widget build(BuildContext context) {
    final (homeColor, _) = fillsFor(participants, branding: branding);
    final primaryBrand = _parseHex(branding?.primaryColor);
    final background = primaryBrand == null
        ? AppColors.surfaceDark
        : Color.lerp(AppColors.surfaceDark, _legibleFill(primaryBrand), 0.62)!;
    final accent = _accentFor(homeColor, branding);

    final crestSize = participantLogoSize;
    final brandHeight = brandAboveParticipants ? 24.0 : crestSize * 0.9;
    return Stack(
      fit: StackFit.expand,
      children: [
        CustomPaint(painter: _BannerArtwork(background: background)),
        Positioned.fill(
          child: Align(
            alignment: centerContent ? Alignment.center : Alignment.centerLeft,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.sm,
                AppSpacing.sm,
                AppSpacing.sm,
                brandAboveParticipants ? 56 : AppSpacing.sm,
              ),
              child: FractionallySizedBox(
                widthFactor: 0.72,
                child: LayoutBuilder(
                  builder: (context, constraints) => FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: centerContent
                        ? Alignment.center
                        : Alignment.centerLeft,
                    child: SizedBox(
                      width: constraints.maxWidth,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: centerContent
                            ? CrossAxisAlignment.center
                            : CrossAxisAlignment.start,
                        children: [
                          if (brandAboveParticipants && showBrand) ...[
                            Center(child: _bannerBrand(brandHeight, accent)),
                            const SizedBox(height: AppSpacing.xs),
                          ],
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _BannerTeam(
                                participant: participants[0],
                                size: crestSize,
                              ),
                              const SizedBox(width: AppSpacing.md),
                              _BannerTeam(
                                participant: participants[1],
                                size: crestSize,
                              ),
                            ],
                          ),
                          if (showMatchup) ...[
                            const SizedBox(height: AppSpacing.xs),
                            MatchupText(
                              home: participants[0].name,
                              away: participants[1].name,
                              accent: accent,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (!brandAboveParticipants && showBrand) ...[
          if (branding?.logo case final logo?)
            Positioned(
              top: AppSpacing.xs,
              right: AppSpacing.xs,
              child: _BrandLogo(
                imageUrl: logo.url,
                height: crestSize * 0.9,
                fallback: _BrandMark(
                  label: _eventBrand(eventName),
                  color: accent,
                ),
              ),
            ),
          if (branding?.logo == null)
            Positioned(
              top: AppSpacing.xs,
              right: AppSpacing.xs,
              child: _BrandMark(label: _eventBrand(eventName), color: accent),
            ),
        ],
      ],
    );
  }

  /// Returns the accent used for the `VS` separator in banner matchups.
  static Color accentFor(
    List<Participant> participants, {
    EventBranding? branding,
  }) {
    final (homeColor, _) = fillsFor(participants, branding: branding);
    return _accentFor(homeColor, branding);
  }

  Widget _bannerBrand(double height, Color accent) {
    final logo = branding?.logo;
    if (logo != null) {
      return _BrandLogo(
        imageUrl: logo.url,
        height: height,
        fallback: _BrandMark(label: _eventBrand(eventName), color: accent),
      );
    }
    return _BrandMark(label: _eventBrand(eventName), color: accent);
  }
}

Color _accentFor(Color homeColor, EventBranding? branding) {
  final primaryBrand = _parseHex(branding?.primaryColor);
  return _parseHex(branding?.secondaryColor) ??
      (primaryBrand == null
          ? AppColors.brandAccent
          : _complementaryAccent(homeColor));
}

const _brandStopTokens = {'at', 'in', 'on', 'vs', 'the', 'live'};

String _eventBrand(String title) {
  final words = RegExp(r'[A-Za-z0-9]+')
      .allMatches(title)
      .map((match) => match.group(0)!)
      .where((word) => !_brandStopTokens.contains(word.toLowerCase()))
      .toList(growable: false);
  if (words.isEmpty) return 'EVENT';
  if (words.length == 1) {
    final word = words.first.toUpperCase();
    return word.substring(0, math.min(word.length, 4));
  }
  return words.take(4).map((word) => word.substring(0, 1).toUpperCase()).join();
}

Color _complementaryAccent(Color color) {
  final hsl = HSLColor.fromColor(color);
  return HSLColor.fromAHSL(
    1,
    (hsl.hue + 150) % 360,
    math.max(hsl.saturation, 0.72),
    0.58,
  ).toColor();
}

class _BannerTeam extends StatelessWidget {
  const _BannerTeam({required this.participant, required this.size});

  final Participant participant;
  final double size;

  @override
  Widget build(BuildContext context) =>
      _Crest(imageUrl: participant.logo?.url, size: size, showFallback: false);
}

class MatchupText extends StatelessWidget {
  const MatchupText({
    super.key,
    required this.home,
    required this.away,
    required this.accent,
    this.singleLine = false,
    this.uppercase = true,
    this.textKey,
  });

  final String home;
  final String away;
  final Color accent;
  final bool singleLine;
  final bool uppercase;
  final Key? textKey;

  @override
  Widget build(BuildContext context) {
    final style = AppTypography.displaySm;
    final homeText = uppercase ? home.toUpperCase() : home;
    final awayText = uppercase ? away.toUpperCase() : away;
    if (singleLine) {
      final nameStyle = style.copyWith(
        color: AppColors.onDark,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.7,
      );
      return Text.rich(
        TextSpan(
          children: [
            TextSpan(text: homeText, style: nameStyle),
            TextSpan(
              text: ' VS ',
              style: style.copyWith(color: accent, fontWeight: FontWeight.w400),
            ),
            TextSpan(text: awayText, style: nameStyle),
          ],
        ),
        key: textKey,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _BannerName(homeText, style),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              'VS',
              style: style.copyWith(color: accent, fontWeight: FontWeight.w400),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(child: _BannerName(awayText, style)),
          ],
        ),
      ],
    );
  }
}

class _BannerName extends StatelessWidget {
  const _BannerName(this.value, this.style);

  final String value;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: FittedBox(
      alignment: Alignment.centerLeft,
      fit: BoxFit.scaleDown,
      child: Text(
        value.toUpperCase(),
        maxLines: 1,
        style: style.copyWith(
          color: AppColors.onDark,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.7,
        ),
      ),
    ),
  );
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
    this.branding,
  });

  final String seed;
  final List<Participant> participants;
  final ImageRef? logo;

  final EventBranding? branding;

  @visibleForTesting
  static (Color, Color) fillsFor(
    String seed, {
    List<Participant> participants = const [],
    EventBranding? branding,
  }) {
    final participant = participants.isEmpty ? null : participants.first;
    final primaryKey = participant?.name ?? seed;
    final primaryIndex = _paletteIndex(primaryKey);
    var secondaryIndex = _paletteIndex('$seed:secondary');
    if (secondaryIndex == primaryIndex) {
      secondaryIndex = (secondaryIndex + 1) % _bannerPalette.length;
    }

    final primary = _legibleFill(
      _parseHex(branding?.primaryColor) ??
          _parseHex(participant?.color) ??
          _bannerPalette[primaryIndex],
    );
    final secondary = _legibleFill(
      _parseHex(branding?.secondaryColor) ?? _bannerPalette[secondaryIndex],
    );
    return (primary, _separated(primary, secondary));
  }

  @override
  Widget build(BuildContext context) {
    final (primary, secondary) = fillsFor(
      seed,
      participants: participants,
      branding: branding,
    );
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
    this.showFallback = true,
  });

  final String? imageUrl;
  final double size;
  final IconData fallbackIcon;
  final double fallbackIconScale;
  final bool showFallbackWhileLoading;
  final bool showFallback;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: imageUrl == null
        ? showFallback
              ? _CrestFallback(
                  size: size,
                  icon: fallbackIcon,
                  iconScale: fallbackIconScale,
                )
              : const SizedBox.shrink()
        : CachedNetworkImage(
            imageUrl: imageUrl!,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
            fadeInDuration: Duration.zero,
            memCacheWidth: artworkCacheDimension(context, size),
            placeholder: (context, url) => showFallbackWhileLoading
                ? _CrestFallback(
                    size: size,
                    icon: fallbackIcon,
                    iconScale: fallbackIconScale,
                  )
                : const SizedBox.shrink(),
            errorWidget: (context, url, error) => showFallback
                ? _CrestFallback(
                    size: size,
                    icon: fallbackIcon,
                    iconScale: fallbackIconScale,
                  )
                : const SizedBox.shrink(),
          ),
  );
}

class _BrandLogo extends StatelessWidget {
  const _BrandLogo({
    required this.imageUrl,
    required this.height,
    required this.fallback,
  });

  final String imageUrl;
  final double height;
  final Widget fallback;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    width: height * 2.2,
    child: CachedNetworkImage(
      imageUrl: imageUrl,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      fadeInDuration: Duration.zero,
      memCacheWidth: artworkCacheDimension(context, height * 2.2),
      placeholder: (_, _) => const SizedBox.shrink(),
      errorWidget: (_, _, _) => fallback,
    ),
  );
}

class _BrandMark extends StatelessWidget {
  const _BrandMark({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Text(
    label,
    style: AppTypography.titleMd.copyWith(
      color: AppColors.onDark,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.6,
      shadows: [Shadow(color: color.withValues(alpha: 0.8), blurRadius: 12)],
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
  const _BannerArtwork({required this.background});

  final Color background;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = background);
  }

  @override
  bool shouldRepaint(covariant _BannerArtwork oldDelegate) =>
      oldDelegate.background != background;
}
