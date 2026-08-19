#include <stdbool.h>
#include <stdint.h>

#if _WIN32
#define FFI_PLUGIN_EXPORT __declspec(dllexport)
#else
#define FFI_PLUGIN_EXPORT
#endif

// Opaque handle over one QuickJS runtime + context pair.
typedef struct QjsrEngine QjsrEngine;

// A host function callable from JS via `__host_call(name, argsJson)`.
//
// Must return a malloc'd, NUL-terminated string (freed internally right
// after it's copied into the JS return value), or NULL to signal failure
// (surfaced to JS as a thrown TypeError).
typedef char *(*QjsrHostCallback)(const char *name, const char *argsJson);

// Invoked synchronously when JS calls the global `fetch(url, options)`. Must
// not block — kick off the real (async, on the Dart side) request and
// return; the result arrives later via qjsr_resolve_fetch. `headersJson` is
// always a JSON object string (`"{}"` if none given); `method` defaults to
// `"GET"`; `body` is NULL if none given.
typedef void (*QjsrFetchStartCallback)(uint32_t requestId, const char *url,
                                        const char *method,
                                        const char *headersJson,
                                        const char *body);

// Creates a runtime + context and installs the `__host_call`/`fetch`
// globals. Returns NULL on allocation failure.
FFI_PLUGIN_EXPORT QjsrEngine *qjsr_new_engine(void);

FFI_PLUGIN_EXPORT void qjsr_free_engine(QjsrEngine *engine);

// Installs (or replaces) the function `__host_call` forwards to. NULL
// disables it — calling `__host_call` from JS then throws.
FFI_PLUGIN_EXPORT void qjsr_set_host_callback(QjsrEngine *engine,
                                               QjsrHostCallback callback);

// Installs (or replaces) the function `fetch` forwards to. NULL disables it
// — calling `fetch` from JS then throws synchronously (the promise it would
// have returned is never created).
FFI_PLUGIN_EXPORT void qjsr_set_fetch_start_callback(
    QjsrEngine *engine, QjsrFetchStartCallback callback);

// Caps what a script can consume. Any parameter may be 0 to leave that limit
// off. Applies to every subsequent call into this engine.
//
// `memory_limit_bytes` and `max_stack_bytes` are runtime-wide and always in
// force. `timeout_ms` is a *per-entry* budget on JS execution, re-armed each
// time control enters JS (an eval, or the job drain inside
// qjsr_resolve_fetch) — so a script waiting on a slow fetch is not charged
// for the host's own round-trip time, only for the JS it actually runs.
// Exceeding it interrupts the script, surfacing as an ordinary JS exception
// through the usual error_out paths.
FFI_PLUGIN_EXPORT void qjsr_set_limits(QjsrEngine *engine,
                                        uint64_t memory_limit_bytes,
                                        uint64_t max_stack_bytes,
                                        uint64_t timeout_ms);

// Evaluates `code` as a global-scope script.
//
// On success, returns a malloc'd string: the result JSON-stringified where
// possible (covers objects/arrays/primitives), or its plain ToString for
// values JSON can't represent (undefined, functions). Free with
// qjsr_free_string.
//
// On a thrown JS exception, returns NULL and, if error_out is non-NULL,
// sets *error_out to a malloc'd message (also freed with qjsr_free_string).
FFI_PLUGIN_EXPORT char *qjsr_eval(QjsrEngine *engine, const char *code,
                                   char **error_out);

// Like qjsr_eval, but understands a script whose result is a Promise —
// e.g. `(async () => { ... await fetch(url) ... })()`, or a `.then()`
// chain. (Bare top-level `await`, outside any function, isn't supported —
// wrap the script in an async IIFE as above.) Behavior:
//
// - Result isn't a Promise, or is one that's already settled (no real async
//   work happened, or everything awaited was already resolved): behaves
//   exactly like qjsr_eval — the settled value, or NULL + *error_out on
//   rejection.
// - Still pending (e.g. waiting on a fetch): returns NULL, *error_out
//   untouched, *out_pending set true, and *out_eval_id set to a nonzero id.
//   The eventual settlement is collected via qjsr_take_completion.
//
// Any number of evals may be pending at once — they share one JS event loop,
// exactly as concurrent work in a browser would, so a fan-out across
// providers doesn't need an engine each.
FFI_PLUGIN_EXPORT char *qjsr_eval_async(QjsrEngine *engine, const char *code,
                                         char **error_out, bool *out_pending,
                                         uint32_t *out_eval_id);

// Resolves or rejects the fetch identified by request_id and drains the JS
// job queue so any `.then()`/`await` continuations run immediately.
//
// error_message non-NULL rejects the fetch's promise with that message;
// otherwise it resolves with `{status, headers, url, body}` built from the
// other params (headers_json must be a JSON object string; final_url is the
// URL after any redirects the Dart side followed).
//
// Settling this fetch may complete any number of pending evals; collect them
// with qjsr_take_completion afterwards.
FFI_PLUGIN_EXPORT void qjsr_resolve_fetch(
    QjsrEngine *engine, uint32_t request_id, int status,
    const char *headers_json, const char *final_url, const char *body,
    const char *error_message);

// Takes one settled eval, if any.
//
// Sets *out_id to its qjsr_eval_async id and returns its value (malloc'd),
// or returns NULL with *out_error set (malloc'd) if it rejected. When
// nothing has settled, *out_id is 0 and the return is NULL — check *out_id,
// not the return value. Call in a loop until *out_id is 0, since one fetch
// can unblock several evals at once.
FFI_PLUGIN_EXPORT char *qjsr_take_completion(QjsrEngine *engine,
                                              uint32_t *out_id,
                                              char **out_error);

FFI_PLUGIN_EXPORT void qjsr_free_string(char *s);
