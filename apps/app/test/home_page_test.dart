import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_app/catalog/catalog_screen.dart';
import 'package:fvcksubs_app/catalog/catalog_cache.dart';
import 'package:fvcksubs_app/catalog/media_grid.dart';
import 'package:fvcksubs_app/catalog/plugin_controller.dart';
import 'package:fvcksubs_app/addons/installer_controller.dart';
import 'package:fvcksubs_app/catalog/plugin_selector.dart';
import 'package:fvcksubs_app/home/catalog_shelf.dart';
import 'package:fvcksubs_app/home/home_page.dart';
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';

import 'support/harness.dart';

void main() {
  testWidgets('chips come from installed extensions, first one selected', (
    tester,
  ) async {
    final registry = ExtensionRegistry([
      FakeExtension(id: 'a', categories: ['live', 'sport']),
      FakeExtension(id: 'b', categories: ['movie']),
    ]);

    await tester.pumpWidget(
      wrapApp(child: const HomePage(), registry: registry),
    );
    await tester.pumpAndSettle();

    expect(find.widgetWithText(ChoiceChip, 'Live'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Sport'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Movie'), findsOneWidget);

    // No app-invented "All" chip — chips are exactly what extensions declare.
    expect(find.widgetWithText(ChoiceChip, 'All'), findsNothing);

    final first = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, 'Live'),
    );
    expect(first.selected, isTrue);
  });

  testWidgets('tapping a chip switches which category is loaded', (
    tester,
  ) async {
    final registry = ExtensionRegistry([
      FakeExtension(
        id: 'a',
        categories: ['live', 'sport'],
        itemsByCategory: {
          'live': [fakeItem(id: 'l1', title: 'Live Item')],
          'sport': [fakeItem(id: 's1', title: 'Sport Item')],
        },
      ),
    ]);

    await tester.pumpWidget(
      wrapApp(child: const HomePage(), registry: registry),
    );
    await tester.pumpAndSettle();

    expect(find.text('Live Item'), findsOneWidget);
    expect(find.text('Sport Item'), findsNothing);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Sport'));
    await tester.pumpAndSettle();

    expect(find.text('Sport Item'), findsOneWidget);
    expect(find.text('Live Item'), findsNothing);
  });

  testWidgets('a row catalog carousels, a grid one lays out in columns', (
    tester,
  ) async {
    Future<void> pumpWith(CatalogDisplay display) async {
      final registry = ExtensionRegistry([
        FakeExtension(
          categories: ['sport'],
          display: display,
          items: [fakeItem(title: 'Item')],
        ),
      ]);
      await tester.pumpWidget(
        wrapApp(child: const HomePage(), registry: registry),
      );
      await tester.pumpAndSettle();
    }

    await pumpWith(CatalogDisplay.row);
    // The outer ListView is Home's own vertical scroller; the carousel is the
    // one nested inside it.
    expect(
      tester.widgetList<ListView>(find.byType(ListView)).last.scrollDirection,
      Axis.horizontal,
    );
    expect(find.byType(GridView), findsNothing);

    await pumpWith(CatalogDisplay.grid);
    expect(find.byType(GridView), findsOneWidget);
  });

  testWidgets('a phone grid is two columns wide', (tester) async {
    // The extension asks for "show it all"; how many columns that is stays the
    // app's decision, and on a phone it's two.
    expect(MediaGrid.columnsFor(400), 2);
    // Never one, even on a very narrow screen.
    expect(MediaGrid.columnsFor(280), 2);
    // Wider screens get more.
    expect(MediaGrid.columnsFor(900), 3);
    expect(MediaGrid.columnsFor(1280), 4);
  });

  group('sections', () {
    testWidgets('one heading + carousel per subcategory', (tester) async {
      final registry = ExtensionRegistry([
        FakeExtension(
          categories: ['sport'],
          display: CatalogDisplay.row,
          items: [
            fakeItem(id: 'm1', title: 'Lens vs PSG', group: 'Football'),
            fakeItem(id: 'm2', title: 'SL vs IND', group: 'Cricket'),
            fakeItem(id: 'm3', title: 'ATP vs WTA', group: 'Tennis'),
          ],
        ),
      ]);

      await tester.pumpWidget(
        wrapApp(child: const HomePage(), registry: registry),
      );
      await tester.pumpAndSettle();

      // Football, Cricket and Tennis are peers — one section each.
      expect(find.text('Football'), findsOneWidget);
      expect(find.text('Cricket'), findsOneWidget);
      expect(find.text('Tennis'), findsOneWidget);

      final carousels = tester
          .widgetList<ListView>(find.byType(ListView))
          .where((view) => view.scrollDirection == Axis.horizontal);
      expect(carousels, hasLength(3));
    });

    testWidgets('a small section survives next to a large one', (tester) async {
      // The reason the preview is capped per section rather than once across
      // the whole response: a flat cut of six would be six football fixtures,
      // and Cricket would never appear on Home at all.
      final registry = ExtensionRegistry([
        FakeExtension(
          categories: ['sport'],
          display: CatalogDisplay.row,
          items: [
            for (var i = 0; i < 20; i++)
              fakeItem(id: 'f$i', title: 'Football $i', group: 'Football'),
            fakeItem(id: 'c1', title: 'SL vs IND', group: 'Cricket'),
          ],
        ),
      ]);

      await tester.pumpWidget(
        wrapApp(child: const HomePage(), registry: registry),
      );
      await tester.pumpAndSettle();

      expect(find.text('Cricket'), findsOneWidget);
      expect(find.text('SL vs IND'), findsOneWidget);
      // Football is truncated to its own preview limit, not to what's left
      // over after the other sections.
      expect(
        find.text('Football ${CatalogShelf.rowPreviewLimit}'),
        findsNothing,
      );
    });

    testWidgets('an ungrouped catalog is one section under its own name', (
      tester,
    ) async {
      final registry = ExtensionRegistry([
        FakeExtension(
          categories: ['live'],
          catalogName: 'Live Now',
          display: CatalogDisplay.row,
          items: [fakeItem(id: 'm1', title: 'Item 1')],
        ),
      ]);

      await tester.pumpWidget(
        wrapApp(child: const HomePage(), registry: registry),
      );
      await tester.pumpAndSettle();

      expect(find.text('Live Now'), findsOneWidget);
      final carousels = tester
          .widgetList<ListView>(find.byType(ListView))
          .where((view) => view.scrollDirection == Axis.horizontal);
      expect(carousels, hasLength(1));
    });
  });

  group('see more', () {
    List<MediaItem> manyItems(int count) => [
      for (var i = 0; i < count; i++) fakeItem(id: 'm$i', title: 'Match $i'),
    ];

    testWidgets('a row previews up to 10 items before See more', (
      tester,
    ) async {
      final registry = ExtensionRegistry([
        FakeExtension(
          categories: ['sport'],
          display: CatalogDisplay.row,
          items: manyItems(CatalogShelf.rowPreviewLimit),
        ),
      ]);

      await tester.pumpWidget(
        wrapApp(child: const HomePage(), registry: registry),
      );
      await tester.pumpAndSettle();

      // Exactly at the limit: nothing was withheld, so there's nothing to
      // defer to a full screen for.
      expect(find.text('See more'), findsNothing);
    });

    testWidgets('is absent when the section already shows everything', (
      tester,
    ) async {
      final registry = ExtensionRegistry([
        FakeExtension(
          categories: ['sport'],
          items: manyItems(CatalogShelf.previewLimit),
        ),
      ]);

      await tester.pumpWidget(
        wrapApp(child: const HomePage(), registry: registry),
      );
      await tester.pumpAndSettle();

      expect(find.text('See more'), findsNothing);
      expect(find.text('Match 5'), findsOneWidget);
    });

    testWidgets('truncates the section and opens the full catalog', (
      tester,
    ) async {
      final registry = ExtensionRegistry([
        FakeExtension(
          categories: ['sport'],
          items: manyItems(CatalogShelf.previewLimit + 3),
        ),
      ]);

      await tester.pumpWidget(
        wrapApp(child: const HomePage(), registry: registry),
      );
      await tester.pumpAndSettle();

      // Home stays glanceable: the extra items are behind "See more".
      expect(find.text('Match 8'), findsNothing);
      expect(find.text('See more'), findsOneWidget);

      await tester.tap(find.text('See more'));
      await tester.pumpAndSettle();

      expect(find.byType(CatalogScreen), findsOneWidget);
      // The full screen holds the items the shelf withheld — off-screen at
      // first, since its grid builds lazily, so scroll to prove it's there.
      await tester.scrollUntilVisible(find.text('Match 8'), 200);
      expect(find.text('Match 8'), findsOneWidget);
    });

    testWidgets('a section showing everything it has offers nothing more', (
      tester,
    ) async {
      final registry = ExtensionRegistry([
        FakeExtension(
          categories: ['sport'],
          display: CatalogDisplay.row,
          subCategories: const [SubCategory(id: 'cricket', name: 'Cricket')],
          items: [fakeItem(id: 'c1', title: 'SL vs IND', group: 'Cricket')],
        ),
      ]);

      await tester.pumpWidget(
        wrapApp(child: const HomePage(), registry: registry),
      );
      await tester.pumpAndSettle();

      // Mapping to a subcategory isn't enough on its own — the cut is what
      // "See more" is about.
      expect(find.text('See more'), findsNothing);
    });

    testWidgets("a section's see more opens that subcategory narrowed", (
      tester,
    ) async {
      final extension = FakeExtension(
        categories: ['sport'],
        display: CatalogDisplay.row,
        subCategories: const [SubCategory(id: 'cricket', name: 'Cricket')],
        items: [
          for (var i = 0; i < CatalogShelf.rowPreviewLimit + 2; i++)
            fakeItem(id: 'c$i', title: 'Cricket $i', group: 'Cricket'),
        ],
        itemsBySubCategory: {
          'cricket': [fakeItem(id: 'narrowed', title: 'Narrowed Hit')],
        },
      );

      await tester.pumpWidget(
        wrapApp(
          child: const HomePage(),
          registry: ExtensionRegistry([extension]),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('See more'));
      await tester.pumpAndSettle();

      // The section heading matched a declared subcategory, so "See more"
      // carried that narrowing through instead of dumping the whole catalog.
      expect(extension.lastSubCategory, 'cricket');
      expect(find.text('Narrowed Hit'), findsOneWidget);
    });
  });

  group('expanded catalog', () {
    List<MediaItem> manyItems(int count, {String prefix = 'm'}) => [
      for (var i = 0; i < count; i++)
        fakeItem(id: '$prefix$i', title: 'Match $i'),
    ];

    testWidgets('shows every item directly, no heading and no See more', (
      tester,
    ) async {
      final registry = ExtensionRegistry([
        FakeExtension(
          categories: ['movie'],
          expanded: true,
          catalogName: 'TMDB',
          items: manyItems(CatalogShelf.previewLimit + 3),
        ),
      ]);

      await tester.pumpWidget(
        wrapApp(child: const HomePage(), registry: registry),
      );
      await tester.pumpAndSettle();

      // No capped preview, no "See more", no catalog-name heading — the
      // whole point of `expanded`: Home shows the feed directly.
      expect(find.text('See more'), findsNothing);
      expect(find.text('TMDB'), findsNothing);
      expect(
        find.text('Match ${CatalogShelf.previewLimit + 2}'),
        findsOneWidget,
      );
    });

    testWidgets('loads further pages as the viewer scrolls near the bottom', (
      tester,
    ) async {
      final registry = ExtensionRegistry([
        FakeExtension(
          categories: ['movie'],
          expanded: true,
          pages: {
            null: CatalogPage(items: manyItems(20), nextPage: 'p2'),
            'p2': const CatalogPage(
              items: [
                MediaItem(
                  ref: MediaRef(
                    extensionId: 'fake',
                    providerId: 'fake.p',
                    id: 'later',
                  ),
                  kind: MediaKind.movie,
                  title: 'Later Item',
                ),
              ],
            ),
          },
        ),
      ]);

      await tester.pumpWidget(
        wrapApp(child: const HomePage(), registry: registry),
      );
      await tester.pumpAndSettle();

      expect(find.text('Later Item'), findsNothing);

      // Drag repeatedly rather than `scrollUntilVisible`: with a shared
      // scroll controller feeding an async load, that helper's own settle
      // loop double-counts the newly-inserted item mid-scroll.
      for (
        var i = 0;
        i < 10 && find.text('Later Item').evaluate().isEmpty;
        i++
      ) {
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(find.text('Later Item'), findsOneWidget);
    });
  });

  group('plugin selector', () {
    ExtensionRegistry twoPlugins() => ExtensionRegistry([
      FakeExtension(
        id: 'fvck',
        name: 'fvck',
        categories: const ['live'],
        items: [fakeItem(id: 'a', extensionId: 'fvck', title: 'From fvck')],
      ),
      FakeExtension(
        id: 'example_extension',
        name: 'fvck (JS)',
        categories: const ['live'],
        items: [
          fakeItem(
            id: 'b',
            extensionId: 'example_extension',
            title: 'From example extension',
          ),
        ],
      ),
    ]);

    testWidgets('lists plugins by name, and switches the source', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrapApp(child: const HomePage(), registry: twoPlugins()),
      );
      await tester.pumpAndSettle();

      // The first plugin supplies content by default.
      expect(find.byType(PluginSelector), findsOneWidget);
      expect(find.text('From fvck'), findsOneWidget);
      expect(find.text('From example extension'), findsNothing);

      await tester.tap(find.byType(PluginSelector));
      await tester.pumpAndSettle();
      // The menu names plugins, not catalogs — the question it answers is
      // whose data you want.
      expect(find.text('fvck (JS)'), findsOneWidget);
      await tester.tap(find.text('fvck (JS)'));
      await tester.pumpAndSettle();

      expect(find.text('From example extension'), findsOneWidget);
      expect(find.text('From fvck'), findsNothing);
    });

    testWidgets('is hidden when only one plugin serves the category', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrapApp(
          child: const HomePage(),
          registry: ExtensionRegistry([
            FakeExtension(id: 'fvck', categories: const ['live']),
          ]),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PluginSelector), findsNothing);
    });
  });

  testWidgets('shows an empty state when nothing is installed', (tester) async {
    await tester.pumpWidget(
      wrapApp(child: const HomePage(), registry: ExtensionRegistry([])),
    );

    expect(find.text('No extensions installed'), findsOneWidget);
  });

  group('selection persistence', () {
    testWidgets('restores the last-browsed category on launch', (tester) async {
      final registry = ExtensionRegistry([
        FakeExtension(
          id: 'a',
          categories: ['live', 'sport'],
          items: [fakeItem(title: 'Some Match')],
        ),
      ]);

      await tester.pumpWidget(
        wrapApp(
          child: const HomePage(),
          registry: registry,
          homeCategoryStore: FakeCategorySelectionStore(initial: 'sport'),
        ),
      );
      await tester.pumpAndSettle();

      final sportChip = tester.widget<ChoiceChip>(
        find.widgetWithText(ChoiceChip, 'Sport'),
      );
      expect(sportChip.selected, isTrue);
    });

    testWidgets('picking a category saves it', (tester) async {
      final registry = ExtensionRegistry([
        FakeExtension(id: 'a', categories: ['live', 'sport']),
      ]);
      final store = FakeCategorySelectionStore();

      await tester.pumpWidget(
        wrapApp(
          child: const HomePage(),
          registry: registry,
          homeCategoryStore: store,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ChoiceChip, 'Sport'));
      await tester.pumpAndSettle();

      expect(store.saved, 'sport');
    });

    testWidgets('picking a plugin saves it', (tester) async {
      final pluginStore = FakePluginSelectionStore();

      await tester.pumpWidget(
        wrapApp(
          child: const HomePage(),
          registry: ExtensionRegistry([
            FakeExtension(id: 'fvck', name: 'fvck', categories: const ['live']),
            FakeExtension(
              id: 'example_extension',
              name: 'fvck (JS)',
              categories: const ['live'],
            ),
          ]),
          pluginController: PluginController(store: pluginStore),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(PluginSelector));
      await tester.pumpAndSettle();
      await tester.tap(find.text('fvck (JS)'));
      await tester.pumpAndSettle();

      expect(pluginStore.saved, 'example_extension');
    });

    testWidgets('a stored plugin that is gone falls back to the first', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrapApp(
          child: const HomePage(),
          registry: ExtensionRegistry([
            FakeExtension(
              id: 'fvck',
              categories: const ['live'],
              items: [
                fakeItem(id: 'a', extensionId: 'fvck', title: 'Still Here'),
              ],
            ),
          ]),
          // Names an extension that is no longer installed.
          pluginController: PluginController(
            store: FakePluginSelectionStore(),
            initial: 'uninstalled',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Still Here'), findsOneWidget);
    });
  });

  group('caching', () {
    FakeExtension twoCategories() => FakeExtension(
      id: 'a',
      categories: ['live', 'sport'],
      itemsByCategory: {
        'live': [fakeItem(id: 'l1', title: 'Live Item')],
        'sport': [fakeItem(id: 's1', title: 'Sport Item')],
      },
    );

    testWidgets('going back to a category shows it without re-fetching', (
      tester,
    ) async {
      final extension = twoCategories();
      await tester.pumpWidget(
        wrapApp(
          child: const HomePage(),
          registry: ExtensionRegistry([extension]),
        ),
      );
      await tester.pumpAndSettle();
      expect(extension.catalogCalls, 1);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Sport'));
      await tester.pumpAndSettle();
      expect(find.text('Sport Item'), findsOneWidget);
      expect(extension.catalogCalls, 2);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Live'));
      await tester.pumpAndSettle();

      // The whole point: already in hand, so shown rather than fetched again.
      expect(find.text('Live Item'), findsOneWidget);
      expect(extension.catalogCalls, 2);
    });

    testWidgets('a revisited category paints without a spinner first', (
      tester,
    ) async {
      final extension = FakeExtension(
        id: 'a',
        categories: ['live', 'sport'],
        // Slow enough that a re-fetch would be plainly visible as a spinner.
        catalogDelay: const Duration(milliseconds: 200),
        itemsByCategory: {
          'live': [fakeItem(id: 'l1', title: 'Live Item')],
          'sport': [fakeItem(id: 's1', title: 'Sport Item')],
        },
      );
      await tester.pumpWidget(
        wrapApp(
          child: const HomePage(),
          registry: ExtensionRegistry([extension]),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ChoiceChip, 'Sport'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Live'));
      // One frame only — no waiting for a future to settle.
      await tester.pump();

      expect(find.text('Live Item'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('the cache survives leaving Home and coming back', (
      tester,
    ) async {
      // The cache is app-level rather than page-level precisely for this:
      // HomeShell rebuilds its destinations, so HomePage's own state is gone
      // by the time the viewer returns.
      final extension = twoCategories();
      final cache = CatalogCache();

      Future<void> pumpHome() => tester.pumpWidget(
        wrapApp(
          child: const HomePage(),
          registry: ExtensionRegistry([extension]),
          catalogCache: cache,
        ),
      );

      await pumpHome();
      await tester.pumpAndSettle();
      expect(extension.catalogCalls, 1);

      // Away, and back to a freshly-built HomePage.
      await tester.pumpWidget(
        wrapApp(
          child: const SizedBox(),
          registry: ExtensionRegistry([extension]),
        ),
      );
      await tester.pumpAndSettle();
      await pumpHome();
      await tester.pumpAndSettle();

      expect(find.text('Live Item'), findsOneWidget);
      expect(extension.catalogCalls, 1);
    });

    testWidgets('pull to refresh is what fetches again', (tester) async {
      final extension = twoCategories();
      await tester.pumpWidget(
        wrapApp(
          child: const HomePage(),
          registry: ExtensionRegistry([extension]),
        ),
      );
      await tester.pumpAndSettle();
      expect(extension.catalogCalls, 1);

      await tester.fling(
        find.byType(CustomScrollView),
        const Offset(0, 300),
        1000,
      );
      await tester.pumpAndSettle();

      expect(extension.catalogCalls, 2);
      expect(find.text('Live Item'), findsOneWidget);
    });

    testWidgets('an installed update replaces the visible cached catalog', (
      tester,
    ) async {
      final registry = ExtensionRegistry([
        FakeExtension(
          id: 'nimora',
          version: '1.0.0',
          categories: ['sport'],
          items: [fakeItem(title: 'Old catalog')],
        ),
      ]);
      final controller = InstallerController(
        registry: registry,
        installer: ExtensionInstaller(),
        installedStore: FakeInstalledExtensionStore(),
        repoStore: FakeRepoStore(),
      );
      addTearDown(controller.close);

      await tester.pumpWidget(
        wrapApp(
          child: const HomePage(),
          registry: registry,
          installerController: controller,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Old catalog'), findsOneWidget);

      registry.install(
        FakeExtension(
          id: 'nimora',
          version: '1.1.0',
          categories: ['sport'],
          items: [fakeItem(title: 'Updated catalog')],
        ),
      );
      await controller.setRepoUrl('https://example.invalid/repo.json');
      await tester.pumpAndSettle();

      expect(find.text('Old catalog'), findsNothing);
      expect(find.text('Updated catalog'), findsOneWidget);
    });
  });
}
