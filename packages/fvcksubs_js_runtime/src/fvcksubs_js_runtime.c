#include "fvcksubs_js_runtime.h"

#include <stdlib.h>
#include <string.h>

#if defined(_WIN32)
#include <windows.h>
#else
#include <time.h>
#endif

#include "quickjs/quickjs.h"

// Monotonic milliseconds — never the wall clock, which can jump backwards
// (NTP, DST, the user changing the time) and would otherwise either hang a
// script past its budget or kill it early.
static uint64_t now_ms(void) {
#if defined(_WIN32)
  return (uint64_t)GetTickCount64();
#else
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (uint64_t)ts.tv_sec * 1000u + (uint64_t)(ts.tv_nsec / 1000000);
#endif
}

// One in-flight qjsr_eval_async whose promise hasn't settled yet.
typedef struct {
  uint32_t id;
  JSValue promise;
  bool in_use;
} QjsrEvalSlot;

typedef struct {
  uint32_t request_id;
  JSValue resolve_func;
  JSValue reject_func;
  bool in_use;
} QjsrFetchSlot;

struct QjsrEngine {
  JSRuntime *rt;
  JSContext *ctx;
  QjsrHostCallback host_callback;
  QjsrFetchStartCallback fetch_start_callback;
  uint32_t next_request_id;
  QjsrFetchSlot *fetch_slots;
  int fetch_slots_len;
  QjsrEvalSlot *eval_slots;
  int eval_slots_len;
  uint32_t next_eval_id;
  uint64_t timeout_ms;   // 0 = no per-entry time budget
  uint64_t deadline_ms;  // 0 = not currently inside JS
  bool interrupted;      // set by the interrupt handler, cleared per entry
};

// Arms (or re-arms) this engine's per-entry time budget. Called on every
// entry into JS, and again before serializing a result — serialization can
// itself run script-controlled code (`toJSON`, `toString`), so it gets its
// own fresh budget rather than either running unbounded or inheriting an
// already-exhausted one from a script that legitimately used its whole
// slice.
static void begin_js(QjsrEngine *engine) {
  engine->deadline_ms =
      engine->timeout_ms ? now_ms() + engine->timeout_ms : 0;
}

// Disarms the budget — outside a JS entry there is nothing to interrupt,
// and leaving an expired deadline set would poison the next call.
static void end_js(QjsrEngine *engine) { engine->deadline_ms = 0; }

static int js_interrupt_handler(JSRuntime *rt, void *opaque) {
  (void)rt;
  QjsrEngine *engine = (QjsrEngine *)opaque;
  if (!engine || engine->deadline_ms == 0) return 0;
  if (now_ms() <= engine->deadline_ms) return 0;
  // Recorded because an interrupt raised inside a promise-reaction job does
  // not necessarily reject that job's promise — see abandon_pending_promise.
  engine->interrupted = true;
  return 1;
}

// Marks the start of a top-level entry from Dart (as opposed to the
// re-arming that happens within one).
static void enter_engine(QjsrEngine *engine) { engine->interrupted = false; }

// ---- shared helpers ----

// JSON-stringifies `val`, falling back to plain ToString for values JSON
// can't represent (undefined, functions) — same rule qjsr_eval documents.
// Returns a malloc'd string; never NULL. Does not free `val`.
static char *stringify_value(JSContext *ctx, JSValueConst val) {
  char *result;
  JSValue json_val = JS_JSONStringify(ctx, val, JS_UNDEFINED, JS_UNDEFINED);
  if (!JS_IsException(json_val) && !JS_IsUndefined(json_val)) {
    const char *s = JS_ToCString(ctx, json_val);
    result = strdup(s ? s : "null");
    if (s) JS_FreeCString(ctx, s);
  } else {
    JS_FreeValue(ctx, JS_GetException(ctx));
    const char *s = JS_ToCString(ctx, val);
    result = strdup(s ? s : "");
    if (s) JS_FreeCString(ctx, s);
  }
  JS_FreeValue(ctx, json_val);
  return result;
}

// ToString's `val` (never JSON — `JSON.stringify(someError)` is `"{}"`,
// since Error's message/stack aren't enumerable own properties). Returns a
// malloc'd string; never NULL. Does not free `val`.
static char *stringify_error(JSContext *ctx, JSValueConst val) {
  const char *s = JS_ToCString(ctx, val);
  char *result = strdup(s ? s : "unknown error");
  if (s) JS_FreeCString(ctx, s);
  return result;
}

