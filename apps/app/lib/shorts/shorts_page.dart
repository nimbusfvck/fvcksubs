import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';

import '../app_scope.dart';
import '../navigation/app_route_observer.dart';
import '../player/models/app_player_controller.dart';
import '../theme/breakpoints.dart';
import '../theme/tokens.dart';
import 'shorts_controller.dart';
import 'shorts_primary_action.dart';
import 'shorts_state.dart';
import 'widgets/shorts_feed_card.dart';

/// A vertically paged, autoplaying preview feed. Preview and full playback
/// are separate workflows (source plan §2.3) — Watch hands off to the app's
/// existing playback route via [watchShortsItem]; nothing here substitutes
/// for it.
class ShortsPage extends StatefulWidget {
  const ShortsPage({super.key});

  @override
  State<ShortsPage> createState() => _ShortsPageState();
}

class _ShortsPageState extends State<ShortsPage> with RouteAware {
  late final ShortsController _controller;
  bool _controllerReady = false;
  final PageController _pageController = PageController();
  int _currentIndex = 0;

  // Session-only per source plan §4: starts muted every time Shorts is
  // entered, persists across pages only within this visit. The fill mode
  // follows the same rule — a viewer's fit preference carries across pages
  // for the session but resets to letterboxed on re-entry.
  bool _muted = true;
  PlayerFitMode _fitMode = PlayerFitMode.contain;

  bool _routeVisible = true;
  ModalRoute<void>? _route;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_controllerReady) {
      _controller = ShortsController(registry: AppScope.of(context).registry);
      _controllerReady = true;
      unawaited(
        _controller.load().then((_) {
          if (mounted) _resolveAround(0);
        }),
      );
    }
    final route = ModalRoute.of<void>(context);
    if (route != null && route != _route) {
      final previous = _route;
      if (previous != null) appRouteObserver.unsubscribe(this);
      _route = route;
      appRouteObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    _pageController.dispose();
    if (_controllerReady) unawaited(_controller.close());
    super.dispose();
  }

  @override
  void didPushNext() {
    if (!mounted) return;
    setState(() => _routeVisible = false);
  }

  @override
  void didPopNext() {
    if (!mounted) return;
    setState(() => _routeVisible = true);
  }

  void _onPageChanged(int index) {
    setState(() => _currentIndex = index);
    _resolveAround(index);
  }

  void _resolveAround(int index) {
    final items = _controller.state.items;
    if (index >= 0 && index < items.length) {
      final item = items[index].item;
      unawaited(_controller.ensurePreviewResolved(item));
      unawaited(_controller.ensureDetailFetched(item));
    }
    if (index + 1 < items.length) {
      final next = items[index + 1].item;
      unawaited(_controller.ensurePreviewResolved(next));
      unawaited(_controller.ensureDetailFetched(next));
    }
  }

  /// The current item has no usable preview — skip past it lazily rather
  /// than showing a dead card. A last item with no usable preview is left
  /// as-is (artwork only); there is nothing further to skip to.
  void _advancePastUnusable(int index, int itemCount) {
    if (index != _currentIndex || index + 1 >= itemCount) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_pageController.hasClients) return;
      unawaited(
        _pageController.animateToPage(
          index + 1,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        ),
      );
    });
  }

  void _toggleMute() => setState(() => _muted = !_muted);

  void _toggleFit() => setState(() => _fitMode = _fitMode.toggled);

  Future<void> _watch(MediaItemV2 item, MediaDetailV2? detail) async {
    try {
      await watchShortsItem(context, item, detail: detail);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not start playback for "${item.title}".')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    body: BlocConsumer<ShortsController, ShortsState>(
      bloc: _controller,
      listener: (context, state) {
        if (state.items.isEmpty || !_routeVisible) return;
        final index = _currentIndex.clamp(0, state.items.length - 1);
        final current = state.items[index].item;
        if (state.previewFor(current.ref).status == PreviewStatus.unusable) {
          _advancePastUnusable(index, state.items.length);
        }
      },
      builder: (context, state) {
        if (state.items.isEmpty) {
          return switch (state.status) {
            ShortsStatus.error => _ShortsMessage(
              message: 'Could not load Shorts.',
              actionLabel: 'Retry',
              onAction: () => unawaited(_controller.retry()),
            ),
            ShortsStatus.usable ||
            ShortsStatus.empty => const _ShortsMessage(
              message: 'No previews are available right now.',
            ),
            ShortsStatus.initial ||
            ShortsStatus.loading => const Center(
              child: CircularProgressIndicator(color: AppColors.onDark),
            ),
          };
        }
        return _viewportFor(context, _feed(state));
      },
    ),
  );

  Widget _viewportFor(BuildContext context, Widget feed) =>
      AppBreakpoints.isPhone(context)
      ? feed
      : Center(child: SizedBox(width: 420, child: feed));

  Widget _feed(ShortsState state) => RefreshIndicator(
    onRefresh: _controller.refresh,
    child: PageView.builder(
      controller: _pageController,
      scrollDirection: Axis.vertical,
      onPageChanged: _onPageChanged,
      itemCount: state.items.length,
      itemBuilder: (context, index) {
        final item = state.items[index].item;
        // Only the active page gets a preview resolution to render — an
        // adjacent, not-yet-current page stays on artwork, so only one
        // native player exists at a time (source plan §3/§5).
        final isCurrent = index == _currentIndex && _routeVisible;
        return ShortsFeedCard(
          item: item,
          detail: state.detailFor(item.ref),
          previewResolution: isCurrent ? state.previewFor(item.ref) : const PreviewResolution(),
          muted: _muted,
          playing: isCurrent,
          fit: _fitMode,
          onToggleMute: _toggleMute,
          onToggleFit: _toggleFit,
          onReady: () {},
          onError: (_) => _advancePastUnusable(index, state.items.length),
          onWatch: () => _watch(item, state.detailFor(item.ref)),
        );
      },
    ),
  );
}

class _ShortsMessage extends StatelessWidget {
  const _ShortsMessage({required this.message, this.actionLabel, this.onAction});

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppTypography.bodyMd.copyWith(color: AppColors.onDarkSoft),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: AppSpacing.md),
            FilledButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    ),
  );
}
