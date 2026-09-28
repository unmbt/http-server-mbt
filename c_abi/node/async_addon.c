/* Included by addon.c. Node-API v8 only; the library owns the runtime. */
#include "../runtime/platform.h"
typedef struct hs_node_env hs_node_env;
typedef struct hs_node_operation {
  hs_operation_t *ptr;
  int refs;
} hs_node_operation;
static const napi_type_tag handle_tag = {UINT64_C(0x4f2b2fb494d54b17),
                                         UINT64_C(0xaab5270b35a75121)};
typedef struct hs_node_handle {
  hs_node_env *env;
  int kind, closed;
  void *ptr;
  struct hs_node_handle *next;
} hs_node_handle;
struct hs_node_env {
  hs_mutex mutex;
  hs_cond completed;
  int refs, pending, closing;
  napi_async_cleanup_hook_handle cleanup;
  hs_node_handle *handles;
};
typedef struct hs_node_work {
  hs_node_env *owner;
  napi_threadsafe_function tsfn;
  napi_deferred deferred;
  hs_event_t event;
  hs_node_operation *operation;
  int native_done, finalized;
} hs_node_work;
static void node_env_drop(hs_node_env *e) {
  LOCK(&e->mutex);
  int last = --e->refs == 0;
  UNLOCK(&e->mutex);
  if (last) {
#ifndef _WIN32
    pthread_cond_destroy(&e->completed);
    pthread_mutex_destroy(&e->mutex);
#endif
    free(e);
  }
}
static void node_pending_done(hs_node_env *e) {
  napi_async_cleanup_hook_handle hook = NULL;
  LOCK(&e->mutex);
  e->pending--;
  if (e->closing && !e->pending && e->cleanup) {
    hook = e->cleanup;
    e->cleanup = NULL;
  }
  UNLOCK(&e->mutex);
  if (hook) {
    napi_remove_async_cleanup_hook(hook);
  }
}
static void discarded_close(void *p, const hs_event_t *event) {
  (void)p;
  (void)event;
}
static void discard_engine(hs_node_env *e, hs_engine_t *engine) {
  (void)e;
  /* Only called on the host thread. Teardown must not depend on a TSFN:
   * Node may finalize every TSFN before the native close notification. */
  hs_operation_t *op = NULL;
  int rc = hs_engine_close_async(engine, discarded_close, NULL, &op);
  hs_engine_release(engine);
  if (!rc)
    hs_operation_release(op);
}
static void dispose_event(hs_node_env *e, hs_event_t *v) {
  if (v->engine) {
    discard_engine(e, v->engine);
    v->engine = NULL;
  }
  if (v->response) {
    hs_response_release(v->response);
    v->response = NULL;
  }
  if (v->chunk) {
    hs_chunk_release(v->chunk);
    v->chunk = NULL;
  }
}
static void release_node_handle(hs_node_handle *h) {
  if (!h->ptr)
    return;
  if (h->kind == 1) {
    if (h->closed)
      hs_engine_release(h->ptr);
    else
      discard_engine(h->env, h->ptr);
  } else if (h->kind == 2)
    hs_response_release(h->ptr);
  else if (h->kind == 3) {
    hs_node_operation *operation = h->ptr;
    LOCK(&h->env->mutex);
    if (operation->ptr)
      hs_operation_cancel(operation->ptr);
    int last = --operation->refs == 0;
    UNLOCK(&h->env->mutex);
    if (last)
      free(operation);
  } else if (h->kind == 4)
    hs_server_destroy(h->ptr);
  h->ptr = NULL;
}
static void handle_finalizer(napi_env env, void *data, void *hint) {
  (void)env;
  (void)hint;
  hs_node_handle *h = data;
  hs_node_env *e = h->env;
  hs_node_handle **slot = &e->handles;
  while (*slot && *slot != h)
    slot = &(*slot)->next;
  if (*slot)
    *slot = h->next;
  release_node_handle(h);
  free(h);
  node_env_drop(e);
}
static napi_value wrap_handle(napi_env env, hs_node_env *e, int kind,
                              void *ptr) {
  hs_node_handle *h = calloc(1, sizeof(*h));
  h->env = e;
  h->kind = kind;
  h->ptr = ptr;
  LOCK(&e->mutex);
  e->refs++;
  UNLOCK(&e->mutex);
  h->next = e->handles;
  e->handles = h;
  napi_value v;
  napi_create_object(env, &v);
  napi_wrap(env, v, h, handle_finalizer, NULL, NULL);
  napi_type_tag_object(env, v, &handle_tag);
  return v;
}
static hs_node_handle *get_handle(napi_env env, napi_value v, int kind) {
  hs_node_handle *h = NULL;
  bool tagged = false;
  if (napi_check_object_type_tag(env, v, &handle_tag, &tagged) != napi_ok ||
      !tagged || napi_unwrap(env, v, (void **)&h) != napi_ok || !h ||
      h->kind != kind || !h->ptr) {
    napi_throw_type_error(env, "HS_INVALID_HANDLE",
                          "Invalid or released handle");
    return NULL;
  }
  return h;
}
static napi_value node_string(napi_env env, const char *s) {
  napi_value v;
  napi_create_string_utf8(env, s, NAPI_AUTO_LENGTH, &v);
  return v;
}
static void property(napi_env env, napi_value o, const char *name,
                     napi_value v) {
  napi_set_named_property(env, o, name, v);
}
static napi_value node_error(napi_env env, int code) {
  char message[128];
  hs_error_copy(code, message, sizeof(message));
  static const char *codes[] = {
      "HS_OK",           "HS_CONFIG",  "HS_INVALID_ARGUMENT",
      "HS_IO",           "HS_CLOSED",  "HS_UNSUPPORTED",
      "HS_UPSTREAM",     "HS_TIMEOUT", "HS_CANCELLED",
      "HS_FILE_CHANGED", "HS_LIMIT",   "HS_BUSY",
      "HS_ABI_MISMATCH"};
  napi_value error;
  napi_create_error(
      env, node_string(env, code >= 0 && code <= 12 ? codes[code] : "HS_IO"),
      node_string(env, message), &error);
  return error;
}
static void work_finalizer(napi_env env, void *data, void *hint) {
  (void)env;
  (void)hint;
  hs_node_work *w = data;
  LOCK(&w->owner->mutex);
  w->finalized = 1;
  if (!w->native_done && w->operation)
    hs_operation_cancel(w->operation->ptr);
  while (!w->native_done)
    WAIT(&w->owner->completed, &w->owner->mutex);
  UNLOCK(&w->owner->mutex);
  dispose_event(w->owner, &w->event);
  if (w->operation) {
    LOCK(&w->owner->mutex);
    hs_operation_t *op = w->operation->ptr;
    w->operation->ptr = NULL;
    int last = --w->operation->refs == 0;
    UNLOCK(&w->owner->mutex);
    /* Keep the ABI operation until host-thread TSFN finalization, including
     * failed creation with no engine handle. This is the unload barrier. */
    hs_operation_release(op);
    if (last)
      free(w->operation);
  }
  node_pending_done(w->owner);
  node_env_drop(w->owner);
  free(w);
}
static void deliver_work(napi_env env, napi_value function, void *context,
                         void *data) {
  (void)function;
  (void)data;
  hs_node_work *w = context;
  hs_node_env *e = w->owner;
  LOCK(&e->mutex);
  int closing = e->closing;
  UNLOCK(&e->mutex);
  if (!env || closing) {
    dispose_event(e, &w->event);
    return;
  }
  hs_event_t *v = &w->event;
  if (v->code) {
    dispose_event(e, v);
    napi_reject_deferred(env, w->deferred, node_error(env, v->code));
  } else {
    napi_value result;
    napi_create_object(env, &result);
    if (v->kind == HS_RESULT_ENGINE) {
      result = wrap_handle(env, e, 1, v->engine);
      v->engine = NULL;
    } else if (v->kind == HS_RESULT_HANDLED) {
      hs_response_meta_t meta = {sizeof(meta), 1};
      hs_response_meta(v->response, &meta);
      property(env, result, "kind", node_string(env, "handled"));
      napi_value status;
      napi_create_int32(env, meta.status, &status);
      property(env, result, "status", status);
      napi_value headers;
      napi_create_array_with_length(env, meta.header_count, &headers);
      for (uint32_t i = 0; i < meta.header_count; i++) {
        napi_value pair, k, val;
        napi_create_array_with_length(env, 2, &pair);
        napi_create_string_utf8(env, (const char *)meta.headers[i].name.data,
                                (size_t)meta.headers[i].name.length, &k);
        napi_create_string_utf8(env, (const char *)meta.headers[i].value.data,
                                (size_t)meta.headers[i].value.length, &val);
        napi_set_element(env, pair, 0, k);
        napi_set_element(env, pair, 1, val);
        napi_set_element(env, headers, i, pair);
      }
      property(env, result, "headers", headers);
      napi_value length;
      if (meta.has_content_length)
        napi_create_bigint_uint64(env, meta.content_length, &length);
      else
        napi_get_null(env, &length);
      property(env, result, "contentLength", length);
      property(env, result, "response", wrap_handle(env, e, 2, v->response));
      v->response = NULL;
    } else if (v->kind == HS_RESULT_NEXT) {
      property(env, result, "kind", node_string(env, "next"));
    } else if (v->kind == HS_RESULT_CHUNK) {
      hs_span_t s = hs_chunk_data(v->chunk);
      napi_create_buffer_copy(env, (size_t)s.length, s.data, NULL, &result);
      hs_chunk_release(v->chunk);
      v->chunk = NULL;
    } else
      napi_get_null(env, &result);
    napi_resolve_deferred(env, w->deferred, result);
  }
}
static void work_completed(void *data, const hs_event_t *event) {
  hs_node_work *w = data;
  hs_node_env *e = w->owner;
  LOCK(&e->mutex);
  w->event = *event;
  if (!w->finalized) {
    napi_call_threadsafe_function(w->tsfn, NULL, napi_tsfn_nonblocking);
    napi_release_threadsafe_function(w->tsfn, napi_tsfn_release);
  }
  w->native_done = 1;
  BROADCAST(&e->completed);
  UNLOCK(&e->mutex);
}
static hs_node_work *new_work(napi_env env, hs_node_env *owner,
                              napi_value *promise) {
  hs_node_work *w = calloc(1, sizeof(*w));
  if (!w) {
    napi_throw_error(env, "HS_LIMIT", "Out of memory");
    return NULL;
  }
  w->owner = owner;
  LOCK(&owner->mutex);
  owner->refs++;
  owner->pending++;
  UNLOCK(&owner->mutex);
  if (napi_create_promise(env, &w->deferred, promise) != napi_ok ||
      napi_create_threadsafe_function(
          env, NULL, NULL, node_string(env, "http-server-mbt completion"), 1, 1,
          w, work_finalizer, w, deliver_work, &w->tsfn) != napi_ok) {
    node_pending_done(owner);
    node_env_drop(owner);
    free(w);
    napi_throw_error(env, "HS_LIMIT", "Cannot allocate completion channel");
    return NULL;
  }
  return w;
}
static napi_value finish_submit(napi_env env, hs_node_env *owner,
                                hs_node_work *w, napi_value promise, int rc,
                                hs_operation_t *op) {
  napi_value result;
  napi_create_object(env, &result);
  property(env, result, "promise", promise);
  if (rc) {
    napi_reject_deferred(env, w->deferred, node_error(env, rc));
    LOCK(&owner->mutex);
    w->native_done = 1;
    UNLOCK(&owner->mutex);
    napi_release_threadsafe_function(w->tsfn, napi_tsfn_release);
  } else {
    w->operation = calloc(1, sizeof(*w->operation));
    if (!w->operation)
      abort();
    w->operation->ptr = op;
    w->operation->refs = 2;
    property(env, result, "token", wrap_handle(env, owner, 3, w->operation));
  }
  return result;
}
static char *copy_js_string(napi_env env, napi_value value, size_t *len) {
  if (napi_get_value_string_utf8(env, value, NULL, 0, len) != napi_ok ||
      *len > 1048576) {
    napi_throw_type_error(env, "HS_INVALID_ARGUMENT",
                          "Expected UTF-8 string <= 1 MiB");
    return NULL;
  }
  char *s = malloc(*len + 1);
  if (!s) {
    napi_throw_error(env, "HS_LIMIT", "Out of memory");
    return NULL;
  }
  napi_get_value_string_utf8(env, value, s, *len + 1, len);
  return s;
}
static napi_value EngineCreate(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value args[1];
  hs_node_env *owner = NULL;
  napi_get_cb_info(env, info, &argc, args, NULL, (void **)&owner);
  if (argc != 1) {
    napi_throw_type_error(env, NULL, "Expected configuration JSON");
    return NULL;
  }
  size_t len;
  char *json = copy_js_string(env, args[0], &len);
  if (!json)
    return NULL;
  napi_value promise;
  hs_node_work *w = new_work(env, owner, &promise);
  if (!w) {
    free(json);
    return NULL;
  }
  hs_operation_t *op = NULL;
  int rc = hs_engine_create_async(json, len, work_completed, w, &op);
  free(json);
  return finish_submit(env, owner, w, promise, rc, op);
}
static napi_value EngineClose(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value args[1];
  hs_node_env *owner = NULL;
  napi_get_cb_info(env, info, &argc, args, NULL, (void **)&owner);
  hs_node_handle *h = argc ? get_handle(env, args[0], 1) : NULL;
  if (!h)
    return NULL;
  napi_value promise;
  hs_node_work *w = new_work(env, owner, &promise);
  if (!w)
    return NULL;
  hs_operation_t *op = NULL;
  int rc = hs_engine_close_async(h->ptr, work_completed, w, &op);
  if (!rc)
    h->closed = 1;
  return finish_submit(env, owner, w, promise, rc, op);
}
static napi_value EngineSubmit(napi_env env, napi_callback_info info) {
  size_t argc = 4;
  napi_value args[4];
  hs_node_env *owner = NULL;
  napi_get_cb_info(env, info, &argc, args, NULL, (void **)&owner);
  hs_node_handle *h = argc == 4 ? get_handle(env, args[0], 1) : NULL;
  if (!h)
    return NULL;
  size_t mn = 0, tn = 0;
  char *meth = copy_js_string(env, args[1], &mn);
  if (!meth)
    return NULL;
  char *target = copy_js_string(env, args[2], &tn);
  if (!target) {
    free(meth);
    return NULL;
  }
  uint32_t n = 0;
  bool array = false;
  napi_is_array(env, args[3], &array);
  if (!array || napi_get_array_length(env, args[3], &n) != napi_ok || n > 256) {
    free(meth);
    free(target);
    napi_throw_type_error(env, NULL, "Expected <=256 header pairs");
    return NULL;
  }
  hs_header_t *headers = calloc(n ? n : 1, sizeof(*headers));
  int valid = headers != NULL;
  for (uint32_t i = 0; i < n && valid; i++) {
    napi_value pair, k, v;
    napi_get_element(env, args[3], i, &pair);
    napi_get_element(env, pair, 0, &k);
    napi_get_element(env, pair, 1, &v);
    size_t a = 0, b = 0;
    headers[i].name.data = (uint8_t *)copy_js_string(env, k, &a);
    headers[i].name.length = a;
    if (headers[i].name.data) {
      headers[i].value.data = (uint8_t *)copy_js_string(env, v, &b);
      headers[i].value.length = b;
    }
    valid = headers[i].name.data && headers[i].value.data;
  }
  napi_value promise, result = NULL;
  hs_node_work *w = valid ? new_work(env, owner, &promise) : NULL;
  if (w) {
    hs_request_t r = {
        sizeof(r), 1, {(uint8_t *)meth, mn}, {(uint8_t *)target, tn}, headers,
        n,         0};
    hs_operation_t *op = NULL;
    int rc = hs_submit_async(h->ptr, &r, work_completed, w, &op);
    result = finish_submit(env, owner, w, promise, rc, op);
  }
  for (uint32_t i = 0; i < n && headers; i++) {
    free((void *)headers[i].name.data);
    free((void *)headers[i].value.data);
  }
  free(headers);
  free(meth);
  free(target);
  return result;
}
static napi_value ResponseRead(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value args[1];
  hs_node_env *owner = NULL;
  napi_get_cb_info(env, info, &argc, args, NULL, (void **)&owner);
  hs_node_handle *h = argc ? get_handle(env, args[0], 2) : NULL;
  if (!h)
    return NULL;
  napi_value promise;
  hs_node_work *w = new_work(env, owner, &promise);
  if (!w)
    return NULL;
  hs_operation_t *op = NULL;
  int rc = hs_response_read_async(h->ptr, 0, work_completed, w, &op);
  return finish_submit(env, owner, w, promise, rc, op);
}
static napi_value HandleRelease(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value args[1];
  napi_get_cb_info(env, info, &argc, args, NULL, NULL);
  hs_node_handle *h = NULL;
  bool tagged = false;
  if (argc &&
      napi_check_object_type_tag(env, args[0], &handle_tag, &tagged) ==
          napi_ok &&
      tagged && napi_unwrap(env, args[0], (void **)&h) == napi_ok && h)
    release_node_handle(h);
  napi_value v;
  napi_get_undefined(env, &v);
  return v;
}
static napi_value OperationCancel(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value args[1];
  napi_get_cb_info(env, info, &argc, args, NULL, NULL);
  hs_node_handle *h = argc ? get_handle(env, args[0], 3) : NULL;
  if (h) {
    hs_node_operation *op = h->ptr;
    LOCK(&h->env->mutex);
    if (op->ptr)
      hs_operation_cancel(op->ptr);
    UNLOCK(&h->env->mutex);
  }
  napi_value v;
  napi_get_undefined(env, &v);
  return v;
}
static void env_cleanup(napi_async_cleanup_hook_handle hook, void *data) {
  hs_node_env *e = data;
  LOCK(&e->mutex);
  e->closing = 1;
  e->cleanup = hook;
  e->pending++;
  UNLOCK(&e->mutex);
  for (hs_node_handle *h = e->handles; h; h = h->next)
    release_node_handle(h);
  node_pending_done(e);
  node_env_drop(e);
}
static hs_node_env *async_addon_init(napi_env env, napi_value exports) {
  hs_node_env *e = calloc(1, sizeof(*e));
  hs_mutex m = HS_MUTEX_INIT;
  hs_cond c = HS_COND_INIT;
  memcpy(&e->mutex, &m, sizeof(m));
  memcpy(&e->completed, &c, sizeof(c));
  e->refs = 1;
  napi_async_cleanup_hook_handle hook;
  napi_add_async_cleanup_hook(env, env_cleanup, e, &hook);
  napi_property_descriptor descriptors[] = {
      {"_createEngine", 0, EngineCreate, 0, 0, 0, napi_default, e},
      {"_closeEngine", 0, EngineClose, 0, 0, 0, napi_default, e},
      {"_submit", 0, EngineSubmit, 0, 0, 0, napi_default, e},
      {"_read", 0, ResponseRead, 0, 0, 0, napi_default, e},
      {"_release", 0, HandleRelease, 0, 0, 0, napi_default, e},
      {"_cancel", 0, OperationCancel, 0, 0, 0, napi_default, e}};
  napi_define_properties(
      env, exports, sizeof(descriptors) / sizeof(*descriptors), descriptors);
  return e;
}
