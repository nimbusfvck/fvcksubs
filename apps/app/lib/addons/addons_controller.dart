import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';
import 'package:fvcksubs_storage/fvcksubs_storage.dart';

class AddonsState {
  const AddonsState({this.revision = 0});

  final int revision;

  AddonsState next() => AddonsState(revision: revision + 1);
}

class AddonsController extends Cubit<AddonsState> {
  AddonsController({required this.registry, required this.store})
    : super(const AddonsState());

  final ExtensionRegistry registry;

  final AddonSettingsStore store;

  void setExtensionEnabled(String extensionId, bool enabled) {
    registry.setExtensionEnabled(extensionId, enabled);
    _persist();
    emit(state.next());
  }

  void setProviderEnabled(String providerId, bool enabled) {
    registry.setProviderEnabled(providerId, enabled);
    _persist();
    emit(state.next());
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
