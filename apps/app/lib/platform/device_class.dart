import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

enum DeviceClass {
  handheld,

  tv;

  bool get isTv => this == DeviceClass.tv;
}

abstract final class DeviceClassResolver {
  static const String _leanbackFeature = 'android.software.leanback';
  static const String _fireTvFeature = 'amazon.hardware.fire_tv';

  static Future<DeviceClass> resolve() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return DeviceClass.handheld;
    }
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      final features = info.systemFeatures.toSet();
      if (features.contains(_leanbackFeature) ||
          features.contains(_fireTvFeature)) {
        return DeviceClass.tv;
      }
    } catch (error) {
      debugPrint('DeviceClassResolver: device info unavailable: $error');
    }
    return DeviceClass.handheld;
  }
}
