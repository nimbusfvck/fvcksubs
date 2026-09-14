import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_app/addons/addons_controller.dart';
import 'package:fvcksubs_app/addons/addons_page.dart';
import 'package:fvcksubs_app/catalog/media_card_v2.dart';
import 'package:fvcksubs_app/catalog/category_page.dart';
import 'package:fvcksubs_app/home/continue_watching_shelf.dart';
import 'package:fvcksubs_app/home/category_chips.dart';
import 'package:fvcksubs_app/home/home_page.dart';
import 'package:fvcksubs_app/library/library_controller.dart';
import 'package:fvcksubs_app/platform/device_class.dart';
import 'package:fvcksubs_app/shell/app_nav_rail.dart';
import 'package:fvcksubs_app/shell/home_shell.dart';
import 'package:fvcksubs_app/widgets/app_page_bar.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';
import 'package:fvcksubs_storage/fvcksubs_storage.dart';

import 'support/harness.dart';

void main() {
  Finder catalogItemText(String title) =>
      find.descendant(of: find.byType(MediaCardV2), matching: find.text(title));

  Future<void> revealCatalog(WidgetTester tester) async {
    await tester.drag(
      find.byType(CustomScrollView).first,
      const Offset(0, -500),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('tv category is labeled Shows', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CategoryChips(
          categories: const ['all', 'tv'],
          selected: 'all',
          onSelected: (_) {},
        ),
      ),
    );

    expect(find.text('Shows'), findsOneWidget);
    expect(find.text('Tv'), findsNothing);

    await tester.pumpWidget(
      MaterialApp(
        home: CategoryChips(
          categories: const ['movie'],
          selected: 'movie',
          onSelected: (_) {},
        ),
      ),
    );
    expect(find.text('Movies'), findsOneWidget);
    expect(find.text('Movie'), findsNothing);
  });

  testWidgets('live category shows an animated indicator', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CategoryChips(
          categories: const ['live'],
          selected: '',
          onSelected: (_) {},
        ),
      ),
    );

    expect(find.text('Live'), findsOneWidget);
    expect(find.byKey(const Key('live-category-indicator')), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 550));
    expect(find.byKey(const Key('live-category-indicator')), findsOneWidget);
  });

  testWidgets('nav is fixed and does not depend on installed extensions', (
    tester,
  ) async {
    // Same four destinations whether one extension is installed or none —
    // that's the point of moving nav out of the registry.
    for (final registry in [
      ExtensionRegistry([
        FakeExtension(categories: ['sport']),
      ]),
      ExtensionRegistry([]),
    ]) {
      await tester.pumpWidget(
        wrapApp(child: const HomeShell(), registry: registry),
      );
      await tester.pump();

      expect(find.widgetWithText(NavigationBar, 'Home'), findsOneWidget);
      expect(find.widgetWithText(NavigationBar, 'Library'), findsOneWidget);
      expect(find.widgetWithText(NavigationBar, 'Shorts'), findsOneWidget);
      expect(find.widgetWithText(NavigationBar, 'Settings'), findsOneWidget);
      // Search is not a destination — it opens from Home as its own screen.
      expect(find.widgetWithText(NavigationBar, 'Search'), findsNothing);
    }
  });

  testWidgets('switching destination swaps the body', (tester) async {
    await tester.pumpWidget(
      wrapApp(
        child: const HomeShell(),
        registry: ExtensionRegistry([FakeExtension()]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('home-logo-title')), findsOneWidget);

    await tester.tap(find.text('Library'));
    await tester.pumpAndSettle();

    // A real LibraryPage now — empty because nothing's been favorited or
    // watched in this fresh session, not because it isn't built.
    expect(find.text('No favorites yet'), findsOneWidget);
    expect(find.widgetWithText(AppPageBar, 'Library'), findsOneWidget);

    await tester.tap(find.text('Shorts'));
    await tester.pumpAndSettle();
    // No preview catalog on this fake registry, so Shorts reaches its empty
    // state — enough to prove the destination actually swapped in.
    expect(find.text('No previews are available right now.'), findsOneWidget);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppPageBar, 'Settings'), findsOneWidget);
  });

  testWidgets('Shorts full-screen fit extends the nav bar over the video, and '
      'switching away resets it', (tester) async {
    final registry = ExtensionRegistry([
      FakeExtension(
        catalogs: [
          FakeCatalog(
            id: 'previews',
            name: 'Previews',
            categories: const [],
            items: [fakeItem(id: 'one', title: 'one')],
            surface: CatalogSurface.preview,
          ),
        ],
        previewFor: {
          'one': const PreviewResponse(
            sources: [
              DirectPreviewSource(
                id: 'd1',
                stream: PlayableStream(url: 'https://cdn.example.com/1.mp4'),
              ),
            ],
          ),
        },
      ),
    ]);

    await tester.pumpWidget(
      wrapApp(child: const HomeShell(), registry: registry),
    );
    await tester.tap(find.text('Shorts'));
    await tester.pump();
    await tester.pump();

    Scaffold shellScaffold() => tester
        .widgetList<Scaffold>(find.byType(Scaffold))
        .firstWhere((s) => s.bottomNavigationBar != null);
    NavigationBar navBar() =>
        tester.widget<NavigationBar>(find.byType(NavigationBar));

    expect(shellScaffold().extendBody, isFalse);
    expect(navBar().backgroundColor, isNull);

    await tester.tap(find.byTooltip('Fit screen'));
    await tester.pump();

    expect(shellScaffold().extendBody, isTrue);
    expect(navBar().backgroundColor, isNotNull);

    // Leaving Shorts drops the immersive state even though the fit
    // toggle itself is session-local to the (now discarded) page.
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Shorts'));
    await tester.pump();
    await tester.pump();

    expect(shellScaffold().extendBody, isFalse);
    expect(navBar().backgroundColor, isNull);
  });

  testWidgets('settings is a real destination', (tester) async {
    await tester.pumpWidget(
      wrapApp(child: const HomeShell(), registry: ExtensionRegistry([])),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Preferred subtitles'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Preferred subtitles'), findsOneWidget);
    expect(find.text('Indonesia'), findsOneWidget);
  });

  testWidgets(
    'toggling an extension off in Addons hides it on Home immediately',
    (tester) async {
      final registry = ExtensionRegistry([
        FakeExtension(
          id: 'fake',
          categories: ['sport'],
          items: [fakeItem(title: 'Some Match')],
        ),
      ]);
      final controller = AddonsController(
        registry: registry,
        store: FakeAddonSettingsStore(),
      );

      await tester.pumpWidget(
        wrapApp(
          child: const HomeShell(),
          registry: registry,
          addonsController: controller,
        ),
      );
      await tester.pumpAndSettle();
      await revealCatalog(tester);
      expect(catalogItemText('Some Match'), findsOneWidget);

      // Addons is reachable from Settings now, not a bottom-nav destination
      // itself — not find.widgetWithText(NavigationBar, ...): that resolves
      // to the whole bar and taps its bounding-box center, which only
      // happens to land on the right destination for items near the middle.
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Addons'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.byType(AddonsPage))).pop();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();

      // The registry's own state changed in place — HomePage only reflects
      // it because HomeShell listens to the same AddonsController and
      // rebuilds whichever tab is showing.
      expect(catalogItemText('Some Match'), findsNothing);
    },
  );

  testWidgets('TV gets a rail instead of a bottom bar', (tester) async {
    await tester.pumpWidget(
      wrapApp(
        child: const HomeShell(),
        registry: ExtensionRegistry([FakeExtension()]),
        deviceClass: DeviceClass.tv,
      ),
    );
    await tester.pump();

    expect(find.byType(AppNavRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('Sport'), findsOneWidget);
    expect(find.byKey(const Key('home-category-header')), findsNothing);

    await tester.tap(find.text('Sport'));
    await tester.pump();
    expect(find.byType(AppNavRail), findsOneWidget);
    expect(find.byType(CategoryPage), findsOneWidget);
  });

  testWidgets(
    'a tablet-sized handheld window gets a rail instead of a bottom bar',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        wrapApp(
          child: const HomeShell(),
          registry: ExtensionRegistry([FakeExtension()]),
          deviceClass: DeviceClass.handheld,
        ),
      );
      await tester.pump();

      expect(find.byType(AppNavRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
    },
  );

  testWidgets('a narrow handheld window keeps the bottom bar', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      wrapApp(
        child: const HomeShell(),
        registry: ExtensionRegistry([FakeExtension()]),
        deviceClass: DeviceClass.handheld,
      ),
    );
    await tester.pump();

    expect(find.byType(AppNavRail), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('a phone keeps the bottom bar after rotating to landscape', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      wrapApp(
        child: const HomeShell(),
        registry: ExtensionRegistry([FakeExtension()]),
        deviceClass: DeviceClass.handheld,
      ),
    );
    await tester.pump();
    expect(find.byType(AppNavRail), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);

    tester.view.physicalSize = const Size(844, 390);
    await tester.pump();

    expect(find.byType(AppNavRail), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('all stays on Home while other categories open a category page', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrapApp(
        child: const HomePage(),
        registry: ExtensionRegistry([
          FakeExtension(
            categories: ['all', 'movie'],
            expanded: true,
            items: [fakeItem(title: 'Home item')],
          ),
        ]),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(CategoryPage), findsNothing);
    expect(find.text('All'), findsNothing);

    await tester.tap(find.text('Movies'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(CategoryPage), findsOneWidget);
    expect(find.widgetWithText(AppPageBar, 'Movies'), findsOneWidget);
    expect(find.text('Home item'), findsWidgets);
  });

  testWidgets(
    'category chips hide while scrolling down and show while scrolling up',
    (tester) async {
      await tester.pumpWidget(
        wrapApp(
          child: const HomePage(),
          registry: ExtensionRegistry([
            FakeExtension(
              expanded: true,
              items: [
                for (var index = 0; index < 30; index++)
                  fakeItem(id: 'item-$index', title: 'Item $index'),
              ],
            ),
          ]),
        ),
      );
      // The Home page contains long-lived scroll/preview state, so settling the
      // entire tree is not a reliable way to wait for its catalog response.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      AnimatedSlide header() => tester.widget<AnimatedSlide>(
        find.byKey(const Key('home-category-header-animation')),
      );

      expect(header().offset, Offset.zero);

      await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
      await tester.pump(const Duration(milliseconds: 300));
      expect(header().offset, const Offset(0, -1));

      await tester.drag(find.byType(CustomScrollView), const Offset(0, 300));
      await tester.pump(const Duration(milliseconds: 300));
      expect(header().offset, Offset.zero);
    },
  );

  testWidgets('Continue Watching hides mature records when NSFW is off', (
    tester,
  ) async {
    final registry = ExtensionRegistry([
      FakeExtension(categories: ['all']),
    ]);
    final item = fakeItem(title: 'Mature item');
    final library = LibraryController(
      store: _TestLibraryStore(),
      initial: {
        UserMediaState.keyFor(item.ref): UserMediaState(
          item: item,
          contentRating: ContentRating.mature,
          progress: const Duration(minutes: 2),
        ),
      },
    );

    await tester.pumpWidget(
      wrapApp(
        child: const HomeShell(),
        registry: registry,
        libraryController: library,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Continue Watching'), findsNothing);
    expect(find.text('Mature item'), findsNothing);
  });

  testWidgets(
    'Continue Watching shows remaining duration beside a smaller checklist',
    (tester) async {
      final registry = ExtensionRegistry([FakeExtension()]);
      final item = fakeItem(title: 'In progress');
      final library = LibraryController(
        store: _TestLibraryStore(),
        initial: {
          UserMediaState.keyFor(item.ref): UserMediaState(
            item: item,
            progress: const Duration(minutes: 25),
            duration: const Duration(hours: 2),
            lastWatched: DateTime.utc(2026, 9, 10),
          ),
        },
      );

      await tester.pumpWidget(
        wrapApp(
          child: ContinueWatchingShelf(controller: library, registry: registry),
          registry: registry,
          libraryController: library,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('1h 35m left'), findsOneWidget);
      final checkButton = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.check_rounded),
      );
      expect(checkButton.iconSize, 16);
      expect(
        checkButton.constraints,
        const BoxConstraints.tightFor(width: 36, height: 36),
      );
      expect(
        tester.getSize(find.byType(LinearProgressIndicator)),
        const Size(280, 4),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('expanded sectioned catalogs keep their section heading', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrapApp(
        child: const HomeShell(),
        registry: ExtensionRegistry([
          FakeExtension(
            categories: ['nsfw'],
            expanded: true,
            sectionTitle: 'Section title',
            items: [fakeItem(title: 'Catalog item')],
          ),
        ]),
      ),
    );
    await tester.pumpAndSettle();
    await revealCatalog(tester);

    expect(find.text('Section title'), findsOneWidget);
    expect(catalogItemText('Catalog item'), findsOneWidget);
  });

  testWidgets('groups service catalogs and switches the visible shelf', (
    tester,
  ) async {
    final registry = ExtensionRegistry([
      FakeExtension(
        id: 'streaming',
        categories: ['movie'],
        catalogs: [
          FakeCatalog(
            id: 'apple',
            name: 'Movies on Apple TV',
            categories: ['movie'],
            items: [fakeItem(id: 'apple-movie', title: 'Apple movie')],
          ),
          FakeCatalog(
            id: 'netflix',
            name: 'Movies on Netflix',
            categories: ['movie'],
            items: [fakeItem(id: 'netflix-movie', title: 'Netflix movie')],
          ),
        ],
      ),
    ]);

    await tester.pumpWidget(
      wrapApp(child: const HomeShell(), registry: registry),
    );
    await tester.pumpAndSettle();
    await revealCatalog(tester);

    expect(find.text('Movies'), findsOneWidget);
    expect(find.text('Apple TV'), findsOneWidget);
    expect(find.text('Netflix'), findsNothing);
    expect(catalogItemText('Apple movie'), findsOneWidget);
    expect(catalogItemText('Netflix movie'), findsNothing);

    await tester.drag(
      find.byType(CustomScrollView).first,
      const Offset(0, 300),
    );
    await tester.pumpAndSettle();
    final changeService = find.byTooltip('Change service').first;
    await tester.ensureVisible(changeService);
    await tester.pumpAndSettle();
    await tester.tap(changeService);
    await tester.pumpAndSettle();
    expect(find.text('Netflix'), findsOneWidget);
    await tester.tap(find.text('Netflix'));
    await tester.pumpAndSettle();
    await revealCatalog(tester);

    expect(catalogItemText('Apple movie'), findsNothing);
    expect(catalogItemText('Netflix movie'), findsOneWidget);
  });

  testWidgets('groups service sections inside the all catalog', (tester) async {
    final extension = FakeExtension(
      id: 'all-sections',
      categories: ['all'],
      catalogSections: [
        CatalogSectionV2(
          id: 'movies-apple',
          title: 'Movies on Apple TV',
          items: [
            VersionedMediaItem(
              item: fakeItem(
                id: 'apple-movie',
                title: 'Apple movie',
                poster: const ImageRef('https://image.example/apple.jpg'),
              ),
            ),
          ],
        ),
        CatalogSectionV2(
          id: 'movies-netflix',
          title: 'Movies on Netflix',
          items: [
            VersionedMediaItem(
              item: fakeItem(
                id: 'netflix-movie',
                title: 'Netflix movie',
                poster: const ImageRef('https://image.example/netflix.jpg'),
              ),
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      wrapApp(
        child: const HomeShell(),
        registry: ExtensionRegistry([extension]),
      ),
    );
    await tester.pumpAndSettle();
    await revealCatalog(tester);

    expect(find.text('Movies'), findsOneWidget);
    expect(find.text('Apple TV'), findsOneWidget);
    expect(find.text('Netflix'), findsNothing);
    expect(catalogItemText('Apple movie'), findsOneWidget);
    expect(catalogItemText('Netflix movie'), findsNothing);

    await tester.drag(
      find.byType(CustomScrollView).first,
      const Offset(0, 300),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Change service').first);
    await tester.pumpAndSettle();
    expect(find.text('Netflix'), findsOneWidget);
    await tester.tap(find.text('Netflix'));
    await tester.pumpAndSettle();
    await revealCatalog(tester);

    expect(catalogItemText('Apple movie'), findsNothing);
    expect(catalogItemText('Netflix movie'), findsOneWidget);
  });
}

class _TestLibraryStore implements LibraryStore {
  @override
  Future<Map<String, UserMediaState>> load() async => {};

  @override
  Future<void> save(Map<String, UserMediaState> records) async {}
}
