# Remove legacy protocol support

Status: parked

The production contract is protocol version 2. The remaining version 1 code
exists only because several app screens, test fixtures, and host tests still
use the old models. Remove it in buildable checkpoints.

## Current state

- Catalog and search render protocol v2 items.
- Detail, playback, progress, favorites, and Library support protocol v2.
- The protocol v2 Library types now use the canonical names:
  `LibraryController`, `LibraryState`, `LibraryStore`, and `UserMediaState`.
- Old Library types are isolated behind the `Legacy` prefix.
- Nimora already publishes an API version 2 manifest and payloads.
- The JavaScript SDK documents protocol version 2.

## Work items

### 1. Migrate app fixtures to protocol v2

- Replace `FakeExtension` catalog, search, metadata, and stream fixtures with
  `MediaItemV2`, `VersionedCatalogPage`, and `MediaDetailV2` payloads.
- Replace legacy detail and playback tests with equivalent v2 coverage.
- Keep provider IDs, categories, grouping IDs, and labels supplied by fixtures;
  do not add app-owned provider vocabulary.

Done when no app test needs `MediaItem`, `MediaDetail`, `CatalogPage`,
`SeriesSeason`, or `LegacyLibraryController`.

### 2. Remove legacy app screens and state

- Remove the old detail page, episode helpers, favorite button, media card, and
  media grid after their v2 replacements cover the same user flows.
- Remove the legacy branch from `PlayerPage`, `playItem`, and `PlaybackMedia`.
- Remove the legacy Library controller from `AppScope`, `FvcksubsApp`, and
  startup.
- Remove legacy sections from `LibraryPage`.

Done when the app imports only the canonical Library controller and accepts
only `MediaItemV2` at navigation and playback boundaries.

### 3. Make the host protocol v2-only

- Make `Manifest.parse` accept only API version 2.
- Replace `catalogVersioned` and `searchVersioned` with direct v2 return types.
- Keep only `metaV2`, `sourcesV2`, and `externalSubtitlesV2`, then rename them
  to their canonical role names.
- Remove version-based decoding and all version 1 JavaScript bridge branches.
- Update installer and role tests to use API version 2 fixtures.

Done when installing or loading an API version 1 extension fails with a clear
unsupported-version error.

### 4. Remove legacy core and storage types

- Remove `MediaItem`, `MediaDetail`, `CatalogPage`, and their supporting
  version 1-only models.
- Remove `VersionedMediaItem` and its version 1 adapter.
- Rename the remaining v2 core types only where the suffix no longer adds
  useful meaning.
- Remove `LegacyLibraryController`, `LegacyLibraryStore`,
  `LegacyUserMediaState`, their exports, and their tests.
- Remove the old `library.records` storage path. Keep `library.records.v2`
  unless a separate storage migration intentionally changes it.

Done when `rg` finds no production reference to `Legacy`, version 1 content
models, compatibility adapters, or dual protocol methods.

### 5. Update documentation and SDK

- Remove compatibility language from architecture and protocol documents.
- Ensure the JavaScript declarations and runtime expose only the final host
  method names.
- Rebuild the Nimora bundle after the SDK surface is final.
- Update examples and fixtures together with every contract change.

## Validation

Run after each checkpoint:

```sh
dart format --output=none --set-exit-if-changed <changed Dart files>
flutter analyze
flutter test
git diff --check
```

Before completion, also run the core, extension host, storage, JavaScript
runtime, app, and Nimora test suites. The app test suite should pass with its
normal concurrency; serial execution may be used to diagnose shared-state
fixtures but is not the final result.

## Commit checkpoints

1. `test(app): migrate fixtures to protocol v2`
2. `refactor(app): remove legacy content flow`
3. `refactor(host): require protocol v2`
4. `refactor(core): remove protocol v1 models`
5. `docs: finalize protocol v2 contract`

Do not push these commits without confirmation.
