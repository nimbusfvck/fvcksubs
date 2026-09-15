import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';

import '../app_scope.dart';
import '../catalog/catalog_cache.dart';
import '../detail/open_versioned_item.dart';
import '../theme/tokens.dart';
import '../widgets/centered_content.dart';

class SurpriseMeBanner extends StatefulWidget {
  const SurpriseMeBanner({
    super.key,
    required this.registry,
    required this.catalogCache,
    this.refreshToken = 0,
  });

  final ExtensionRegistry registry;
  final CatalogCache catalogCache;
  final int refreshToken;

  @override
  State<SurpriseMeBanner> createState() => _SurpriseMeBannerState();
}

class _SurpriseMeBannerState extends State<SurpriseMeBanner> {
  final Random _random = Random();
  _SurpriseCandidate? _candidate;
  List<_SurpriseCandidate> _candidates = const [];
  bool _loading = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_candidates.isEmpty && !_loading) unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant SurpriseMeBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) {
      _candidates = const [];
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    if (_loading) return;
    _loading = true;
    final category = widget.registry.categories.cast<String?>().firstWhere(
      (value) => value?.toLowerCase() == 'all',
      orElse: () => null,
    );
    if (category == null) {
      _loading = false;
      return;
    }

    final scope = AppScope.of(context);
    final plugins = widget.registry.pluginsFor(category);
    final pluginId = scope.pluginController.resolve([
      for (final plugin in plugins) plugin.id,
    ]);
    if (pluginId == null) {
      _loading = false;
      return;
    }

    final candidates = <_SurpriseCandidate>[];
    final bindings = [
      for (final binding in widget.registry.catalogsFor(category))
        if (binding.extensionId == pluginId) binding,
    ];
    for (final binding in bindings) {
      try {
        final page = await widget.catalogCache.fetchCatalog(
          widget.registry,
          binding,
          category: category,
        );
        for (final section in page.sections) {
          for (final entry in section.items) {
            final kind = entry.item.kind;
            if (kind != MediaKindV2.video && kind != MediaKindV2.series) {
              continue;
            }
            candidates.add(_SurpriseCandidate(entry, binding.contentRating));
          }
        }
      } catch (_) {
        // An optional banner should stay usable when one catalog fails.
      }
    }

    if (!mounted) return;
    final unique = <MediaRef, _SurpriseCandidate>{
      for (final candidate in candidates) candidate.item.item.ref: candidate,
    };
    final values = unique.values.toList();
    setState(() {
      _candidates = values;
      _candidate = values.isEmpty
          ? null
          : values[_random.nextInt(values.length)];
      _loading = false;
    });
  }

  void _surprise() {
    if (_candidates.isEmpty) {
      unawaited(_load());
      return;
    }
    final next = _candidates[_random.nextInt(_candidates.length)];
    setState(() => _candidate = next);
    openVersionedItem(context, next.item, contentRating: next.contentRating);
  }

  @override
  Widget build(BuildContext context) {
    final artworkCandidates = [
      ...?(_candidate == null ? null : <_SurpriseCandidate>[_candidate!]),
      ..._candidates.where((candidate) => candidate != _candidate).take(9),
    ];
    return CenteredContent(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: SizedBox(
          height: 96,
          child: ClipRRect(
            borderRadius: AppRadius.lg,
            child: ColoredBox(
              color: Colors.transparent,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                  ),
                  child: Row(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(
                          right: AppSpacing.lg,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Not sure what to watch?',
                              style: AppTypography.bodySm.copyWith(
                                color: AppColors.onDark,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            FilledButton.icon(
                              onPressed: _loading ? null : _surprise,
                              icon: const Icon(Icons.shuffle_rounded),
                              label: const Text('Surprise Me'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Flexible(
                        child: SizedBox(
                          width: 190,
                          height: 96,
                          child: _ArtworkStack(candidates: artworkCandidates),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ArtworkStack extends StatelessWidget {
  const _ArtworkStack({required this.candidates});

  final List<_SurpriseCandidate> candidates;

  @override
  Widget build(BuildContext context) {
    final entries = candidates
        .map((candidate) => candidate.item.item.artwork?.portrait)
        .whereType<ImageRef>()
        .take(10)
        .toList();
    if (entries.isEmpty) return const SizedBox.shrink();

    return Align(
      alignment: Alignment.center,
      child: SizedBox(
        width: 190,
        height: 96,
        child: Stack(
          alignment: Alignment.center,
          children: [
            for (var index = 0; index < entries.length; index++)
              Transform.translate(
                offset: Offset((index - (entries.length - 1) / 2) * 13, 0),
                child: Transform.rotate(
                  angle: (index - (entries.length - 1) / 2) * 0.02,
                  child: _ArtworkCard(
                    image: entries[index],
                    opacity: index == entries.length - 1 ? 0.58 : 0.3,
                    blurCenter: index == entries.length - 1,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ArtworkCard extends StatelessWidget {
  const _ArtworkCard({
    required this.image,
    required this.opacity,
    required this.blurCenter,
  });

  final ImageRef image;
  final double opacity;
  final bool blurCenter;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: opacity,
    child: ClipRRect(
      borderRadius: AppRadius.md,
      child: Container(
        width: 46,
        height: 66,
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.onDark.withValues(alpha: 0.16)),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            CachedNetworkImage(
              imageUrl: image.url,
              fit: BoxFit.cover,
              placeholder: (_, _) =>
                  const ColoredBox(color: AppColors.surfaceDarkHighest),
              errorWidget: (_, _, _) =>
                  const ColoredBox(color: AppColors.surfaceDarkHighest),
            ),
            if (blurCenter)
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                    vertical: AppSpacing.xs,
                  ),
                  child: ClipRRect(
                    borderRadius: AppRadius.sm,
                    child: ImageFiltered(
                      imageFilter: ImageFilter.blur(sigmaX: 9, sigmaY: 9),
                      child: CachedNetworkImage(
                        imageUrl: image.url,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class _SurpriseCandidate {
  const _SurpriseCandidate(this.item, this.contentRating);

  final VersionedMediaItem item;
  final ContentRating contentRating;
}
