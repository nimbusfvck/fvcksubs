import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_app/player/models/app_player_controller.dart';
import 'package:fvcksubs_app/player/state/player_controls_cubit.dart';

import 'support/harness.dart';

void main() {
  test(
    'pending seek retains intent without overwriting observed position',
    () async {
      final controller = _SeekingController();
      final cubit = PlayerControlsCubit();
      expect(cubit.state.pendingSeekPosition, isNull);
      final seek = cubit.seek(controller, const Duration(seconds: 30));
      expect(cubit.state.pendingSeekPosition, const Duration(seconds: 30));
      expect(cubit.state.value.position, Duration.zero);
      controller.current.value = controller.current.value.copyWith(
        position: const Duration(seconds: 30),
      );
      controller.requests.single.complete();
      await seek;
      expect(cubit.state.pendingSeekPosition, isNull);
      expect(cubit.state.value.position, const Duration(seconds: 30));
      await cubit.close();
    },
  );

  test('an older completion cannot clear a newer seek', () async {
    final controller = _SeekingController();
    final cubit = PlayerControlsCubit();
    final first = cubit.seek(controller, const Duration(seconds: 30));
    final second = cubit.seek(controller, const Duration(seconds: 60));
    controller.requests.first.complete();
    await first;
    expect(cubit.state.pendingSeekPosition, const Duration(seconds: 60));
    controller.requests.last.complete();
    await second;
    expect(cubit.state.pendingSeekPosition, isNull);
    await cubit.close();
  });

  test('failed seek clears pending intent and permits retry', () async {
    final controller = _SeekingController();
    final cubit = PlayerControlsCubit();
    final failed = cubit.seek(controller, const Duration(seconds: 30));
    controller.requests.single.completeError(StateError('seek failed'));
    await failed;
    expect(cubit.state.pendingSeekPosition, isNull);
    final retry = cubit.seek(controller, const Duration(seconds: 30));
    controller.requests.last.complete();
    await retry;
    expect(cubit.state.pendingSeekPosition, isNull);
    await cubit.close();
  });

  test(
    'controller replacement and disposal ignore pending completion',
    () async {
      final controller = _SeekingController();
      final cubit = PlayerControlsCubit();
      final seek = cubit.seek(controller, const Duration(seconds: 30));
      cubit.cancelSeek();
      expect(cubit.state.pendingSeekPosition, isNull);
      await cubit.close();
      controller.requests.single.complete();
      await seek;
    },
  );
}

class _SeekingController extends FakeAppPlayerController {
  final current = ValueNotifier(
    const AppPlayerValue(initialized: true, duration: Duration(minutes: 10)),
  );
  final List<Completer<void>> requests = [];
  @override
  ValueListenable<AppPlayerValue> get value => current;
  @override
  Future<void> seekTo(Duration target) {
    final request = Completer<void>();
    requests.add(request);
    return request.future;
  }
}