// Drains every pending job (microtask). A job that itself throws (e.g. an
// unrelated unhandled rejection) has its exception dropped rather than
// stopping the rest from running — but an interrupt stops the drain, since
// every remaining job would be interrupted on entry anyway.
static void drain_jobs(QjsrEngine *engine) {
  JSContext *job_ctx;
  while (JS_IsJobPending(engine->rt)) {
    int err = JS_ExecutePendingJob(engine->rt, &job_ctx);
    if (err < 0) {
      JS_FreeValue(job_ctx, JS_GetException(job_ctx));
    }
    if (engine->interrupted) return;
  }
}

// Finds a free eval slot, growing the table if needed.
static QjsrEvalSlot *alloc_eval_slot(QjsrEngine *engine) {
  for (int i = 0; i < engine->eval_slots_len; i++) {
    if (!engine->eval_slots[i].in_use) return &engine->eval_slots[i];
  }
  int new_len = engine->eval_slots_len == 0 ? 4 : engine->eval_slots_len * 2;
  QjsrEvalSlot *grown =
      realloc(engine->eval_slots, sizeof(QjsrEvalSlot) * new_len);
  if (!grown) return NULL;
  for (int i = engine->eval_slots_len; i < new_len; i++) grown[i].in_use = false;
  engine->eval_slots = grown;
  QjsrEvalSlot *slot = &grown[engine->eval_slots_len];
  engine->eval_slots_len = new_len;
  return slot;
}

// ---- __host_call ----

// Reads the owning engine off the context opaque slot (set in
// qjsr_new_engine) rather than a JS closure, so there's no JSValue lifetime
// to manage for the engine pointer itself.
static JSValue js_host_call(JSContext *ctx, JSValueConst this_val, int argc,
                             JSValueConst *argv) {
  (void)this_val;
  QjsrEngine *engine = (QjsrEngine *)JS_GetContextOpaque(ctx);
  if (!engine || !engine->host_callback) {
    return JS_ThrowTypeError(ctx, "no host callback registered");
  }

  const char *name = argc > 0 ? JS_ToCString(ctx, argv[0]) : "";
  const char *args_json = argc > 1 ? JS_ToCString(ctx, argv[1]) : "";
  char *result =
      engine->host_callback(name ? name : "", args_json ? args_json : "");
  if (name) JS_FreeCString(ctx, name);
  if (args_json) JS_FreeCString(ctx, args_json);

  if (!result) {
    return JS_ThrowTypeError(ctx, "host callback failed");
  }
  JSValue ret = JS_NewString(ctx, result);
  free(result);
  return ret;
}

// ---- fetch ----

static QjsrFetchSlot *alloc_fetch_slot(QjsrEngine *engine) {
  for (int i = 0; i < engine->fetch_slots_len; i++) {
    if (!engine->fetch_slots[i].in_use) return &engine->fetch_slots[i];
  }
  int new_len =
      engine->fetch_slots_len == 0 ? 8 : engine->fetch_slots_len * 2;
  QjsrFetchSlot *grown =
      realloc(engine->fetch_slots, sizeof(QjsrFetchSlot) * new_len);
  if (!grown) return NULL;
  for (int i = engine->fetch_slots_len; i < new_len; i++) {
    grown[i].in_use = false;
  }
  engine->fetch_slots = grown;
  QjsrFetchSlot *slot = &grown[engine->fetch_slots_len];
  engine->fetch_slots_len = new_len;
  return slot;
}

static QjsrFetchSlot *find_fetch_slot(QjsrEngine *engine,
                                       uint32_t request_id) {
  for (int i = 0; i < engine->fetch_slots_len; i++) {
    if (engine->fetch_slots[i].in_use &&
        engine->fetch_slots[i].request_id == request_id) {
      return &engine->fetch_slots[i];
    }
  }
  return NULL;
}

