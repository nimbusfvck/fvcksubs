import 'package:flutter/material.dart';
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';
import 'package:fvcksubs_storage/fvcksubs_storage.dart';

import 'addons/addons_controller.dart';
import 'addons/installer_controller.dart';
import 'app_scope.dart';
import 'catalog/catalog_cache.dart';
import 'catalog/plugin_controller.dart';
import 'library/library_controller.dart';
import 'library/library_controller_v2.dart';
import 'platform/device_class.dart';
import 'player/source_cache.dart';
import 'player/source_priority_controller.dart';
import 'player/stream_player.dart';
import 'player/subtitle_preference_controller.dart';
import 'shell/home_shell.dart';
import 'theme/app_theme.dart';

class FvcksubsApp extends StatelessWidget {
  const FvcksubsApp({
    super.key,
    required this.registry,
    required this.deviceClass,
    required this.addonsController,
    required this.installerController,
    required this.libraryController,
    required this.libraryControllerV2,
    required this.pluginController,
    required this.catalogCache,
    required this.subtitlePreferenceController,
    required this.sourcePriorityController,
    required this.homeCategoryStore,
    required this.sourceCache,
    this.navigatorKey,
    this.playerBuilder = defaultPlayerBuilder,
  });

  final ExtensionRegistry registry;

  final DeviceClass deviceClass;

  final AddonsController addonsController;

  final InstallerController installerController;

  final LibraryController libraryController;

  final LibraryControllerV2 libraryControllerV2;

  final PluginController pluginController;

  final CatalogCache catalogCache;

  final SubtitlePreferenceController subtitlePreferenceController;

  final SourcePriorityController sourcePriorityController;

  final CategorySelectionStore homeCategoryStore;

  final SourceCache sourceCache;

  final GlobalKey<NavigatorState>? navigatorKey;

  final PlayerBuilder playerBuilder;

  @override
  Widget build(BuildContext context) => AppScope(
    registry: registry,
    deviceClass: deviceClass,
    playerBuilder: playerBuilder,
    addonsController: addonsController,
    installerController: installerController,
    libraryController: libraryController,
    libraryControllerV2: libraryControllerV2,
    pluginController: pluginController,
    catalogCache: catalogCache,
    subtitlePreferenceController: subtitlePreferenceController,
    sourcePriorityController: sourcePriorityController,
    homeCategoryStore: homeCategoryStore,
    sourceCache: sourceCache,
    child: MaterialApp(
      navigatorKey: navigatorKey,
      title: 'fvcksubs',
      debugShowCheckedModeBanner: false,
      theme: buildDarkTheme(),
      home: const HomeShell(),
    ),
  );
}
