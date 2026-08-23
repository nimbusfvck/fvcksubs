import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Keeps screen-wakelock requests ordered while one or more players are alive.
class PlayerWakelockLease {
  PlayerWakelockLease._(this._id);

  static final Set<int> _activeIds = <int>{};
  static Future<void> _pending = Future<void>.value();
  static int _nextId = 0;

  final int _id;
  bool _released = false;

  static PlayerWakelockLease acquire() {
    final lease = PlayerWakelockLease._(++_nextId);
    _activeIds.add(lease._id);
    _queueSync();
    return lease;
  }

  void refresh() {
    if (!_released && _activeIds.contains(_id)) _queueSync();
  }

  void release() {
    if (_released) return;
    _released = true;
    _activeIds.remove(_id);
    _queueSync();
  }

  static void _queueSync() {
    _pending = _pending.then((_) async {
      try {
        await WakelockPlus.toggle(enable: _activeIds.isNotEmpty);
      } catch (error) {
        if (kDebugMode) {
          debugPrint('[PlayerWakelock] toggle failed: $error');
        }
      }
    });
  }
}
