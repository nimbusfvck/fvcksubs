import 'package:flutter/widgets.dart';
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';
import 'package:fvcksubs_storage/fvcksubs_storage.dart';

import 'addons/addons_controller.dart';
import 'addons/installer_controller.dart';
import 'catalog/catalog_cache.dart';
import 'catalog/plugin_controller.dart';
import 'library/library_controller.dart';
import 'platform/device_class.dart';
import 'player/state/source_cache.dart';
import 'player/state/source_priority_controller.dart';
import 'player/state/subtitle_preference_controller.dart';
import 'player/widgets/stream_player.dart';
import 'settings/nsfw_controller.dart';

class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.registry,
    required this.deviceClass,
    required this.playerBuilder,
    required this.addonsController,
    required this.installerController,
    required this.libraryController,
    required this.pluginController,
    required this.catalogCache,
    required this.subtitlePreferenceController,
    required this.sourcePriorityController,
    required this.homeCategoryStore,
    required this.sourceCache,
    required this.nsfwController,
    required super.child,
  });

  final ExtensionRegistry registry;

  final DeviceClass deviceClass;

  final PlayerBuilder playerBuilder;

  final AddonsController addonsController;

  final InstallerController installerController;

  final LibraryController libraryController;

  final PluginController pluginController;

  final CatalogCache catalogCache;

  final SubtitlePreferenceController subtitlePreferenceController;

  final SourcePriorityController sourcePriorityController;

  final CategorySelectionStore homeCategoryStore;

  final SourceCache sourceCache;

  final NsfwController nsfwController;

  static AppScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'No AppScope found in context');
    return scope!;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) =>
      registry != oldWidget.registry ||
      deviceClass != oldWidget.deviceClass ||
      playerBuilder != oldWidget.playerBuilder ||
      addonsController != oldWidget.addonsController ||
      installerController != oldWidget.installerController ||
      libraryController != oldWidget.libraryController ||
      pluginController != oldWidget.pluginController ||
      catalogCache != oldWidget.catalogCache ||
      subtitlePreferenceController != oldWidget.subtitlePreferenceController ||
      sourcePriorityController != oldWidget.sourcePriorityController ||
      homeCategoryStore != oldWidget.homeCategoryStore ||
      sourceCache != oldWidget.sourceCache ||
      nsfwController != oldWidget.nsfwController;
}
