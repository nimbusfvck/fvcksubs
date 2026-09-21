import 'dart:async';

import 'package:flutter/foundation.dart';

/// Serializes macOS WebKit work that creates and disposes native web views.
class WebKitLifecycleCoordinator {
  Future<void> _tail = Future<void>.value();
  int _waiting = 0;

  Future<T> run<T>(String operationName, Future<T> Function() operation) {
    final previous = _tail;
    final release = Completer<void>();
    final result = Completer<T>();
    final queuedAt = DateTime.now();
    _waiting += 1;
    _log('queued operation=$operationName waiting=$_waiting');
    _tail = release.future;

    unawaited(() async {
      await previous;
      _waiting -= 1;
      final waitMs = DateTime.now().difference(queuedAt).inMilliseconds;
      _log('started operation=$operationName wait_ms=$waitMs');
      try {
        result.complete(await operation());
      } catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      } finally {
        _log('finished operation=$operationName');
        release.complete();
      }
    }());

    return result.future;
  }

  static void _log(String message) {
    if (kDebugMode) debugPrint('[WebKitLifecycle] $message');
  }
}
