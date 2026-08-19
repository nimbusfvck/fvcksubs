import 'package:flutter/material.dart';

import '../addons/addons_page.dart';
import '../app_scope.dart';
import '../home/home_page.dart';
import '../library/library_page.dart';
import 'app_destination.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  AppDestination _destination = AppDestination.home;

  Widget get _body => switch (_destination) {
    AppDestination.home => const HomePage(),
    AppDestination.library => const LibraryPage(),
    AppDestination.addons => const AddonsPage(),
  };

  void _select(int index) =>
      setState(() => _destination = AppDestination.values[index]);

  @override
  Widget build(BuildContext context) {
    final index = _destination.index;
    final scope = AppScope.of(context);
    final body = ListenableBuilder(
      listenable: Listenable.merge([
        scope.addonsController,
        scope.libraryController,
      ]),
      builder: (context, _) => _body,
    );

    if (scope.deviceClass.isTv) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: index,
              onDestinationSelected: _select,
              labelType: NavigationRailLabelType.all,
              destinations: [
                for (final destination in AppDestination.values)
                  NavigationRailDestination(
                    icon: Icon(destination.icon),
                    selectedIcon: Icon(destination.selectedIcon),
                    label: Text(destination.label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: body),
          ],
        ),
      );
    }

    return Scaffold(
      body: SafeArea(child: body),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: _select,
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
