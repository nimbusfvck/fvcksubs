import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fvcksubs_app/widgets/media_hero_layout.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';

import '../app_scope.dart';
import '../catalog/generated_banner.dart';
import '../detail/open_versioned_item.dart';
import '../library/library_controller.dart';
import '../player/widgets/trailer_preview.dart';
import '../player/workflow/play_item.dart';
import '../theme/tokens.dart';
import '../widgets/shimmer_placeholder.dart';
import '../widgets/media_hero_card.dart';
import '../widgets/media_hero_flexible_space.dart';
import '../widgets/media_hero_summary.dart';

class FeaturedHero extends StatefulWidget {
  const FeaturedHero({super.key, required this.items});

  final List<VersionedMediaItem> items;

  @override
  State<FeaturedHero> createState() => _FeaturedHeroState();
}

/// Keeps the expanded app bar stable while the featured feed is loading.
class FeaturedHeroPlaceholder extends StatelessWidget {
  const FeaturedHeroPlaceholder({super.key});

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Stack(
      key: const Key('featured-hero-placeholder'),
      fit: StackFit.expand,
      children: [
        const Positioned.fill(child: ShimmerPlaceholder(height: null)),
        const DecoratedBox(
          decoration: BoxDecoration(gradient: MediaHeroCard.gradient),
        ),
        Positioned(
          left: AppSpacing.md,
          right: AppSpacing.md,
          bottom: MediaHeroLayout.homeSummaryBottom,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const ShimmerPlaceholder(
                width: 180,
                height: 24,
                borderRadius: BorderRadius.all(Radius.circular(4)),
              ),
              const SizedBox(height: AppSpacing.sm),
              const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ShimmerPlaceholder(
                    width: 56,
                    height: 14,
                    borderRadius: BorderRadius.all(Radius.circular(4)),
                  ),
                  SizedBox(width: AppSpacing.xs),
                  ShimmerPlaceholder(
                    width: 56,
                    height: 14,
                    borderRadius: BorderRadius.all(Radius.circular(4)),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              const ShimmerPlaceholder(
                width: 280,
                height: 14,
                borderRadius: BorderRadius.all(Radius.circular(4)),
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: AppSpacing.xs,
                children: [
                  ShimmerPlaceholder(
                    width: 92,
                    height: 40,
                    borderRadius: AppRadius.md,
                  ),
                  ShimmerPlaceholder(
                    width: 40,
                    height: 40,
                    borderRadius: AppRadius.md,
                  ),
                  ShimmerPlaceholder(
                    width: 40,
                    height: 40,
                    borderRadius: AppRadius.md,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

const _featuredIndicatorStartProgress = 0.12;
const _featuredIncomingTravelFactor = 0.09;
const _featuredOutgoingTravelFactor = 0.04;
const _featuredArtworkOverscan = 0.28;

class _FeaturedHeroState extends State<FeaturedHero>
    with SingleTickerProviderStateMixin {
  static const _noTrailerAutoSlideDelay = Duration(seconds: 8);
  static const _completedPreviewHold = Duration(milliseconds: 420);

  late final PageController _pageController;
  final ValueNotifier<bool> _dragging = ValueNotifier(false);
  final ValueNotifier<MediaRef?> _previewRef = ValueNotifier(null);
  final ValueNotifier<double?> _previewProgress = ValueNotifier(null);
  final ValueNotifier<bool> _animatePosterIn = ValueNotifier(false);
  final ValueNotifier<bool?> _previewHasTrailer = ValueNotifier(null);
  final ValueNotifier<bool> _scrolling = ValueNotifier(false);
  late final AnimationController _noTrailerAutoSlideController;
  Timer? _autoSlideTimer;
  bool _previewCompletionPending = false;
  bool _heroVisible = true;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _noTrailerAutoSlideController =
        AnimationController(vsync: this, duration: _noTrailerAutoSlideDelay)
          ..addListener(_onNoTrailerAutoSlideProgress)
          ..addStatusListener(_onNoTrailerAutoSlideStatus);
    _previewHasTrailer.addListener(_onPreviewAvailabilityChanged);
  }

  @override
  void didUpdateWidget(covariant FeaturedHero oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldRef = _page < oldWidget.items.length
        ? oldWidget.items[_page].item.ref
        : null;
    if (widget.items.isEmpty) {
      _page = 0;
      if (_pageController.hasClients && !_pageViewIsScrolling) {
        _pageController.jumpToPage(0);
      }
      return;
    }

    final matchingPage = oldRef == null
        ? -1
        : widget.items.indexWhere((entry) => entry.item.ref == oldRef);
    final nextPage = matchingPage >= 0
        ? matchingPage
        : _page.clamp(0, widget.items.length - 1).toInt();
    if (_pageViewIsScrolling) return;
    final nextRef = widget.items[nextPage].item.ref;
    if (nextRef != oldRef) {
      _autoSlideTimer?.cancel();
      _autoSlideTimer = null;
      _noTrailerAutoSlideController.reset();
      _previewProgress.value = null;
      _previewHasTrailer.value = null;
      _animatePosterIn.value = false;
    }
    _page = nextPage;
    if (_pageController.hasClients &&
        _pageController.page?.round() != nextPage) {
      _pageController.jumpToPage(nextPage);
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _noTrailerAutoSlideController.dispose();
    _autoSlideTimer?.cancel();
    _previewHasTrailer.removeListener(_onPreviewAvailabilityChanged);
    _dragging.dispose();
    _previewRef.dispose();
    _previewProgress.dispose();
    _animatePosterIn.dispose();
    _previewHasTrailer.dispose();
    _scrolling.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();
    final overlayOpacity = MediaHeroLayout.homeOverlayOpacity(
      MediaHeroCollapseScope.of(context),
      maxCollapse: MediaHeroCollapseScope.maxCollapseOf(context),
    );
    final activeItem = widget.items[_page];
    final collapse = MediaHeroCollapseScope.of(context);
    final maxCollapse = MediaHeroCollapseScope.maxCollapseOf(context);
    final heroVisible = maxCollapse <= 0 || collapse < maxCollapse;
    _updateHeroVisibility(heroVisible);
    return TickerMode(
      enabled: heroVisible,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: ClipRect(
                child: Transform.translate(
                  offset: Offset(0, -collapse * 0.28),
                  child: _FeaturedPreview(
                    item: activeItem,
                    pageController: _pageController,
                    selectedPage: _page,
                    previewRef: _previewRef,
                    previewProgress: _previewProgress,
                    animatePosterIn: _animatePosterIn,
                    previewHasTrailer: _previewHasTrailer,
                    visible: heroVisible,
                    onCompleted: _onPreviewCompleted,
                    scrolling: _scrolling,
                  ),
                ),
              ),
            ),
          ),
          NotificationListener<ScrollNotification>(
            onNotification: _onScrollNotification,
            child: PageView.builder(
              controller: _pageController,
              itemCount: widget.items.length,
              pageSnapping: true,
              itemBuilder: (context, index) => const SizedBox.expand(),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: _FeaturedPosterLayer(
                items: widget.items,
                selectedPage: _page,
                pageController: _pageController,
                dragging: _dragging,
                previewRef: _previewRef,
                animatePosterIn: _animatePosterIn,
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: ClipRect(
                child: Transform.translate(
                  offset: Offset(0, -collapse * 0.28),
                  child: const DecoratedBox(
                    decoration: BoxDecoration(gradient: MediaHeroCard.gradient),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: AppSpacing.lg,
            right: AppSpacing.md,
            bottom: MediaHeroLayout.homeSummaryBottom,
            child: Visibility(
              visible: heroVisible,
              maintainState: true,
              maintainAnimation: false,
              child: TickerMode(
                // The hero ticker pauses offscreen, but this small ticker must
                // finish the summary fade before it leaves the toolbar.
                enabled: true,
                child: AnimatedBuilder(
                  animation: Listenable.merge([_pageController, _scrolling]),
                  builder: (context, _) {
                    final page = _pageController.hasClients
                        ? _pageController.page ?? _page.toDouble()
                        : _page.toDouble();
                    final summaryPage = _scrolling.value
                        ? page.round().clamp(0, widget.items.length - 1).toInt()
                        : _page;
                    final summaryVisible =
                        !_scrolling.value || summaryPage != _page;
                    final summaryItem = widget.items[summaryPage];
                    return AnimatedSlide(
                      offset: summaryVisible
                          ? Offset.zero
                          : const Offset(0, 0.12),
                      duration: summaryVisible
                          ? Duration.zero
                          : const Duration(milliseconds: 160),
                      curve: Curves.easeInOutCubic,
                      child: AnimatedOpacity(
                        opacity: summaryVisible ? overlayOpacity : 0.0,
                        duration: summaryVisible
                            ? Duration.zero
                            : const Duration(milliseconds: 160),
                        curve: Curves.easeInOutCubic,
                        child: Align(
                          alignment: MediaHeroLayout.isLargeScreen(context)
                              ? Alignment.bottomLeft
                              : Alignment.bottomCenter,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 680),
                            child: SizedBox(
                              width: double.infinity,
                              child: _FeaturedDetails(item: summaryItem),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          if (widget.items.length > 1)
            Positioned(
              key: const Key('featured-page-indicator'),
              left: 0,
              right: 0,
              bottom: MediaHeroLayout.homeIndicatorBottom,
              child: Opacity(
                opacity: overlayOpacity,
                child: Center(
                  child: _FeaturedPageIndicator(
                    selectedPage: _page,
                    itemRefs: [for (final item in widget.items) item.item.ref],
                    previewProgress: _previewProgress,
                    previewHasTrailer: _previewHasTrailer,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  bool _onScrollNotification(ScrollNotification notification) {
    if (notification is ScrollStartNotification) {
      _autoSlideTimer?.cancel();
      _autoSlideTimer = null;
      _noTrailerAutoSlideController.stop();
      _dragging.value = true;
      _scrolling.value = true;
    } else if (notification is ScrollEndNotification) {
      final settledPage = _pageController.hasClients
          ? _pageController.page?.round() ?? _page
          : _page;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final currentRef = _page < widget.items.length
            ? widget.items[_page].item.ref
            : null;
        final settledRef = settledPage < widget.items.length
            ? widget.items[settledPage].item.ref
            : null;
        if (settledRef != currentRef) {
          _noTrailerAutoSlideController.reset();
          _previewProgress.value = null;
          _previewHasTrailer.value = null;
          _animatePosterIn.value = false;
        }
        if (settledPage != _page) setState(() => _page = settledPage);
        _dragging.value = false;
        _scrolling.value = false;
        _scheduleAutoSlide();
      });
    }
    return false;
  }

  bool get _pageViewIsScrolling =>
      _dragging.value ||
      (_pageController.hasClients &&
          _pageController.position.isScrollingNotifier.value);

  void _onPreviewAvailabilityChanged() {
    _scheduleAutoSlide();
  }

  void _onNoTrailerAutoSlideProgress() {
    if (_previewHasTrailer.value != false || !mounted) return;
    _previewProgress.value =
        _featuredIndicatorStartProgress +
        ((1.0 - _featuredIndicatorStartProgress) *
            _noTrailerAutoSlideController.value);
  }

  void _onNoTrailerAutoSlideStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) _advanceToNextPage();
  }

  void _updateHeroVisibility(bool visible) {
    if (_heroVisible == visible) return;
    _heroVisible = visible;
    if (!visible) {
      _autoSlideTimer?.cancel();
      _autoSlideTimer = null;
      _noTrailerAutoSlideController.stop();
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        if (_previewCompletionPending) {
          _onPreviewCompleted();
        } else {
          _scheduleAutoSlide();
        }
      }
    });
  }

  void _scheduleAutoSlide() {
    _autoSlideTimer?.cancel();
    _autoSlideTimer = null;
    _noTrailerAutoSlideController.stop();
    if (!_heroVisible ||
        widget.items.length < 2 ||
        _scrolling.value ||
        _dragging.value ||
        _previewHasTrailer.value != false) {
      return;
    }
    if (_noTrailerAutoSlideController.status == AnimationStatus.completed) {
      _noTrailerAutoSlideController.reset();
    }
    _noTrailerAutoSlideController.forward();
  }

  void _onPreviewCompleted() {
    _previewCompletionPending = true;
    _autoSlideTimer?.cancel();
    _autoSlideTimer = Timer(_completedPreviewHold, _advanceToNextPage);
  }

  void _advanceToNextPage() {
    _autoSlideTimer = null;
    _previewCompletionPending = false;
    if (!mounted ||
        !_heroVisible ||
        widget.items.length < 2 ||
        _scrolling.value ||
        _dragging.value ||
        !_pageController.hasClients) {
      return;
    }
    final nextPage = (_page + 1) % widget.items.length;
    unawaited(
      _pageController.animateToPage(
        nextPage,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOutCubic,
      ),
    );
  }
}

class _FeaturedPageIndicator extends StatelessWidget {
  const _FeaturedPageIndicator({
    required this.selectedPage,
    required this.itemRefs,
    required this.previewProgress,
    required this.previewHasTrailer,
  });

  final int selectedPage;
  final List<MediaRef> itemRefs;
  final ValueListenable<double?> previewProgress;
  final ValueListenable<bool?> previewHasTrailer;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([previewProgress, previewHasTrailer]),
    builder: (context, _) {
      final progress = previewProgress.value;
      final activeColor = AppColors.primaryAction;
      final inactiveColor = AppColors.onDarkSoft.withValues(alpha: 0.7);
      return Semantics(
        label: 'Featured item ${selectedPage + 1} of ${itemRefs.length}',
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.surfaceDark.withValues(alpha: 0.82),
            borderRadius: AppRadius.pill,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xs,
              vertical: AppSpacing.xxs,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var index = 0; index < itemRefs.length; index++)
                  Padding(
                    key: ValueKey(itemRefs[index]),
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: _FeaturedIndicatorDot(
                      active: index == selectedPage,
                      progress: index == selectedPage ? progress : null,
                      activeColor: activeColor,
                      inactiveColor: inactiveColor,
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _FeaturedIndicatorDot extends StatelessWidget {
  const _FeaturedIndicatorDot({
    required this.active,
    required this.progress,
    required this.activeColor,
    required this.inactiveColor,
  });

  final bool active;
  final double? progress;
  final Color activeColor;
  final Color inactiveColor;

  @override
  Widget build(BuildContext context) {
    final fill = (progress ?? (active ? 0.12 : 0.0)).clamp(0.0, 1.0).toDouble();
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      width: active ? 20 : 6,
      height: 6,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: active ? activeColor.withValues(alpha: 0.32) : inactiveColor,
        borderRadius: AppRadius.pill,
      ),
      child: active
          ? Align(
              alignment: Alignment.centerLeft,
              child: AnimatedSize(
                duration: const Duration(milliseconds: 120),
                curve: Curves.easeOutCubic,
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: 20 * fill,
                  height: 6,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: activeColor,
                      borderRadius: AppRadius.pill,
                    ),
                  ),
                ),
              ),
            )
          : null,
    );
  }
}

class _FeaturedSlide extends StatelessWidget {
  const _FeaturedSlide({required this.item, this.artworkAlignment});

  final VersionedMediaItem item;
  final Alignment? artworkAlignment;

  @override
  Widget build(BuildContext context) {
    final media = item.item;
    final fallbackArtwork = _fallbackArtwork(media);
    return RepaintBoundary(
      child: MediaHeroCard(
        item: media,
        fallback: fallbackArtwork,
        showGradient: false,
        artworkAlignment: artworkAlignment ?? Alignment.topCenter,
        foreground: const SizedBox.shrink(),
      ),
    );
  }
}

class _FeaturedPosterLayer extends StatelessWidget {
  const _FeaturedPosterLayer({
    required this.items,
    required this.selectedPage,
    required this.pageController,
    required this.dragging,
    required this.previewRef,
    required this.animatePosterIn,
  });

  final List<VersionedMediaItem> items;
  final int selectedPage;
  final PageController pageController;
  final ValueListenable<bool> dragging;
  final ValueListenable<MediaRef?> previewRef;
  final ValueListenable<bool> animatePosterIn;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([
      pageController,
      dragging,
      previewRef,
      animatePosterIn,
    ]),
    builder: (context, _) {
      final page = pageController.hasClients
          ? pageController.page ?? selectedPage.toDouble()
          : selectedPage.toDouble();
      final direction = page.compareTo(selectedPage.toDouble());
      final targetIndex = (selectedPage + direction).clamp(0, items.length - 1);
      final rawProgress = (page - selectedPage)
          .abs()
          .clamp(0.0, 1.0)
          .toDouble();
      final currentItem = items[selectedPage];
      final currentPosterOpacity = previewRef.value == currentItem.item.ref
          ? 0.0
          : 1.0;
      // A flat remote image cannot reproduce tvOS layered artwork exactly.
      // Combine restrained pan and opacity with an edge blur during the drag.
      const dragFollowThrough = 0.68;
      final posterProgress = dragging.value
          ? rawProgress * dragFollowThrough
          : rawProgress;
      const posterParallax = 0.32;
      final artworkOffset = direction < 0
          ? posterParallax * (1 - posterProgress)
          : -posterParallax * (1 - posterProgress);
      final viewportWidth =
          pageController.hasClients &&
              pageController.position.hasViewportDimension
          ? pageController.position.viewportDimension
          : MediaQuery.sizeOf(context).width;
      final artworkWidth = viewportWidth * (1 + _featuredArtworkOverscan);
      final currentTranslation =
          -(page - selectedPage) *
          viewportWidth *
          _featuredOutgoingTravelFactor;
      final targetTranslation =
          direction.sign.toDouble() *
          viewportWidth *
          _featuredIncomingTravelFactor *
          (1 - rawProgress);
      final targetOpacity = Curves.easeOutCubic.transform(rawProgress);
      final currentPosterFadeDuration = currentPosterOpacity == 0.0
          ? const Duration(milliseconds: 360)
          : animatePosterIn.value
          ? const Duration(milliseconds: 420)
          : Duration.zero;

      return Stack(
        fit: StackFit.expand,
        children: [
          Opacity(
            opacity: 1 - rawProgress * 0.22,
            child: Transform.translate(
              key: const Key('featured-parallax-current'),
              offset: Offset(currentTranslation, 0),
              child: AnimatedOpacity(
                opacity: currentPosterOpacity,
                duration: currentPosterFadeDuration,
                curve: Curves.easeInOut,
                child: _FeaturedExtendedSlide(
                  item: currentItem,
                  width: artworkWidth,
                ),
              ),
            ),
          ),
          if (direction != 0 && targetIndex != selectedPage)
            Opacity(
              opacity: targetOpacity,
              child: Transform.translate(
                key: const Key('featured-parallax-target'),
                offset: Offset(targetTranslation, 0),
                child: _FeaturedExtendedSlide(
                  item: items[targetIndex],
                  width: artworkWidth,
                  artworkAlignment: Alignment(artworkOffset, -1),
                ),
              ),
            ),
          _FeaturedEdgeBlur(
            key: const Key('featured-edge-blur'),
            page: page,
            selectedPage: selectedPage,
            viewportWidth: viewportWidth,
          ),
        ],
      );
    },
  );
}

class _FeaturedExtendedSlide extends StatelessWidget {
  const _FeaturedExtendedSlide({
    required this.item,
    required this.width,
    this.artworkAlignment,
  });

  final VersionedMediaItem item;
  final double width;
  final Alignment? artworkAlignment;

  @override
  Widget build(BuildContext context) => OverflowBox(
    alignment: Alignment.center,
    minWidth: width,
    maxWidth: width,
    child: SizedBox(
      width: width,
      child: _FeaturedSlide(item: item, artworkAlignment: artworkAlignment),
    ),
  );
}

class _FeaturedEdgeBlur extends StatelessWidget {
  const _FeaturedEdgeBlur({
    super.key,
    required this.page,
    required this.selectedPage,
    required this.viewportWidth,
  });

  final double page;
  final int selectedPage;
  final double viewportWidth;

  @override
  Widget build(BuildContext context) {
    final direction = page.compareTo(selectedPage.toDouble());
    if (direction == 0) return const SizedBox.shrink();
    final progress = (page - selectedPage).abs().clamp(0.0, 1.0).toDouble();
    // Match the blur edge to the user's swipe: a left swipe blurs the left
    // edge, while a right swipe blurs the right edge.
    final fromRight = direction > 0;
    final blurWidth = viewportWidth * (0.38 + progress * 0.16);
    final overlap = viewportWidth * 0.22;
    final totalWidth = blurWidth + overlap;
    final sigmaX = 26 + progress * 30;
    final sigmaY = 5 + progress * 7;
    final blurStart = overlap / totalWidth;
    return Align(
      alignment: fromRight ? Alignment.centerRight : Alignment.centerLeft,
      child: SizedBox(
        width: totalWidth,
        height: double.infinity,
        child: ClipRect(
          child: ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (bounds) => LinearGradient(
              begin: fromRight ? Alignment.centerLeft : Alignment.centerRight,
              end: fromRight ? Alignment.centerRight : Alignment.centerLeft,
              colors: const [Colors.transparent, Colors.white, Colors.white],
              stops: [0, blurStart, 1],
            ).createShader(bounds),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: sigmaX, sigmaY: sigmaY),
              child: const ColoredBox(color: Colors.transparent),
            ),
          ),
        ),
      ),
    );
  }
}

class _FeaturedPreview extends StatefulWidget {
  const _FeaturedPreview({
    required this.item,
    required this.pageController,
    required this.selectedPage,
    required this.previewRef,
    required this.previewProgress,
    required this.animatePosterIn,
    required this.previewHasTrailer,
    required this.visible,
    required this.onCompleted,
    required this.scrolling,
  });

  final VersionedMediaItem item;
  final PageController pageController;
  final int selectedPage;
  final ValueNotifier<MediaRef?> previewRef;
  final ValueNotifier<double?> previewProgress;
  final ValueNotifier<bool> animatePosterIn;
  final ValueNotifier<bool?> previewHasTrailer;
  final bool visible;
  final VoidCallback onCompleted;
  final ValueListenable<bool> scrolling;

  @override
  State<_FeaturedPreview> createState() => _FeaturedPreviewState();
}

class _FeaturedPreviewState extends State<_FeaturedPreview> {
  MediaTrailer? _trailer;
  MediaRef? _trailerRef;
  MediaRef? _loadedRef;
  MediaRef? _loadingRef;
  MediaTrailer? _pendingTrailer;
  MediaRef? _pendingRef;
  bool _hasPendingPreview = false;
  bool _playing = false;
  Timer? _playDelay;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    widget.scrolling.addListener(_onScrollChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loadingRef == null && _loadedRef != widget.item.item.ref) {
      _loadPreview();
    }
  }

  @override
  void didUpdateWidget(covariant _FeaturedPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrolling != widget.scrolling) {
      oldWidget.scrolling.removeListener(_onScrollChanged);
      widget.scrolling.addListener(_onScrollChanged);
    }
    if (oldWidget.item.item.ref != widget.item.item.ref) _loadPreview();
  }

  @override
  void dispose() {
    _playDelay?.cancel();
    widget.scrolling.removeListener(_onScrollChanged);
    super.dispose();
  }

  void _onScrollChanged() {
    if (!widget.scrolling.value) _commitPendingPreview();
  }

  void _loadPreview() {
    final ref = widget.item.item.ref;
    _playDelay?.cancel();
    _playDelay = null;
    _loadedRef = ref;
    _loadingRef = ref;
    _pendingTrailer = null;
    _pendingRef = null;
    _hasPendingPreview = false;
    final future = _loadDetail();
    final generation = ++_loadGeneration;
    if (future == null) {
      _loadingRef = null;
      _trailer = null;
      _trailerRef = null;
      _playing = false;
      _publishPreviewHasTrailer(false, generation);
      _publishPreviewRef(null, generation);
      return;
    }
    unawaited(_resolvePreview(future, ref, generation));
  }

  Future<void> _resolvePreview(
    Future<MediaDetailV2> future,
    MediaRef ref,
    int generation,
  ) async {
    try {
      final detail = await future;
      if (!mounted || generation != _loadGeneration) return;
      final trailer = _autoplayTrailer(detail);
      _loadingRef = null;
      if (widget.scrolling.value) {
        _pendingTrailer = trailer;
        _pendingRef = ref;
        _hasPendingPreview = true;
        return;
      }
      _applyPreview(trailer, ref, generation);
    } catch (_) {
      if (!mounted || generation != _loadGeneration) return;
      _loadingRef = null;
      if (widget.scrolling.value) {
        _pendingTrailer = null;
        _pendingRef = ref;
        _hasPendingPreview = true;
        return;
      }
      _applyPreview(null, ref, generation);
    }
  }

  void _commitPendingPreview() {
    if (!_hasPendingPreview || _pendingRef != widget.item.item.ref) return;
    final trailer = _pendingTrailer;
    final ref = _pendingRef!;
    _pendingTrailer = null;
    _pendingRef = null;
    _hasPendingPreview = false;
    _applyPreview(trailer, ref, _loadGeneration);
  }

  void _applyPreview(MediaTrailer? trailer, MediaRef ref, int generation) {
    if (!mounted || generation != _loadGeneration) return;
    widget.previewProgress.value = null;
    widget.animatePosterIn.value = false;
    _publishPreviewHasTrailer(trailer != null, generation);
    final autoplayEnabled = AppScope.of(
      context,
    ).previewAutoplayPreferenceController.enabled;
    final delayPlayback =
        autoplayEnabled &&
        trailer != null &&
        _trailerRef != null &&
        _trailerRef != ref;
    setState(() {
      _trailer = trailer;
      _trailerRef = trailer == null ? null : ref;
      _playing = trailer != null && autoplayEnabled && !delayPlayback;
    });
    if (trailer == null) {
      _publishPreviewRef(null, generation);
      return;
    }
    if (!autoplayEnabled) {
      _publishPreviewRef(null, generation);
      return;
    }
    if (!delayPlayback) {
      _publishPreviewRef(ref, generation);
      return;
    }
    _playDelay = Timer(const Duration(milliseconds: 180), () {
      if (!mounted || generation != _loadGeneration || _trailerRef != ref) {
        return;
      }
      setState(() => _playing = true);
    });
  }

  void _onTrailerPlaying(bool playing) {
    if (!mounted || _trailerRef == null) return;
    final autoplayEnabled = AppScope.of(
      context,
    ).previewAutoplayPreferenceController.enabled;
    if (!autoplayEnabled) {
      _publishPreviewRef(null, _loadGeneration);
      return;
    }
    if (!playing) return;
    // Start fading the poster only once TrailerPreview's autoplay timer has
    // actually started native playback.
    _publishPreviewRef(_trailerRef, _loadGeneration);
  }

  void _onTrailerProgress(double? progress) {
    if (!mounted) return;
    if (progress == null) {
      widget.previewProgress.value = null;
      return;
    }
    final normalized = progress.clamp(0.0, 1.0).toDouble();
    widget.previewProgress.value =
        _featuredIndicatorStartProgress +
        ((1.0 - _featuredIndicatorStartProgress) * normalized);
  }

  void _onTrailerCompleted() {
    if (!mounted || _trailerRef == null) return;
    final generation = _loadGeneration;
    setState(() => _playing = false);
    widget.previewProgress.value = 1.0;
    widget.animatePosterIn.value = true;
    _publishPreviewRef(null, generation);
    widget.onCompleted();
  }

  void _publishPreviewRef(MediaRef? ref, int generation) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _loadGeneration) return;
      widget.previewRef.value = ref;
    });
  }

  void _publishPreviewHasTrailer(bool hasTrailer, int generation) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _loadGeneration) return;
      widget.previewHasTrailer.value = hasTrailer;
    });
  }

  Future<MediaDetailV2>? _loadDetail() {
    final item = widget.item;
    if (item.item is! VideoItemV2 && item.item is! SeriesItemV2) return null;
    final registry = AppScope.of(context).registry;
    final manifest = registry.installed.where(
      (entry) => entry.id == item.item.ref.extensionId,
    );
    if (manifest.isEmpty || manifest.first.apiVersion < 2) return null;
    return registry.meta(item.item.ref);
  }

  @override
  Widget build(BuildContext context) {
    final trailer = _trailer;
    if (trailer == null) return const SizedBox.shrink();
    // Keep the player visible and playing while the poster layer transitions.
    // If the selected item changes, the previous trailer stays here until the
    // new detail resolves and the poster can cover the handoff.
    return AnimatedBuilder(
      animation: widget.pageController,
      builder: (context, child) {
        final page = widget.pageController.hasClients
            ? widget.pageController.page ?? widget.selectedPage.toDouble()
            : widget.selectedPage.toDouble();
        final viewportWidth =
            widget.pageController.hasClients &&
                widget.pageController.position.hasViewportDimension
            ? widget.pageController.position.viewportDimension
            : MediaQuery.sizeOf(context).width;
        final translation =
            -(page - widget.selectedPage) *
            viewportWidth *
            _featuredOutgoingTravelFactor;
        return Transform.translate(
          offset: Offset(translation, 0),
          child: child,
        );
      },
      child: TrailerPreview(
        trailer: trailer,
        playing: _playing && widget.visible,
        onPlayingChanged: _onTrailerPlaying,
        onProgressChanged: _onTrailerProgress,
        onCompleted: _onTrailerCompleted,
      ),
    );
  }
}

MediaTrailer? _autoplayTrailer(MediaDetailV2 detail) {
  for (final trailer in detail.trailers) {
    if (trailer.mimeType?.toLowerCase().startsWith('video/') ?? false) {
      return trailer;
    }
  }
  return null;
}

Widget _fallbackArtwork(MediaItemV2 item) => switch (item) {
  EventItemV2(:final participants, :final branding, :final subtitle)
      when participants.length == 2 =>
    GeneratedBanner(
      participants: participants,
      eventName: subtitle ?? '',
      brandAboveParticipants: true,
      centerContent: true,
      participantLogoSize: 64,
      showMatchup: false,
      showBrand: false,
      branding: branding,
    ),
  EventItemV2(:final participants, :final branding) => GeneratedLiveArtwork(
    seed: _artworkSeed(item),
    participants: participants,
    logo: item.artwork?.logo,
    branding: branding,
  ),
  ChannelItemV2() => GeneratedLiveArtwork(
    seed: _artworkSeed(item),
    logo: item.artwork?.logo,
  ),
  _ => const ColoredBox(
    color: AppColors.surfaceDarkElevated,
    child: Icon(Icons.movie_outlined, color: AppColors.onDarkSoft, size: 48),
  ),
};

String _artworkSeed(MediaItemV2 item) {
  final ref = item.ref;
  return '${ref.extensionId}|${ref.providerId}|${ref.id}|${item.title}';
}

class _FeaturedDetails extends StatelessWidget {
  const _FeaturedDetails({required this.item});

  final VersionedMediaItem item;

  @override
  Widget build(BuildContext context) {
    final media = item.item;
    final alignStart = MediaHeroLayout.isLargeScreen(context);
    return MediaHeroSummary(
      item: media,
      alignStart: alignStart,
      titleTextKey: const Key('featured-title-text'),
      titleLogoKey: const Key('featured-title-logo'),
      actions: Wrap(
        alignment: alignStart ? WrapAlignment.start : WrapAlignment.center,
        spacing: AppSpacing.xs,
        runSpacing: AppSpacing.xs,
        children: [
          FilledButton.icon(
            key: const Key('featured-play'),
            onPressed: () => unawaited(_play(context)),
            icon: const Icon(Icons.play_arrow),
            label: const Text('Watch Now'),
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(borderRadius: AppRadius.lg),
            ),
          ),
          BlocBuilder<LibraryController, LibraryState>(
            bloc: AppScope.of(context).libraryController,
            builder: (context, state) {
              final favorite = state.isFavorite(media.ref);
              return IconButton(
                key: const Key('featured-favorite'),
                tooltip: favorite ? 'In favorites' : 'Add to favorites',
                style: IconButton.styleFrom(
                  foregroundColor: AppColors.onDark,
                  side: const BorderSide(color: AppColors.outlineDark),
                  shape: RoundedRectangleBorder(borderRadius: AppRadius.lg),
                ),
                icon: Icon(favorite ? Icons.check : Icons.add),
                onPressed: () => AppScope.of(
                  context,
                ).libraryController.toggleFavorite(media),
              );
            },
          ),
          IconButton(
            key: const Key('featured-info'),
            tooltip: 'Open details',
            style: IconButton.styleFrom(
              foregroundColor: AppColors.onDark,
              backgroundColor: AppColors.surfaceDarkElevated.withValues(
                alpha: 0.86,
              ),
              side: const BorderSide(color: AppColors.outlineDark),
              shape: RoundedRectangleBorder(borderRadius: AppRadius.lg),
            ),
            icon: const Icon(Icons.info_outline),
            onPressed: () => openVersionedItem(context, item),
          ),
        ],
      ),
    );
  }

  Future<void> _play(BuildContext context) {
    return playItemV2(context, item.item);
  }
}
