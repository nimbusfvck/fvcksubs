import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'mini_player_session.dart';

/// Renders the player as a full-screen surface or a draggable mini-player.
class MiniPlayerHost extends StatefulWidget {
  /// Creates the persistent host for [session].
  const MiniPlayerHost({super.key, required this.session});

  /// Session whose player is rendered by this host.
  final MiniPlayerSession session;

  @override
  State<MiniPlayerHost> createState() => _MiniPlayerHostState();
}

const double _dragThreshold = 280;
const double _dragVelocityThreshold = 800;
const double _systemGestureGuard = 64;
const double _miniHorizontalMargin = 8;
const double _miniBottomMargin = 8;
const double _miniControlsHeight = 40;
const double _miniControlSize = 24;
const double _miniIconSize = 16;
const double _miniMaxWidth = 200;

class _MiniPlayerHostState extends State<MiniPlayerHost>
    with TickerProviderStateMixin {
  late final AnimationController _snapController;
  late final AnimationController _dockController;
  Animation<double>? _snapAnimation;
  Animation<Offset>? _dockAnimation;
  bool _dragAccepted = false;
  double _dragOffset = 0;
  int? _miniPointerId;
  Offset? _miniPointerDownPosition;
  bool _miniDragActive = false;
  Rect? _miniDragStartRect;
  Rect? _miniDragRect;

  MiniPlayerSession get _session => widget.session;

  @override
  void initState() {
    super.initState();
    _snapController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    )..addListener(_onSnapTick);
    _dockController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    )..addListener(_onDockTick);
  }

  @override
  void dispose() {
    _snapController.dispose();
    _dockController.dispose();
    super.dispose();
  }

  void _onSnapTick() {
    final animation = _snapAnimation;
    if (animation == null) return;
    _setDragOffset(animation.value);
  }

  void _onDockTick() {
    final animation = _dockAnimation;
    final rect = _miniDragRect;
    if (animation == null || rect == null || !mounted) return;
    setState(() {
      _miniDragRect = Rect.fromLTWH(
        animation.value.dx,
        animation.value.dy,
        rect.width,
        rect.height,
      );
    });
  }

  void _setDragOffset(double offset) {
    _dragOffset = offset.clamp(0.0, _dragThreshold);
    _session.updateDrag(_dragOffset / _dragThreshold);
  }

  void _onDragStart(DragStartDetails details) {
    if (_session.isMinimized) return;
    final topGuard =
        MediaQuery.viewPaddingOf(context).top + _systemGestureGuard;
    _dragAccepted = details.globalPosition.dy >= topGuard;
    if (_dragAccepted && _snapController.isAnimating) {
      _snapController.stop();
    }
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (!_dragAccepted) return;
    _setDragOffset(_dragOffset + details.delta.dy);
  }

  void _onDragEnd(DragEndDetails details) {
    if (!_dragAccepted) return;
    _dragAccepted = false;
    final velocity = details.primaryVelocity ?? 0;
    final shouldMinimize =
        _dragOffset >= _dragThreshold * 0.5 ||
        velocity >= _dragVelocityThreshold;
    _snapTo(shouldMinimize ? _dragThreshold : 0, minimize: shouldMinimize);
  }

  void _snapTo(double target, {required bool minimize}) {
    final start = _dragOffset;
    _snapAnimation = Tween<double>(
      begin: start,
      end: target,
    ).animate(CurvedAnimation(parent: _snapController, curve: Curves.easeOut));
    _snapController.forward(from: 0).whenComplete(() {
      if (!mounted) return;
      if (minimize) {
        _session.minimize();
      } else {
        _session.restore();
      }
    });
  }

  void _restore() {
    if (_snapController.isAnimating) _snapController.stop();
    _dragOffset = _dragThreshold;
    _snapTo(0, minimize: false);
  }

  void _stopDockAnimation() {
    if (_dockController.isAnimating) _dockController.stop();
    _dockAnimation = null;
  }

  void _onMiniPointerDown(PointerDownEvent event) {
    _stopDockAnimation();
    _miniPointerId = event.pointer;
    _miniPointerDownPosition = event.position;
    final size = MediaQuery.sizeOf(context);
    _miniDragRect = _miniRect(context, size, _session.value.dock);
    _miniDragStartRect = _miniDragRect;
    _miniDragActive = false;
  }

  void _onMiniPointerMove(PointerMoveEvent event) {
    if (event.pointer != _miniPointerId) return;
    final down = _miniPointerDownPosition;
    if (down == null) return;
    final offsetFromOrigin = event.position - down;
    if (!_miniDragActive && offsetFromOrigin.distance <= kTouchSlop) {
      return;
    }
    _miniDragActive = true;

    final start = _miniDragStartRect;
    if (start == null) return;
    final size = MediaQuery.sizeOf(context);
    setState(() {
      _miniDragRect = _clampMiniRect(start.shift(offsetFromOrigin), size);
    });
  }

  void _onMiniPointerUp(PointerUpEvent event) {
    if (event.pointer != _miniPointerId) return;
    final wasDragging = _miniDragActive;
    final rect = _miniDragRect;
    final size = MediaQuery.sizeOf(context);
    _resetMiniPointer();

    if (wasDragging && rect != null) {
      _animateMiniTo(_nearestDock(rect, size));
      return;
    }
    _miniDragRect = null;
    _restore();
  }

  void _onMiniPointerCancel(PointerCancelEvent event) {
    if (event.pointer != _miniPointerId) return;
    final rect = _miniDragRect;
    final wasDragging = _miniDragActive;
    final size = MediaQuery.sizeOf(context);
    _resetMiniPointer();
    if (wasDragging && rect != null) {
      _animateMiniTo(_nearestDock(rect, size));
    }
  }

  void _resetMiniPointer() {
    _miniPointerId = null;
    _miniPointerDownPosition = null;
    _miniDragActive = false;
    _miniDragStartRect = null;
  }

  void _animateMiniTo(MiniPlayerDock dock) {
    final size = MediaQuery.sizeOf(context);
    final begin =
        _miniDragRect ?? _miniRect(context, size, _session.value.dock);
    final end = _miniRect(context, size, dock);
    _miniDragRect = begin;
    _dockAnimation = Tween<Offset>(begin: begin.topLeft, end: end.topLeft)
        .animate(
          CurvedAnimation(parent: _dockController, curve: Curves.easeOutCubic),
        );
    _dockController.forward(from: 0).whenComplete(() {
      if (!mounted || !_dockController.isCompleted || _dockAnimation == null) {
        return;
      }
      _miniDragRect = null;
      _dockAnimation = null;
      _session.setDock(dock);
    });
  }

  Rect _miniRect(BuildContext context, Size size, MiniPlayerDock dock) {
    final width = math.min(
      _miniMaxWidth,
      size.width - _miniHorizontalMargin * 2,
    );
    final height = width * 9 / 16;
    final padding = MediaQuery.paddingOf(context);
    final top = padding.top + _miniBottomMargin;
    final bottom = size.height - padding.bottom - _miniBottomMargin - height;
    final left = _miniHorizontalMargin;
    final right = size.width - width - _miniHorizontalMargin;
    return switch (dock) {
      MiniPlayerDock.topLeft => Rect.fromLTWH(left, top, width, height),
      MiniPlayerDock.topRight => Rect.fromLTWH(right, top, width, height),
      MiniPlayerDock.bottomRight => Rect.fromLTWH(right, bottom, width, height),
      MiniPlayerDock.bottomLeft => Rect.fromLTWH(left, bottom, width, height),
    };
  }

  Rect _clampMiniRect(Rect rect, Size size) {
    final padding = MediaQuery.paddingOf(context);
    final minTop = padding.top + _miniBottomMargin;
    final maxTop =
        size.height - padding.bottom - _miniBottomMargin - rect.height;
    final minLeft = _miniHorizontalMargin;
    final maxLeft = size.width - _miniHorizontalMargin - rect.width;
    return Rect.fromLTWH(
      rect.left.clamp(minLeft, math.max(minLeft, maxLeft)),
      rect.top.clamp(minTop, math.max(minTop, maxTop)),
      rect.width,
      rect.height,
    );
  }

  MiniPlayerDock _nearestDock(Rect rect, Size size) {
    final distances = <MiniPlayerDock, double>{
      for (final dock in MiniPlayerDock.values)
        dock: (rect.center - _miniRect(context, size, dock).center)
            .distanceSquared,
    };
    return distances.entries
        .reduce(
          (closest, entry) => entry.value < closest.value ? entry : closest,
        )
        .key;
  }

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<MiniPlayerPresentationState>(
        valueListenable: _session.presentation,
        builder: (context, presentation, _) {
          final player = _session.player;
          if (player == null) return const SizedBox.shrink();
          final host = RepaintBoundary(
            child: SizedBox.expand(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _buildPlayer(context, player, presentation),
                  HeroControllerScope.none(
                    child: ValueListenableBuilder<bool>(
                      valueListenable: _session.modalOpen,
                      builder: (_, modalOpen, child) =>
                          IgnorePointer(ignoring: !modalOpen, child: child),
                      child: Navigator(
                        key: _session.modalNavigatorKey,
                        observers: [
                          _MiniPlayerModalObserver(_session.modalOpen),
                        ],
                        onGenerateRoute: (_) => PageRouteBuilder<void>(
                          opaque: false,
                          transitionDuration: Duration.zero,
                          reverseTransitionDuration: Duration.zero,
                          pageBuilder: (_, _, _) =>
                              const IgnorePointer(child: SizedBox.expand()),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
          return presentation.interactionEnabled
              ? host
              : IgnorePointer(ignoring: true, child: host);
        },
      );

  Widget _buildPlayer(
    BuildContext context,
    Widget player,
    MiniPlayerPresentationState presentation,
  ) {
    final mode = presentation.mode;
    final progress = mode == MiniPlayerMode.minimized
        ? 1.0
        : presentation.dragProgress;
    final size = MediaQuery.sizeOf(context);
    final miniRect = _miniRect(context, size, presentation.dock);
    final fullRect = Offset.zero & size;
    final rect = mode == MiniPlayerMode.minimized && _miniDragRect != null
        ? _miniDragRect!
        : Rect.lerp(fullRect, miniRect, progress)!;
    final radius = 12 * progress;

    Widget content = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Stack(
        fit: StackFit.expand,
        children: [
          player,
          if (mode == MiniPlayerMode.minimized) ...[
            Positioned.fill(
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: _onMiniPointerDown,
                onPointerMove: _onMiniPointerMove,
                onPointerUp: _onMiniPointerUp,
                onPointerCancel: _onMiniPointerCancel,
                child: const SizedBox.expand(),
              ),
            ),
            _miniBar(),
          ],
        ],
      ),
    );
    if (mode != MiniPlayerMode.minimized && presentation.interactionEnabled) {
      content = GestureDetector(
        behavior: HitTestBehavior.translucent,
        onVerticalDragStart: _onDragStart,
        onVerticalDragUpdate: _onDragUpdate,
        onVerticalDragEnd: _onDragEnd,
        onVerticalDragCancel: () => _snapTo(0, minimize: false),
        child: content,
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned(
          left: rect.left,
          top: rect.top,
          width: rect.width,
          height: rect.height,
          child: Material(
            color: mode == MiniPlayerMode.minimized
                ? Colors.black
                : Colors.transparent,
            elevation: mode == MiniPlayerMode.minimized ? 8 : 0,
            clipBehavior: Clip.antiAlias,
            borderRadius: BorderRadius.circular(radius),
            child: content,
          ),
        ),
      ],
    );
  }

  Widget _miniBar() => Positioned(
    left: 0,
    right: 0,
    top: 0,
    height: _miniControlsHeight,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ValueListenableBuilder<MiniPlayerPlaybackState>(
        valueListenable: _session.playback,
        builder: (context, playback, _) => Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _miniActionButton(
              tooltip: playback.isBuffering
                  ? 'Loading player'
                  : playback.isPlaying
                  ? 'Pause player'
                  : 'Play player',
              onPressed: playback.isBuffering ? null : _session.togglePlayback,
              icon: playback.isBuffering
                  ? Semantics(
                      label: 'Loading player',
                      child: SizedBox.square(
                        dimension: 14,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      ),
                    )
                  : Icon(
                      playback.isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      color: Colors.white,
                    ),
            ),
            _miniActionButton(
              tooltip: 'Close player',
              onPressed: _session.close,
              icon: const Icon(Icons.close_rounded, color: Colors.white),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _miniActionButton({
    required String tooltip,
    required VoidCallback? onPressed,
    required Widget icon,
  }) => Material(
    color: Colors.black.withValues(alpha: 0.72),
    shape: const CircleBorder(),
    clipBehavior: Clip.antiAlias,
    child: IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: icon,
      iconSize: _miniIconSize,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(
        width: _miniControlSize,
        height: _miniControlSize,
      ),
    ),
  );
}

class _MiniPlayerModalObserver extends NavigatorObserver {
  _MiniPlayerModalObserver(this.modalOpen);

  final ValueNotifier<bool> modalOpen;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    if (route is PopupRoute<dynamic>) modalOpen.value = true;
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    if (route is PopupRoute<dynamic>) modalOpen.value = false;
  }
}