static JSValue js_fetch(JSContext *ctx, JSValueConst this_val, int argc,
                         JSValueConst *argv) {
  (void)this_val;
  QjsrEngine *engine = (QjsrEngine *)JS_GetContextOpaque(ctx);
  if (!engine || !engine->fetch_start_callback) {
    return JS_ThrowTypeError(ctx, "fetch is not available");
  }
  if (argc < 1) return JS_ThrowTypeError(ctx, "fetch requires a url");

  const char *url = JS_ToCString(ctx, argv[0]);
  if (!url) return JS_EXCEPTION;

  JSValue options = argc > 1 ? argv[1] : JS_UNDEFINED;
  bool has_options = JS_IsObject(options);

  const char *method = "GET";
  char *method_owned = NULL;
  char *headers_json = NULL;
  const char *body = NULL;
  char *body_owned = NULL;

  if (has_options) {
    JSValue method_val = JS_GetPropertyStr(ctx, options, "method");
    if (!JS_IsUndefined(method_val) && !JS_IsNull(method_val)) {
      const char *m = JS_ToCString(ctx, method_val);
      if (m) {
        method_owned = strdup(m);
        method = method_owned;
        JS_FreeCString(ctx, m);
      }
    }
    JS_FreeValue(ctx, method_val);

    JSValue headers_val = JS_GetPropertyStr(ctx, options, "headers");
    if (JS_IsObject(headers_val)) {
      headers_json = stringify_value(ctx, headers_val);
    }
    JS_FreeValue(ctx, headers_val);

    JSValue body_val = JS_GetPropertyStr(ctx, options, "body");
    if (!JS_IsUndefined(body_val) && !JS_IsNull(body_val)) {
      const char *b = JS_ToCString(ctx, body_val);
      if (b) {
        body_owned = strdup(b);
        body = body_owned;
        JS_FreeCString(ctx, b);
      }
    }
    JS_FreeValue(ctx, body_val);
  }
  if (!headers_json) headers_json = strdup("{}");

  QjsrFetchSlot *slot = alloc_fetch_slot(engine);
  if (!slot) {
    JS_FreeCString(ctx, url);
    free(method_owned);
    free(headers_json);
    free(body_owned);
    return JS_ThrowTypeError(ctx, "too many in-flight fetches");
  }

  JSValue resolving_funcs[2];
  JSValue promise = JS_NewPromiseCapability(ctx, resolving_funcs);
  if (JS_IsException(promise)) {
    JS_FreeCString(ctx, url);
    free(method_owned);
    free(headers_json);
    free(body_owned);
    return promise;
  }

  uint32_t request_id = engine->next_request_id++;
  slot->request_id = request_id;
  slot->resolve_func = resolving_funcs[0];
  slot->reject_func = resolving_funcs[1];
  slot->in_use = true;

  engine->fetch_start_callback(request_id, url, method, headers_json, body);

  JS_FreeCString(ctx, url);
  free(method_owned);
  free(headers_json);
  free(body_owned);
  return promise;
}

// ---- lifecycle ----

QjsrEngine *qjsr_new_engine(void) {
  QjsrEngine *engine = calloc(1, sizeof(QjsrEngine));
  if (!engine) return NULL;

  engine->rt = JS_NewRuntime();
  if (!engine->rt) {
    free(engine);
    return NULL;
  }
  engine->ctx = JS_NewContext(engine->rt);
  if (!engine->ctx) {
    JS_FreeRuntime(engine->rt);
    free(engine);
    return NULL;
  }
  JS_SetContextOpaque(engine->ctx, engine);
  JS_SetInterruptHandler(engine->rt, js_interrupt_handler, engine);

  JSValue global = JS_GetGlobalObject(engine->ctx);
  JS_SetPropertyStr(
      engine->ctx, global, "__host_call",
      JS_NewCFunction(engine->ctx, js_host_call, "__host_call", 2));
  JS_SetPropertyStr(engine->ctx, global, "fetch",
                     JS_NewCFunction(engine->ctx, js_fetch, "fetch", 2));
  JS_FreeValue(engine->ctx, global);

  return engine;
}

void qjsr_free_engine(QjsrEngine *engine) {
  if (!engine) return;
  for (int i = 0; i < engine->eval_slots_len; i++) {
    if (engine->eval_slots[i].in_use) {
      JS_FreeValue(engine->ctx, engine->eval_slots[i].promise);
    }
  }
  free(engine->eval_slots);
  for (int i = 0; i < engine->fetch_slots_len; i++) {
    if (engine->fetch_slots[i].in_use) {
      JS_FreeValue(engine->ctx, engine->fetch_slots[i].resolve_func);
      JS_FreeValue(engine->ctx, engine->fetch_slots[i].reject_func);
    }
  }
  free(engine->fetch_slots);
  JS_FreeContext(engine->ctx);
  JS_FreeRuntime(engine->rt);
  free(engine);
}

void qjsr_set_host_callback(QjsrEngine *engine, QjsrHostCallback callback) {
  if (engine) engine->host_callback = callback;
}

