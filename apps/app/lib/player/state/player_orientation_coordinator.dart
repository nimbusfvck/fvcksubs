import 'dart:async';

import 'package:flutter/services.dart';

typedef PreferredOrientationsSetter =
    Future<void> Function(List<DeviceOrientation> orientations);

const List<DeviceOrientation> _landscapeOrientations = [
  DeviceOrientation.landscapeLeft,
  DeviceOrientation.landscapeRight,
];

/// Keeps the viewer's landscape choice separate from the active presentation.
///
/// The choice stays with the playback session, but the platform request is
/// released while the player is minimized or in native PiP.
class PlayerOrientationCoordinator {
  PlayerOrientationCoordinator({
    PreferredOrientationsSetter? setPreferredOrientations,
  }) : _setPreferredOrientations =
           setPreferredOrientations ?? SystemChrome.setPreferredOrientations;

  final PreferredOrientationsSetter _setPreferredOrientations;
  Timer? _releaseTimer;
  bool _landscapeRequested = false;

  bool get landscapeRequested => _landscapeRequested;

  bool toggle({required bool activeFullPlayer, required bool pipBackground}) {
    _landscapeRequested = !_landscapeRequested;
    sync(activeFullPlayer: activeFullPlayer, pipBackground: pipBackground);
    return _landscapeRequested;
  }

  void sync({
    required bool activeFullPlayer,
    required bool pipBackground,
    Duration releaseDelay = Duration.zero,
  }) {
    _releaseTimer?.cancel();
    _releaseTimer = null;
    final shouldRequestLandscape =
        _landscapeRequested && activeFullPlayer && !pipBackground;
    if (!shouldRequestLandscape && releaseDelay > Duration.zero) {
      _releaseTimer = Timer(releaseDelay, () {
        _releaseTimer = null;
        unawaited(_setPreferredOrientations(const []));
      });
      return;
    }
    unawaited(
      _setPreferredOrientations(
        shouldRequestLandscape ? _landscapeOrientations : const [],
      ),
    );
  }

  void reset() {
    _releaseTimer?.cancel();
    _releaseTimer = null;
    _landscapeRequested = false;
    unawaited(_setPreferredOrientations(const []));
  }
}
