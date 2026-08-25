import 'package:flutter_test/flutter_test.dart';

import 'package:fvcksubs_app/player/state/player_wakelock.dart';

class _FakeWakelockController {
  final states = <bool>[];

  Future<void> toggle(bool enable) async => states.add(enable);
}

Future<void> _drainWakelockQueue() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  test('keeps wakelock on until the last player lease is released', () async {
    final fake = _FakeWakelockController();
    final coordinator = PlayerWakelockCoordinator(fake.toggle);

    final first = coordinator.acquire();
    final second = coordinator.acquire();
    await _drainWakelockQueue();

    first.release();
    await _drainWakelockQueue();
    expect(fake.states.last, isTrue);

    second.release();
    await _drainWakelockQueue();
    expect(fake.states.last, isFalse);
  });
}