void qjsr_set_fetch_start_callback(QjsrEngine *engine,
                                    QjsrFetchStartCallback callback) {
  if (engine) engine->fetch_start_callback = callback;
}

void qjsr_set_limits(QjsrEngine *engine, uint64_t memory_limit_bytes,
                      uint64_t max_stack_bytes, uint64_t timeout_ms) {
  if (!engine) return;
  // QuickJS treats 0 as "no limit" for both of these, matching this
  // function's own contract, so they pass straight through.
  JS_SetMemoryLimit(engine->rt, (size_t)memory_limit_bytes);
  JS_SetMaxStackSize(engine->rt, (size_t)max_stack_bytes);
  engine->timeout_ms = timeout_ms;
}

// ---- eval ----

char *qjsr_eval(QjsrEngine *engine, const char *code, char **error_out) {
  if (error_out) *error_out = NULL;
  JSContext *ctx = engine->ctx;

  enter_engine(engine);
  begin_js(engine);
  JSValue val =
      JS_Eval(ctx, code, strlen(code), "<eval>", JS_EVAL_TYPE_GLOBAL);
  begin_js(engine);  // fresh budget for serialization — see begin_js
  if (JS_IsException(val)) {
    JSValue exc = JS_GetException(ctx);
    if (error_out) *error_out = stringify_error(ctx, exc);
    JS_FreeValue(ctx, exc);
    JS_FreeValue(ctx, val);
    end_js(engine);
    return NULL;
  }

  char *result = stringify_value(ctx, val);
  JS_FreeValue(ctx, val);
  end_js(engine);
  return result;
}

char *qjsr_eval_async(QjsrEngine *engine, const char *code, char **error_out,
                       bool *out_pending, uint32_t *out_eval_id) {
  if (error_out) *error_out = NULL;
  if (out_pending) *out_pending = false;
  if (out_eval_id) *out_eval_id = 0;
  JSContext *ctx = engine->ctx;

  // Deliberately plain JS_EVAL_TYPE_GLOBAL, no JS_EVAL_FLAG_ASYNC: that flag
  // compiles the whole script as an async function body, whose own
  // completion value is an internal record — not the script's — so it
  // doesn't do what its doc comment implies for this purpose (confirmed via
  // a standalone probe: `(async () => 42)()` resolved to `{value:{}}`, not
  // `42`, under the flag). Plain eval's ordinary completion-value semantics
  // already return a real Promise whenever the top-level expression is
  // one — `(async () => { ... })()` or a `.then()` chain — which is all
  // this needs; genuine bare top-level `await` (outside any function) is
  // the one thing callers can't use here.
  enter_engine(engine);
  begin_js(engine);
  JSValue val = JS_Eval(ctx, code, strlen(code), "<eval>", JS_EVAL_TYPE_GLOBAL);
  if (JS_IsException(val)) {
    begin_js(engine);  // fresh budget for serialization — see begin_js
    JSValue exc = JS_GetException(ctx);
    if (error_out) *error_out = stringify_error(ctx, exc);
    JS_FreeValue(ctx, exc);
    JS_FreeValue(ctx, val);
    end_js(engine);
    return NULL;
  }

  if (!JS_IsPromise(val)) {
    // Not a promise at all (e.g. a plain synchronous script) — settle now,
    // matching qjsr_eval's behavior exactly.
    begin_js(engine);
    char *result = stringify_value(ctx, val);
    JS_FreeValue(ctx, val);
    end_js(engine);
    return result;
  }

  drain_jobs(engine);

  JSPromiseStateEnum state = JS_PromiseState(ctx, val);
  if (state == JS_PROMISE_PENDING) {
    QjsrEvalSlot *slot = alloc_eval_slot(engine);
    if (!slot) {
      JS_FreeValue(ctx, val);
      if (error_out) *error_out = strdup("out of eval slots");
      end_js(engine);
      return NULL;
    }
    slot->id = ++engine->next_eval_id;  // ids start at 1; 0 means "none"
    slot->promise = JS_DupValue(ctx, val);
    slot->in_use = true;
    JS_FreeValue(ctx, val);
    if (out_pending) *out_pending = true;
    if (out_eval_id) *out_eval_id = slot->id;
    // Leaving JS to wait on the host; the budget is re-armed when
    // qjsr_resolve_fetch next resumes this script.
    end_js(engine);
    return NULL;
  }

  begin_js(engine);  // fresh budget for serialization — see begin_js
  JSValue result = JS_PromiseResult(ctx, val);
  JS_FreeValue(ctx, val);
  if (state == JS_PROMISE_REJECTED) {
    if (error_out) *error_out = stringify_error(ctx, result);
    JS_FreeValue(ctx, result);
    end_js(engine);
    return NULL;
  }
  char *str = stringify_value(ctx, result);
  JS_FreeValue(ctx, result);
  end_js(engine);
  return str;
}

