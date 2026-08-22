# 12. App Engineering Guidelines

This document defines how Flutter app features are organized and changed. It
applies the useful parts of Clean Architecture without adding layers,
dependencies, or abstractions that have no concrete consumer.

## 12.1 Architecture in this workspace

The workspace is feature-first at the app boundary and package-first at shared
boundaries:

```
apps/app/lib/
  addons/ catalog/ detail/ home/ library/ player/ search/ settings/
packages/
  fvcksubs_core/           shared content model and protocol contract
  fvcksubs_extension_host/ extension routing, installation, JS bridge
  fvcksubs_storage/        app-owned persistence
```

Treat the packages as the domain and infrastructure boundaries shared by every
feature. Do not duplicate these layers inside every feature just to match a
generic folder template.

Dependencies remain inward and downward:

```
widgets and pages -> Cubits/controllers -> core, host, storage
app -> extension_host, core, storage
extension_host -> core, JS runtime
storage -> core
```

The app never learns provider-specific behavior. Extensions own catalogs,
metadata, source discovery, resolution, aliases, and upstream request details.

## 12.2 Feature layout

Keep code in the feature that owns the user journey. A feature may contain:

- pages and feature-only widgets for presentation;
- a Cubit/controller and immutable state for asynchronous, persisted, or shared
  state;
- a focused cache, service, or workflow when it is not shared across features.

Put reusable presentation primitives in `theme/`, `widgets/`, or `utils/` only
after a second consumer exists. Put shared content models, protocol changes,
and matching rules in `fvcksubs_core`; host and extension concerns belong in
`fvcksubs_extension_host`; persisted app-owned state belongs in
`fvcksubs_storage`.

Do not create repository interfaces, use-case classes, DTO layers, or feature
subdirectories by default. Add one only when it isolates a real boundary,
supports a second consumer, or makes a complex workflow independently testable.

## 12.3 State and dependency injection

Use `Cubit` as the default state manager. Use local widget state only for
short-lived presentation concerns such as focus, expansion, animation, and
dragging.

- Inject stores, registries, caches, and services through constructors.
- Scope a Cubit to the smallest route or shell that owns it.
- Model loading, usable data, refresh, and recoverable error states explicitly.
- Preserve usable content during background refreshes and recoverable errors.
- Prevent stale asynchronous results from replacing newer requests.
- Keep navigation, dialogs, snack bars, and other one-off effects outside
  persistent state; trigger them from explicit results or listeners.
- Use `BlocBuilder`, selectors, or `buildWhen` around only the subtree that
  depends on the state.

`AppScope` is the composition root for app-wide dependencies. Keep explicit
constructor injection and `AppScope`; do not add GetIt solely as another way to
locate the same services.

`Equatable` immutable states are the current standard. Do not add Freezed,
`Either`/Dartz, or `BlocObserver` unless a concrete requirement establishes
their benefit.

## 12.4 Error and data boundaries

Use exceptions at host, storage, transport, parsing, and native-player
boundaries. Catch them at the workflow/controller boundary where the app can
retain usable state, map an error to user-facing text, or offer a recovery
action.

- Do not turn every method into `Either` without a concrete caller benefit.
- Do not expose raw upstream, token, URL, or native error details in UI.
- Preserve a cached catalog or known source list when a refresh fails.
- A playback retry for signed or tokenized sources must resolve a fresh stream.
- Never use an error as a reason to auto-advance to another episode.

## 12.5 Widgets and workflows

Widgets render state and forward intent. They do not parse protocol payloads,
call storage, mutate a registry, resolve streams, or implement business rules.

Keep provider-agnostic behavior in the app. Render from protocol fields and
capabilities rather than provider IDs, source labels, sport names, or private
payload keys.

For playback, preserve the existing seams: inject the registry and player
builder, keep source discovery separate from fresh resolution, and forward
headers, DRM, subtitles, and live state without silently dropping them.

## 12.6 Comments and naming

Write comments in simple English when they explain intent, a constraint, or a
non-obvious trade-off. Keep them short and specific.

Good:

```dart
// Keep the current source until the refresh finishes.
// A signed URL must be resolved again after retry.
```

Avoid comments that restate code, narrate obvious control flow, or leave stale
implementation history. Prefer a clear name over a comment. Document public
APIs and security, protocol, caching, or native-player decisions that are easy
to break accidentally.

## 12.7 Testing and validation

Test workflow and state transitions at the Cubit/controller or service level.
Widget tests cover rendering and user intent; they must use the injected
registry and player builder rather than native playback views.

For changed app code, run from `apps/app`:

```sh
flutter analyze
flutter test
```

For package changes, run `dart analyze` and `dart test` in every affected
package. Validate cross-package protocol changes against all consumers, then
run `git diff --check`.
