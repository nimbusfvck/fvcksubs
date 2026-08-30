# fvcksubs_js_runtime

A build-owned QuickJS-ng engine, callable from Dart via FFI, with a real
`async`/`fetch` bridge and resource limits on top. Early slice of PLAN.md's
Phase 3 extension runtime — see PLAN.md §3 (M9/M10/M11 notes), §18, and §19.

Bounded by default (64 MB memory, 1 MB stack, 10 s per JS entry, 15 s per
`fetch`), but **not yet safe to run genuinely untrusted JS**: no stream-URL
validation, no bundle signature verification, no `Isolate.kill` backstop, and
it runs in-process on the app's own isolate. The host primitives themselves
(`crypto`/`codec`/`match`/`storage`, including storage's per-extension
namespacing) live a layer up, in `fvcksubs_extension_host`.

`fetch` takes an optional `timeoutMs` for one call, clamped to
`maxFetchTimeout` so a single slow upstream cannot widen the budget for every
other request. It travels to the Dart side as a private header — the C bridge
carries url/method/headers/body and nothing else — which is stripped before
the request goes out, so it never reaches the network.

## Structure

* `src/quickjs/` — quickjs-ng's core library, vendored at `v0.16.1` (MIT;
  `quickjs.c`, `libregexp.c`, `libunicode.c`, `dtoa.c` + headers — the set
  `CMakeLists.txt`'s `qjs` target builds, unmodified from upstream).
* `src/fvcksubs_js_runtime.{c,h}` — the FFI shim: create/free an engine,
  eval a script (sync or Promise-aware), register the generic `__host_call`
  callback, `fetch`'s Promise-capability + resolve/reject plumbing, and the
  memory/stack/time limits.
* `hook/build.dart` — compiles both of the above for whatever platform/arch
  Flutter is already targeting, via `native_toolchain_c`'s `CBuilder`.
* `lib/fvcksubs_js_runtime.dart` — `JsEngine`, the hand-written Dart wrapper:
  `eval`/`evalAsync`, `setHostFunction`, `fetch` (real HTTP via `dio`, host
  allowlist, manual redirect revalidation, per-request timeout shim), and the
  limit options. A response that arrives after `dispose()` is dropped rather
  than handed to a freed engine.

Regenerate bindings after changing the header: `dart run ffigen --config ffigen.yaml`.