// ---- fetch resolution ----

void qjsr_resolve_fetch(QjsrEngine *engine, uint32_t request_id, int status,
                         const char *headers_json, const char *final_url,
                         const char *body, const char *error_message) {
  JSContext *ctx = engine->ctx;
  // Resuming the script: everything below runs its code (the promise
  // continuations), so it gets a fresh budget — the host's own round-trip
  // time is deliberately not charged against it.
  enter_engine(engine);
  begin_js(engine);
  QjsrFetchSlot *slot = find_fetch_slot(engine, request_id);
  if (slot) {
    if (error_message) {
      JSValue err = JS_NewError(ctx);
      JS_SetPropertyStr(ctx, err, "message",
                         JS_NewString(ctx, error_message));
      JSValue args[1] = {err};
      JSValue ret = JS_Call(ctx, slot->reject_func, JS_UNDEFINED, 1, args);
      JS_FreeValue(ctx, ret);
      JS_FreeValue(ctx, err);
    } else {
      // Reassemble the response object from parts, rather than building one
      // JSON string ourselves, so an unusual body/url string can't corrupt
      // the JSON we'd otherwise hand to JS_ParseJSON.
      JSValue result_obj = JS_NewObject(ctx);
      JS_SetPropertyStr(ctx, result_obj, "status", JS_NewInt32(ctx, status));
      JSValue headers_val = JS_ParseJSON(ctx, headers_json,
                                          strlen(headers_json),
                                          "<fetch-headers>");
      if (JS_IsException(headers_val)) {
        JS_FreeValue(ctx, JS_GetException(ctx));
        headers_val = JS_NewObject(ctx);
      }
      JS_SetPropertyStr(ctx, result_obj, "headers", headers_val);
      JS_SetPropertyStr(ctx, result_obj, "url",
                         JS_NewString(ctx, final_url ? final_url : ""));
      JS_SetPropertyStr(ctx, result_obj, "body",
                         JS_NewString(ctx, body ? body : ""));
      JSValue args[1] = {result_obj};
      JSValue ret = JS_Call(ctx, slot->resolve_func, JS_UNDEFINED, 1, args);
      JS_FreeValue(ctx, ret);
      JS_FreeValue(ctx, result_obj);
    }
    JS_FreeValue(ctx, slot->resolve_func);
    JS_FreeValue(ctx, slot->reject_func);
    slot->in_use = false;
  }

  drain_jobs(engine);
  end_js(engine);
}

char *qjsr_take_completion(QjsrEngine *engine, uint32_t *out_id,
                            char **out_error) {
  if (out_id) *out_id = 0;
  if (out_error) *out_error = NULL;
  JSContext *ctx = engine->ctx;

  for (int i = 0; i < engine->eval_slots_len; i++) {
    QjsrEvalSlot *slot = &engine->eval_slots[i];
    if (!slot->in_use) continue;

    JSPromiseStateEnum state = JS_PromiseState(ctx, slot->promise);
    if (state == JS_PROMISE_PENDING) {
      // Interrupting a promise-reaction job aborts the job rather than
      // rejecting the promise it would have settled, so a runaway
      // continuation would leave this pending forever and its caller never
      // answered. Failing it explicitly is the point of having a budget: it
      // must not be possible to hang the host by exhausting it.
      if (!engine->interrupted) continue;
      JS_FreeValue(ctx, slot->promise);
      slot->in_use = false;
      if (out_id) *out_id = slot->id;
      if (out_error) *out_error = strdup("InternalError: interrupted");
      return NULL;
    }

    JSValue result = JS_PromiseResult(ctx, slot->promise);
    JS_FreeValue(ctx, slot->promise);
    slot->in_use = false;
    if (out_id) *out_id = slot->id;

    begin_js(engine);  // fresh budget for serialization — see begin_js
    char *out;
    if (state == JS_PROMISE_REJECTED) {
      if (out_error) *out_error = stringify_error(ctx, result);
      out = NULL;
    } else {
      out = stringify_value(ctx, result);
    }
    end_js(engine);
    JS_FreeValue(ctx, result);
    return out;
  }
  return NULL;
}

void qjsr_free_string(char *s) { free(s); }
