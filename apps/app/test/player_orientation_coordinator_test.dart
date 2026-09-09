import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_app/player/state/player_orientation_coordinator.dart';

void main() {
  test('releases the platform request outside the full player', () async {
    final requests = <List<DeviceOrientation>>[];
    final coordinator = PlayerOrientationCoordinator(
      setPreferredOrientations: (orientations) async {
        requests.add(orientations);
      },
    );

    expect(
      coordinator.toggle(activeFullPlayer: true, pipBackground: false),
      isTrue,
    );
    expect(requests.last, [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    coordinator.sync(
      activeFullPlayer: false,
      pipBackground: false,
      releaseDelay: const Duration(milliseconds: 10),
    );
    expect(requests.last, [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(requests.last, isEmpty);
    expect(coordinator.landscapeRequested, isTrue);
  });

  test('reapplies the session choice when full player is restored', () async {
    final requests = <List<DeviceOrientation>>[];
    final coordinator = PlayerOrientationCoordinator(
      setPreferredOrientations: (orientations) async {
        requests.add(orientations);
      },
    );

    coordinator.toggle(activeFullPlayer: true, pipBackground: false);
    coordinator.sync(activeFullPlayer: true, pipBackground: false);

    expect(requests, [
      [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight],
      [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight],
    ]);
  });

  test('delays release and cancels it when full player is restored', () async {
    final requests = <List<DeviceOrientation>>[];
    final coordinator = PlayerOrientationCoordinator(
      setPreferredOrientations: (orientations) async {
        requests.add(orientations);
      },
    );

    coordinator.toggle(activeFullPlayer: true, pipBackground: false);
    coordinator.sync(
      activeFullPlayer: false,
      pipBackground: false,
      releaseDelay: const Duration(milliseconds: 10),
    );
    coordinator.sync(activeFullPlayer: true, pipBackground: false);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(requests, [
      [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight],
      [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight],
    ]);
  });
}
