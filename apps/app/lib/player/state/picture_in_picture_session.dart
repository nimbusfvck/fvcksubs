import 'package:flutter/widgets.dart';

/// Owns the single player widget rendered in the Navigator's persistent
/// overlay. Keeping it there prevents native iOS platform-view reparenting
/// when PiP starts or expands.
class PictureInPictureSession extends ChangeNotifier {
  Widget? _player;

  Widget? get player => _player;

  void attach(Widget player) {
    _player = player;
    notifyListeners();
  }

  void detach(Widget player) {
    if (!identical(_player, player)) return;
    _player = null;
    notifyListeners();
  }
}

/// Keeps the player host in the Navigator's overlay for the lifetime of the
/// app. Navigator routes pushed later (including sheets) are inserted above
/// this entry, while the player widget itself never gets reparented during
/// PiP.
class PictureInPictureNavigatorObserver extends NavigatorObserver {
  PictureInPictureNavigatorObserver({required this.session}) {
    session.addListener(_onSessionChanged);
  }

  final PictureInPictureSession session;
  OverlayEntry? _entry;
  bool _playerWasAttached = false;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _syncHost();
    _placeHostBelowNewRoute(route);
  }

  void _onSessionChanged() {
    if (session.player == null) {
      _playerWasAttached = false;
      return;
    }
    _syncHost();
  }

  void _syncHost() {
    final overlay = navigator?.overlay;
    if (overlay == null) return;
    if (_entry == null) {
      _entry = OverlayEntry(
        builder: (_) => PictureInPictureHost(session: session),
      );
      overlay.insert(_entry!);
      _playerWasAttached = session.player != null;
      return;
    }
    // A player can be attached after a Detail route has already been pushed.
    // Move the persistent entry above that route at that point. Later routes,
    // such as a source sheet, are then naturally inserted above the player.
    if (session.player != null && !_playerWasAttached) {
      _entry!.remove();
      final entry = OverlayEntry(
        builder: (_) => PictureInPictureHost(session: session),
      );
      _entry = entry;
      _playerWasAttached = true;
      overlay.insert(entry);
    }
  }

  void _placeHostBelowNewRoute(Route<dynamic> route) {
    if (session.player == null) return;
    final navigatorState = navigator;
    final overlay = navigatorState?.overlay;
    final entry = _entry;
    if (overlay == null || entry == null) {
      return;
    }

    var hasReordered = false;

    void reorder({bool force = false}) {
      if (hasReordered && !force) return;
      if (navigatorState == null ||
          !navigatorState.mounted ||
          session.player == null ||
          !entry.mounted) {
        return;
      }
      // A modal route is already present in the overlay by the time this
      // callback runs, but `isCurrent` can briefly lag during a sheet
      // transition. The route entries themselves are the reliable anchor.
      if (!route.isActive || route.overlayEntries.isEmpty) return;
      final entries = List<OverlayEntry>.of(route.overlayEntries);
      final anchor = entries.first;
      if (!anchor.mounted) return;
      // Include the host in the moved group so its position is unambiguous:
      // route entries must be above the player, while the player entry itself
      // remains mounted so the native surface is not recreated.
      overlay.rearrange(<OverlayEntry>[entry, ...entries], below: entry);
      hasReordered = true;
    }

    // Modal routes normally install their entries before didPush is notified.
    // Reorder immediately when possible so the first transition frame cannot
    // paint the player over the sheet.
    reorder();

    // Navigator rearranges its route entries after observer notifications and
    // again when a transition completes. Cover both points so a persistent
    // player cannot end up above the newly pushed route.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      reorder();
      final animation = route is TransitionRoute<dynamic>
          ? route.animation
          : null;
      if (animation == null) return;
      void onStatusChanged(AnimationStatus status) {
        if (status != AnimationStatus.completed &&
            status != AnimationStatus.dismissed) {
          return;
        }
        animation.removeStatusListener(onStatusChanged);
        if (status == AnimationStatus.completed) {
          // Navigator may restore its route-entry order from another
          // transition listener after this callback. Reorder on the following
          // frame, once all route listeners have finished.
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => reorder(force: true),
          );
        }
      }

      animation.addStatusListener(onStatusChanged);
      if (animation.status == AnimationStatus.completed) {
        animation.removeStatusListener(onStatusChanged);
        reorder();
      }
    });
  }

  @override
  void didStartUserGesture(
    Route<dynamic> route,
    Route<dynamic>? previousRoute,
  ) {
    super.didStartUserGesture(route, previousRoute);
    _syncHost();
  }
}

/// Renders the active player above the Navigator's regular route entries.
class PictureInPictureHost extends StatelessWidget {
  const PictureInPictureHost({super.key, required this.session});

  final PictureInPictureSession session;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: session,
    builder: (context, _) {
      final player = session.player;
      return RepaintBoundary(
        child: SizedBox.expand(child: player ?? const SizedBox.shrink()),
      );
    },
  );
}
