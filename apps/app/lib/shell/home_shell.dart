import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../addons/addons_controller.dart';
import '../app_scope.dart';
import '../home/home_page.dart';
import '../library/library_page.dart';
import '../settings/settings_page.dart';
import '../shorts/shorts_page.dart';
import '../theme/breakpoints.dart';
import '../theme/tokens.dart';
import 'app_destination.dart';
import 'app_nav_rail.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  AppDestination _destination = AppDestination.home;

  // Session-only, mirrors ShortsPage's own fit-mode state: starts false and
  // resets on every destination switch, since re-entering Shorts always
  // starts back at the letterboxed fit (see ShortsPage's `_fitMode`).
  bool _shortsImmersive = false;

  Widget get _body => switch (_destination) {
    AppDestination.home => const HomePage(),
    AppDestination.library => const LibraryPage(),
    AppDestination.shorts => ShortsPage(
      onImmersiveChanged: (immersive) =>
          setState(() => _shortsImmersive = immersive),
    ),
    AppDestination.settings => const SettingsPage(),
  };

  void _select(int index) => setState(() {
    _destination = AppDestination.values[index];
    _shortsImmersive = false;
  });

  @override
  Widget build(BuildContext context) {
    final index = _destination.index;
    final scope = AppScope.of(context);
    final body = BlocBuilder<AddonsController, AddonsState>(
      bloc: scope.addonsController,
      builder: (context, _) => _body,
    );

    final useRail =
        scope.deviceClass.isTv || AppBreakpoints.usesNavigationRail(context);

    if (useRail) {
      return Scaffold(
        body: Row(
          children: [
            AppNavRail(selectedIndex: index, onDestinationSelected: _select),
            const VerticalDivider(
              width: 1,
              thickness: 1,
              color: AppColors.hairlineDark,
            ),
            Expanded(child: body),
          ],
        ),
      );
    }

    final immersiveShorts =
        _destination == AppDestination.shorts && _shortsImmersive;

    return Scaffold(
      // Home owns an edge-to-edge hero so its artwork and gradients continue
      // behind the status bar. Other destinations keep the shared safe inset.
      body:
          _destination == AppDestination.home || _destination == AppDestination.shorts
          ? body
          : SafeArea(child: body),
      // Only Shorts' own full/cover fit mode asks the video to run behind
      // the nav bar too — every other destination keeps it opaque and
      // reserved, as before.
      extendBody: immersiveShorts,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: _select,
        backgroundColor: immersiveShorts ? Colors.black.withValues(alpha: 0.35) : null,
        destinations: [
          for (final destination in AppDestination.values)
            NavigationDestination(
              icon: Icon(destination.icon),
              selectedIcon: Icon(destination.selectedIcon),
              label: destination.label,
            ),
        ],
      ),
    );
  }
}
