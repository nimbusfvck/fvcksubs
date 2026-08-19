# fvcksubs

fvcksubs is an extension-driven streaming client built with Flutter. The app
provides browsing, playback, library state, extension installation, and a
sandboxed JavaScript runtime. Content catalogs and stream sources are supplied
by separately installed extensions.

## Repository layout

- `apps/app`: Flutter application
- `packages/fvcksubs_core`: shared models, protocol, and matching
- `packages/fvcksubs_extension_host`: extension registry, installer, and bridge
- `packages/fvcksubs_js_runtime`: embedded QuickJS runtime
- `packages/fvcksubs_storage`: application persistence
- `sdk/js`: JavaScript SDK for extension authors
- `docs`: architecture and protocol documentation

## Documentation

Start with [the documentation index](docs/README.md). Extension authors should
also read the [JavaScript SDK guide](sdk/js/README.md).

## Development

Install workspace dependencies from the repository root:

```sh
dart pub get
```

Run the application:

```sh
cd apps/app
flutter run
```

The application starts without bundled content extensions. Configure an
extension index from the Addons screen to install one.
