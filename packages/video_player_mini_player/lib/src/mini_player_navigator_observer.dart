import 'package:flutter/material.dart';

import 'mini_player_host.dart';
import 'mini_player_session.dart';

/// Keeps the active player below newly pushed routes while it is minimized.
class MiniPlayerNavigatorObserver extends NavigatorObserver {
  /// Creates an observer that installs a persistent host for [session].
  MiniPlayerNavigatorObserver({required this.session}) {
    session.addListener(_onSessionChanged);
  }

  /// Session whose routes are being observed.
  final MiniPlayerSession session;
  OverlayEntry? _entry;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _syncHost();
    _placeHostBelowNewRoute(route);
  }

  void _onSessionChanged() {
    _syncHost();
  }

  void _syncHost() {
    final overlay = navigator?.overlay;
    if (overlay == null) return;
    // MiniPlayerHost listens to the session itself. Keep this entry stable so
    // attaching a PlayerPage with a GlobalKey cannot briefly mount the same
    // player and modal navigator in both the old and new hosts.
    if (_entry == null) {
      _entry = OverlayEntry(builder: (_) => MiniPlayerHost(session: session));
      overlay.insert(_entry!);
    }
  }

  void _placeHostBelowNewRoute(Route<dynamic> route) {
    if (session.player == null) return;
    final navigatorState = navigator;
    final overlay = navigatorState?.overlay;
    final entry = _entry;
    if (overlay == null || entry == null) return;

    var hasReordered = false;

    void reorder({bool force = false}) {
      if (hasReordered && !force) return;
      if (navigatorState == null ||
          !navigatorState.mounted ||
          session.player == null ||
          !entry.mounted) {
        return;
      }
      if (!route.isActive || route.overlayEntries.isEmpty) return;
      final entries = List<OverlayEntry>.of(route.overlayEntries);
      final anchor = entries.first;
      if (!anchor.mounted) return;
      overlay.rearrange(<OverlayEntry>[entry, ...entries], below: entry);
      hasReordered = true;
    }

    reorder();
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
