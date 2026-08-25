import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Keeps screen-wakelock requests ordered while one or more players are alive.
class PlayerWakelockLease {
  PlayerWakelockLease._(this._id, this._owner);

  static final PlayerWakelockCoordinator _defaultCoordinator =
      PlayerWakelockCoordinator(
        (enable) => WakelockPlus.toggle(enable: enable),
      );

  final int _id;
  final PlayerWakelockCoordinator _owner;
  bool _released = false;

  static PlayerWakelockLease acquire() => _defaultCoordinator.acquire();

  void refresh() {
    if (!_released) _owner.refresh(_id);
  }

  void release() {
    if (_released) return;
    _released = true;
    _owner.release(_id);
  }
}

/// Testable coordinator for the process-wide wakelock state.
class PlayerWakelockCoordinator {
  PlayerWakelockCoordinator(this._toggle);

  final Future<void> Function(bool enable) _toggle;
  final Set<int> _activeIds = <int>{};
  Future<void> _pending = Future<void>.value();
  int _nextId = 0;

  PlayerWakelockLease acquire() {
    final lease = PlayerWakelockLease._(++_nextId, this);
    _activeIds.add(lease._id);
    _queueSync();
    return lease;
  }

  void refresh(int id) {
    if (_activeIds.contains(id)) _queueSync();
  }

  void release(int id) {
    _activeIds.remove(id);
    _queueSync();
  }

  void _queueSync() {
    _pending = _pending.then((_) async {
      try {
        await _toggle(_activeIds.isNotEmpty);
      } catch (error) {
        if (kDebugMode) {
          debugPrint('[PlayerWakelock] toggle failed: $error');
        }
      }
    });
  }
}
