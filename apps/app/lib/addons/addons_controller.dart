import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';
import 'package:fvcksubs_storage/fvcksubs_storage.dart';

class AddonsController extends ChangeNotifier {
  AddonsController({required this.registry, required this.store});

  final ExtensionRegistry registry;

  final AddonSettingsStore store;

  void setExtensionEnabled(String extensionId, bool enabled) {
    registry.setExtensionEnabled(extensionId, enabled);
    _persist();
    notifyListeners();
  }

  void setProviderEnabled(String providerId, bool enabled) {
    registry.setProviderEnabled(providerId, enabled);
    _persist();
    notifyListeners();
  }

  void _persist() {
    unawaited(
      store.save(
        AddonSettings(
          disabledExtensionIds: registry.disabledExtensionIds,
          disabledProviderIds: registry.disabledProviderIds,
        ),
      ),
    );
  }
}
