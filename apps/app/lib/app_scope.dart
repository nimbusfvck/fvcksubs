import 'package:flutter/widgets.dart';
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';

import 'addons/addons_controller.dart';
import 'addons/installer_controller.dart';
import 'catalog/catalog_cache.dart';
import 'catalog/plugin_controller.dart';
import 'library/library_controller.dart';
import 'platform/device_class.dart';
import 'player/state/source_cache.dart';
import 'player/state/picture_in_picture_session.dart';
import 'player/state/picture_in_picture_preference_controller.dart';
import 'player/state/source_priority_controller.dart';
import 'player/state/quality_preference_controller.dart';
import 'player/state/subtitle_preference_controller.dart';
import 'player/widgets/app_preview_player.dart';
import 'player/widgets/stream_player.dart';
import 'settings/nsfw_controller.dart';
import 'settings/preview_autoplay_preference_controller.dart';
import 'settings/febbox_cookie_controller.dart';

class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.registry,
    required this.deviceClass,
    required this.playerBuilder,
    required this.previewPlayerBuilder,
    required this.addonsController,
    required this.installerController,
    required this.libraryController,
    required this.pluginController,
    required this.catalogCache,
    required this.qualityPreferenceController,
    required this.subtitlePreferenceController,
    required this.sourcePriorityController,
    required this.sourceCache,
    required this.pictureInPictureSession,
    required this.pictureInPicturePreferenceController,
    required this.previewAutoplayPreferenceController,
    required this.nsfwController,
    this.febboxCookieController,
    this.navigatorKey,
    required super.child,
  });

  final ExtensionRegistry registry;

  final DeviceClass deviceClass;

  final PlayerBuilder playerBuilder;

  final PreviewNativePlayerBuilder previewPlayerBuilder;

  final AddonsController addonsController;

  final InstallerController installerController;

  final LibraryController libraryController;

  final PluginController pluginController;

  final CatalogCache catalogCache;

  final QualityPreferenceController qualityPreferenceController;

  final SubtitlePreferenceController subtitlePreferenceController;

  final SourcePriorityController sourcePriorityController;

  final SourceCache sourceCache;

  final PictureInPictureSession pictureInPictureSession;

  final PictureInPicturePreferenceController
  pictureInPicturePreferenceController;

  final PreviewAutoplayPreferenceController previewAutoplayPreferenceController;

  final NsfwController nsfwController;

  final FebboxCookieController? febboxCookieController;

  final GlobalKey<NavigatorState>? navigatorKey;

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
      previewPlayerBuilder != oldWidget.previewPlayerBuilder ||
      addonsController != oldWidget.addonsController ||
      installerController != oldWidget.installerController ||
      libraryController != oldWidget.libraryController ||
      pluginController != oldWidget.pluginController ||
      catalogCache != oldWidget.catalogCache ||
      qualityPreferenceController != oldWidget.qualityPreferenceController ||
      subtitlePreferenceController != oldWidget.subtitlePreferenceController ||
      sourcePriorityController != oldWidget.sourcePriorityController ||
      sourceCache != oldWidget.sourceCache ||
      pictureInPictureSession != oldWidget.pictureInPictureSession ||
      pictureInPicturePreferenceController !=
          oldWidget.pictureInPicturePreferenceController ||
      previewAutoplayPreferenceController !=
          oldWidget.previewAutoplayPreferenceController ||
      nsfwController != oldWidget.nsfwController ||
      febboxCookieController != oldWidget.febboxCookieController ||
      navigatorKey != oldWidget.navigatorKey;
}
