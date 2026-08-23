import 'package:flutter/material.dart';
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';
import 'package:fvcksubs_storage/fvcksubs_storage.dart';

import 'addons/addons_controller.dart';
import 'addons/installer_controller.dart';
import 'app_scope.dart';
import 'catalog/catalog_cache.dart';
import 'catalog/plugin_controller.dart';
import 'library/library_controller.dart';
import 'navigation/app_route_observer.dart';
import 'platform/device_class.dart';
import 'player/state/source_cache.dart';
import 'player/state/source_priority_controller.dart';
import 'player/state/subtitle_preference_controller.dart';
import 'player/widgets/stream_player.dart';
import 'shell/home_shell.dart';
import 'shell/system_ui_visibility.dart';
import 'settings/nsfw_controller.dart';
import 'theme/app_theme.dart';

class FvcksubsApp extends StatelessWidget {
  const FvcksubsApp({
    super.key,
    required this.registry,
    required this.deviceClass,
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
    this.navigatorKey,
    this.playerBuilder = defaultPlayerBuilder,
  });

  final ExtensionRegistry registry;

  final DeviceClass deviceClass;

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
    pluginController: pluginController,
    catalogCache: catalogCache,
    subtitlePreferenceController: subtitlePreferenceController,
    sourcePriorityController: sourcePriorityController,
    homeCategoryStore: homeCategoryStore,
    sourceCache: sourceCache,
    nsfwController: nsfwController,
    child: MaterialApp(
      navigatorKey: navigatorKey,
      navigatorObservers: [appRouteObserver],
      title: 'fvcksubs',
      debugShowCheckedModeBanner: false,
      theme: buildDarkTheme(),
      builder: (context, child) =>
          SystemUiVisibility(child: child ?? const SizedBox.shrink()),
      home: const HomeShell(),
    ),
  );
}
