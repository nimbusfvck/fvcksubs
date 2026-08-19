# fvcksubs_js_runtime

A build-owned QuickJS-ng engine, callable from Dart via FFI, with a real
`async`/`fetch` bridge and resource limits on top. Early slice of PLAN.md's
Phase 3 extension runtime — see PLAN.md §3 (M9/M10/M11 notes), §18, and §19.

Bounded by default (64 MB memory, 1 MB stack, 10 s per JS entry), but **not
yet safe to run genuinely untrusted JS**: no storage namespacing, no
stream-URL validation, no bundle signature verification, no `Isolate.kill`
backstop, and it runs in-process on the app's own isolate. No
`crypto`/`codec`/`storage` host primitives yet either.

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
  allowlist, manual redirect revalidation), and the limit options.

Regenerate bindings after changing the header: `dart run ffigen --config ffigen.yaml`.
