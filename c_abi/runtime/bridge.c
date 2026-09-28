/* ABI 1.1: C-owned queues and handles; only the owner enters MoonBit.
 * R-N14 / D-07: notifications run on a separate library thread. */
#include "platform.h"
#include <limits.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#ifndef _WIN32
#include <signal.h>
#endif
#include <moonbit.h>
#define HS_BUILD_DLL
#include "../include/http_server.h"

extern void moonbit_runtime_init(int, char **);
extern void moonbit_init(void);
typedef struct hs_instance {
  int refs, id, server, closing, closed, active, notifications;
  int capacity, block_size, response_count, response_limit;
  uint64_t budget, charged;
  struct hs_instance *next;
} hs_instance;
struct hs_engine {
  hs_instance base;
};
struct hs_server {
  hs_instance base;
};
struct hs_response {
  int refs, id, reading, released, chunks;
  hs_instance *instance;
  hs_response_meta_t meta;
  hs_header_t *headers;
  uint64_t metadata_charge;
};
struct hs_chunk {
  hs_instance *instance;
  hs_response_t *response;
  uint8_t *bytes;
  uint64_t length;
};
struct hs_operation {
  int refs, id, kind, cancelled, done, internal;
  hs_instance *instance;
  hs_response_t *response;
  hs_callback_t callback;
  void *user_data;
  uint8_t *input;
  int input_length, max_bytes;
  hs_request_t request;
  hs_header_t *headers;
  uint64_t input_charge;
  uint64_t allocation_charge;
  hs_event_t event;
  struct hs_operation *next;
};
static hs_mutex mutex = HS_MUTEX_INIT;
static hs_cond changed = HS_COND_INIT;
static hs_operation_t *commands, *commands_tail, *notices, *notices_tail;
static hs_instance *live_instances;
static int state, initialized, owner_done, owner_started, instances, active_ops,
    next_id = 1;
static void (*owner_entry)(void);
static hs_thread owner_thread, notify_thread;
static HS_LOCAL int is_notifier;
static HS_LOCAL int is_owner;
#ifdef _WIN32
static HANDLE wake_fd;
static OVERLAPPED wake_overlapped;
static HANDLE wake_event;
#else
static int wake_fd = -1;
#endif
static unsigned char wake_byte = 1;
static int wake_pending;
MOONBIT_FFI_EXPORT void hs_bridge_complete(hs_operation_t *, int, int);
static void unlink_instance(hs_instance *s) {
  hs_instance **p = &live_instances;
  while (*p && *p != s)
    p = &(*p)->next;
  if (*p)
    *p = s->next;
}
/* Called with mutex held, only by a host thread. A state flag alone cannot
 * prove a notifier has returned from this image: join it before reuse/unload.
 */
static void reap_runtime(void) {
  while (state >= 3) {
    if (state == 4) {
      state = 5;
      hs_thread thread = notify_thread;
      UNLOCK(&mutex);
      hs_thread_join(thread);
      LOCK(&mutex);
      state = 0;
      BROADCAST(&changed);
    } else
      WAIT(&changed, &mutex);
  }
}
static void release_barrier(hs_instance *s) {
  if (!s->closing || is_notifier || is_owner)
    return;
  while (!s->closed)
    WAIT(&changed, &mutex);
  while (s->notifications)
    WAIT(&changed, &mutex);
  while (instances == 0 && state != 0) {
    if (state >= 3)
      reap_runtime();
    else
      WAIT(&changed, &mutex);
  }
}
static uint64_t retained_bytes;
static int charge(hs_instance *s, uint64_t bytes) {
  if (bytes > s->budget || s->charged > s->budget - bytes || bytes > 67108864 ||
      retained_bytes > 67108864 - bytes)
    return 0;
  s->charged += bytes;
  retained_bytes += bytes;
  return 1;
}
static void uncharge(hs_instance *s, uint64_t bytes) {
  s->charged -= bytes;
  retained_bytes -= bytes;
}

static void instance_drop(hs_instance *s) {
  if (s && --s->refs == 0)
    free(s);
}
static void free_span(hs_span_t s) { free((void *)s.data); }
static void free_headers(hs_header_t *h, uint32_t n) {
  for (uint32_t i = 0; i < n; i++) {
    free_span(h[i].name);
    free_span(h[i].value);
  }
  free(h);
}
static int copy_span(hs_span_t *out, hs_span_t in) {
  if (in.length > 1048576 || (in.length && !in.data))
    return 0;
  uint8_t *p = malloc((size_t)in.length + 1);
  if (!p)
    return 0;
  if (in.length)
    memcpy(p, in.data, (size_t)in.length);
  p[in.length] = 0;
  out->data = p;
  out->length = in.length;
  return 1;
}
static void response_drop(hs_response_t *r) {
  if (r && --r->refs == 0) {
    free_headers(r->headers, r->meta.header_count);
    uncharge(r->instance, r->metadata_charge);
    r->instance->response_count--;
    instance_drop(r->instance);
    free(r);
  }
}
static void op_drop(hs_operation_t *o) {
  if (--o->refs)
    return;
  if (o->input_charge)
    uncharge(o->instance, o->input_charge);
  if (o->allocation_charge)
    uncharge(o->instance, o->allocation_charge);
  free(o->input);
  free_span(o->request.method);
  free_span(o->request.target);
  free_headers(o->headers, o->request.header_count);
  response_drop(o->response);
  instance_drop(o->instance);
  free(o);
}
static void wake_owner(void) {
  if (wake_pending)
    return;
#ifdef _WIN32
  if (!wake_fd)
    return;
  memset(&wake_overlapped, 0, sizeof(wake_overlapped));
  wake_overlapped.hEvent = (HANDLE)((uintptr_t)wake_event | 1);
  ResetEvent(wake_event);
  DWORD n = 0;
  if (!WriteFile(wake_fd, &wake_byte, 1, &n, &wake_overlapped) &&
      GetLastError() != ERROR_IO_PENDING)
    return;
#else
  if (wake_fd < 0)
    return;
  ssize_t n;
  do {
    n = write(wake_fd, &wake_byte, 1);
  } while (n < 0 && errno == EINTR);
  if (n != 1)
    return;
#endif
  wake_pending = 1;
}
static void enqueue(hs_operation_t *o) {
  o->next = NULL;
  if (commands_tail)
    commands_tail->next = o;
  else
    commands = o;
  commands_tail = o;
  wake_owner();
  BROADCAST(&changed);
}
static THREAD_RESULT owner_main(void *unused) {
  (void)unused;
  is_owner = 1;
#ifndef _WIN32
  /* Suppress broken-pipe delivery on library threads without changing the
   * host's process-wide disposition. Workers inherit this thread's mask. */
  sigset_t blocked;
  sigemptyset(&blocked);
  sigaddset(&blocked, SIGPIPE);
  pthread_sigmask(SIG_BLOCK, &blocked, NULL);
#endif
  if (!initialized) {
    moonbit_runtime_init(0, NULL);
    moonbit_init();
    initialized = 1;
  }
  owner_entry();
  LOCK(&mutex);
  /* Bootstrap/loop failures return here after MoonBit has unwound. Prevent
   * admission, fail every still-queued command, and retire live instances. */
  state = 3;
#ifdef _WIN32
  wake_fd = NULL;
  if (wake_event) {
    CloseHandle(wake_event);
    wake_event = NULL;
  }
#else
  wake_fd = -1;
#endif
  while (commands) {
    hs_operation_t *o = commands;
    commands = o->next;
    if (!commands)
      commands_tail = NULL;
    UNLOCK(&mutex);
    hs_bridge_complete(o, HS_ERR_IO, 0);
    LOCK(&mutex);
  }
  while (live_instances) {
    hs_instance *s = live_instances;
    live_instances = s->next;
    s->closed = s->closing = 1;
    instances--;
    instance_drop(s);
  }
  owner_done = 1;
  BROADCAST(&changed);
  UNLOCK(&mutex);
  is_owner = 0;
  THREAD_RETURN;
}
static THREAD_RESULT notify_main(void *unused) {
  (void)unused;
  is_notifier = 1;
  LOCK(&mutex);
  for (;;) {
    while (!notices && !owner_done)
      WAIT(&changed, &mutex);
    if (!notices && owner_done)
      break;
    hs_operation_t *o = notices;
    notices = o->next;
    if (!notices)
      notices_tail = NULL;
    UNLOCK(&mutex);
    if (o->callback)
      o->callback(o->user_data, &o->event);
    LOCK(&mutex);
    o->instance->notifications--;
    active_ops--;
    op_drop(o);
    BROADCAST(&changed);
    wake_owner();
  }
  UNLOCK(&mutex);
  if (owner_started)
    hs_thread_join(owner_thread);
  LOCK(&mutex);
  state = 4;
  BROADCAST(&changed);
  UNLOCK(&mutex);
  is_notifier = 0;
  THREAD_RETURN;
}
static int start_runtime(void) {
  if (state >= 3) {
    if (is_notifier)
      return 0;
    reap_runtime();
  }
  if (state)
    return 1;
  state = 1;
  owner_done = 0;
  owner_started = 0;
  next_id = 1;
  /* notifier first: it cannot see owner_done until the owner has started. */
  if (!hs_thread_start(&notify_thread, notify_main, NULL)) {
    state = 0;
    return 0;
  }
  if (!hs_thread_start(&owner_thread, owner_main, NULL)) {
    /* Thread creation failure is exceptional; notify owns its own shutdown. */
    state = 3;
    owner_done = 1;
    BROADCAST(&changed);
    return 0;
  }
  owner_started = 1;
  return 1;
}
static hs_operation_t *new_op(int kind, hs_instance *s, hs_callback_t cb,
                              void *ud) {
  if (next_id == INT_MAX)
    return NULL;
  hs_operation_t *o = calloc(1, sizeof(*o));
  if (!o)
    return NULL;
  if (kind <= 4) {
    if (!charge(s, sizeof(*o))) {
      free(o);
      return NULL;
    }
    o->allocation_charge = sizeof(*o);
  }
  o->refs = 2;
  o->id = next_id++;
  o->kind = kind;
  o->instance = s;
  o->callback = cb;
  o->user_data = ud;
  if (s) {
    s->refs++;
    s->active++;
    s->notifications++;
  }
  active_ops++;
  o->event.struct_size = sizeof(hs_event_t);
  o->event.abi_major = HS_ABI_MAJOR;
  return o;
}
static void abandon(hs_operation_t *o) {
  if (o->instance) {
    o->instance->active--;
    o->instance->notifications--;
  }
  active_ops--;
  o->refs = 1;
  op_drop(o);
}
static int create_async(int kind, const char *json, size_t len,
                        hs_callback_t cb, void *ud, hs_operation_t **out) {
  if (out)
    *out = NULL;
  if (!out || !cb || (len && !json) || len > 1048576)
    return HS_ERR_INVALID_ARG;
  LOCK(&mutex);
  if (active_ops >= 256 || instances >= 1024) {
    UNLOCK(&mutex);
    return HS_ERR_LIMIT;
  }
  if (!start_runtime()) {
    UNLOCK(&mutex);
    return HS_ERR_IO;
  }
  if (next_id >= INT_MAX - 1) {
    UNLOCK(&mutex);
    return HS_ERR_LIMIT;
  }
  hs_instance *s = calloc(1, sizeof(*s));
  if (!s) {
    wake_owner();
    UNLOCK(&mutex);
    return HS_ERR_LIMIT;
  }
  s->refs = 1;
  s->id = next_id++;
  s->server = kind == 2;
  s->capacity = 256;
  s->block_size = 65536;
  s->budget = 67108864;
  s->response_limit = 1024;
  hs_operation_t *o = new_op(kind, s, cb, ud);
  if (!o) {
    free(s);
    wake_owner();
    UNLOCK(&mutex);
    return HS_ERR_LIMIT;
  }
  if (!charge(s, len + 1)) {
    abandon(o);
    instance_drop(s);
    wake_owner();
    UNLOCK(&mutex);
    return HS_ERR_LIMIT;
  }
  o->input_charge = len + 1;
  o->input = malloc(len + 1);
  if (!o->input) {
    abandon(o);
    instance_drop(s);
    wake_owner();
    UNLOCK(&mutex);
    return HS_ERR_LIMIT;
  }
  if (len)
    memcpy(o->input, json, len);
  o->input[len] = 0;
  o->input_length = (int)len;
  s->next = live_instances;
  live_instances = s;
  instances++;
  *out = o;
  enqueue(o);
  UNLOCK(&mutex);
  return HS_OK;
}
HS_EXPORT uint32_t hs_abi_version(void) { return HS_ABI_VERSION; }
HS_EXPORT int32_t hs_engine_create_async(const char *j, size_t n,
                                         hs_callback_t cb, void *u,
                                         hs_operation_t **o) {
  return create_async(1, j, n, cb, u, o);
}
HS_EXPORT int32_t hs_server_start_async(const char *j, size_t n,
                                        hs_callback_t cb, void *u,
                                        hs_operation_t **o) {
  return create_async(2, j, n, cb, u, o);
}
static int close_async(hs_instance *s, hs_callback_t cb, void *ud,
                       hs_operation_t **out) {
  if (out)
    *out = NULL;
  if (!s || !cb || !out)
    return HS_ERR_INVALID_ARG;
  LOCK(&mutex);
  if (s->closing) {
    UNLOCK(&mutex);
    return HS_ERR_CLOSED;
  }
  hs_operation_t *o = new_op(s->server ? 6 : 5, s, cb, ud);
  if (!o) {
    UNLOCK(&mutex);
    return HS_ERR_LIMIT;
  }
  s->closing = 1;
  *out = o;
  enqueue(o);
  UNLOCK(&mutex);
  return HS_OK;
}
HS_EXPORT int32_t hs_engine_close_async(hs_engine_t *s, hs_callback_t cb,
                                        void *u, hs_operation_t **o) {
  return close_async((hs_instance *)s, cb, u, o);
}
HS_EXPORT int32_t hs_server_stop_async(hs_server_t *s, hs_callback_t cb,
                                       void *u, hs_operation_t **o) {
  return close_async((hs_instance *)s, cb, u, o);
}
HS_EXPORT void hs_engine_release(hs_engine_t *engine) {
  hs_instance *s = (hs_instance *)engine;
  if (!s)
    return;
  LOCK(&mutex);
  /* A release after close on a host thread is also a notification-return
   * barrier. Inside a callback release remains nonblocking. */
  release_barrier(s);
  instance_drop(s);
  UNLOCK(&mutex);
}
HS_EXPORT void hs_server_release(hs_server_t *s) {
  hs_engine_release((hs_engine_t *)s);
}
HS_EXPORT void hs_operation_release(hs_operation_t *o) {
  if (o) {
    LOCK(&mutex);
    /* Early operation release must not turn an asynchronous close into a
     * blocking call. Only an already closed instance needs the unload fence. */
    if (o->instance->closed)
      release_barrier(o->instance);
    op_drop(o);
    UNLOCK(&mutex);
  }
}
HS_EXPORT void hs_operation_cancel(hs_operation_t *o) {
  if (o) {
    LOCK(&mutex);
    if (!o->done && o->kind <= 4) {
      o->cancelled = 1;
      wake_owner();
    }
    UNLOCK(&mutex);
  }
}
HS_EXPORT int32_t hs_submit_async(hs_engine_t *engine, const hs_request_t *r,
                                  hs_callback_t cb, void *ud,
                                  hs_operation_t **out) {
  if (out)
    *out = NULL;
  if (!out || !cb || !engine || !r)
    return HS_ERR_INVALID_ARG;
  if (r->abi_major != 1 || r->struct_size < sizeof(*r))
    return HS_ERR_ABI_MISMATCH;
  if (r->header_count > 256 || (r->header_count && !r->headers))
    return HS_ERR_LIMIT;
  uint64_t total = r->method.length + r->target.length;
  if (r->method.length > 64 || r->target.length > 16384)
    return HS_ERR_LIMIT;
  for (uint32_t i = 0; i < r->header_count; i++) {
    if (r->headers[i].name.length > 65536 || r->headers[i].value.length > 65536)
      return HS_ERR_LIMIT;
    total += r->headers[i].name.length + r->headers[i].value.length;
    if (total > 65536)
      return HS_ERR_LIMIT;
  }
  hs_instance *s = (hs_instance *)engine;
  LOCK(&mutex);
  if (s->closing) {
    UNLOCK(&mutex);
    return HS_ERR_CLOSED;
  }
  if (s->active >= s->capacity) {
    UNLOCK(&mutex);
    return HS_ERR_LIMIT;
  }
  hs_operation_t *o = new_op(3, s, cb, ud);
  if (!o) {
    UNLOCK(&mutex);
    return HS_ERR_LIMIT;
  }
  uint64_t input_cost =
      total + (uint64_t)r->header_count * (sizeof(hs_header_t) + 2) + 2;
  if (!charge(s, input_cost)) {
    abandon(o);
    UNLOCK(&mutex);
    return HS_ERR_LIMIT;
  }
  o->input_charge = input_cost;
  int valid = copy_span(&o->request.method, r->method) &&
              copy_span(&o->request.target, r->target);
  if (valid && r->header_count) {
    o->headers = calloc(r->header_count, sizeof(*o->headers));
    valid = o->headers != NULL;
  }
  if (o->headers) {
    o->request.header_count = r->header_count;
    for (uint32_t i = 0; i < r->header_count && valid; i++)
      valid = copy_span(&o->headers[i].name, r->headers[i].name) &&
              copy_span(&o->headers[i].value, r->headers[i].value);
  }
  if (!valid) {
    abandon(o);
    UNLOCK(&mutex);
    return HS_ERR_INVALID_ARG;
  }
  *out = o;
  enqueue(o);
  UNLOCK(&mutex);
  return HS_OK;
}
HS_EXPORT int32_t hs_response_meta(hs_response_t *r, hs_response_meta_t *out) {
  if (!r || !out)
    return HS_ERR_INVALID_ARG;
  if (out->struct_size < sizeof(*out) || out->abi_major != 1)
    return HS_ERR_ABI_MISMATCH;
  *out = r->meta;
  return HS_OK;
}
HS_EXPORT int32_t hs_response_read_async(hs_response_t *r, uint32_t n,
                                         hs_callback_t cb, void *ud,
                                         hs_operation_t **out) {
  if (out)
    *out = NULL;
  if (!r || !cb || !out)
    return HS_ERR_INVALID_ARG;
  LOCK(&mutex);
  hs_instance *s = r->instance;
  if (r->released || s->closing) {
    UNLOCK(&mutex);
    return HS_ERR_CLOSED;
  }
  if (r->reading) {
    UNLOCK(&mutex);
    return HS_ERR_BUSY;
  }
  if (s->active >= s->capacity) {
    UNLOCK(&mutex);
    return HS_ERR_LIMIT;
  }
  hs_operation_t *o = new_op(4, s, cb, ud);
  if (!o) {
    UNLOCK(&mutex);
    return HS_ERR_LIMIT;
  }
  o->response = r;
  r->refs++;
  r->reading = 1;
  o->max_bytes =
      n == 0 ? s->block_size
             : (int)(n > (uint32_t)s->block_size ? (uint32_t)s->block_size : n);
  *out = o;
  enqueue(o);
  UNLOCK(&mutex);
  return HS_OK;
}
HS_EXPORT void hs_response_release(hs_response_t *r) {
  if (!r)
    return;
  LOCK(&mutex);
  if (!r->released) {
    r->released = 1;
    if (!r->instance->closing) {
      hs_operation_t *o = new_op(7, r->instance, NULL, NULL);
      if (o) {
        o->refs = 1;
        o->internal = 1;
        o->response = r;
        r->refs++;
        enqueue(o);
      }
    }
  }
  response_drop(r);
  UNLOCK(&mutex);
}
HS_EXPORT hs_span_t hs_chunk_data(const hs_chunk_t *c) {
  hs_span_t s = {c ? c->bytes : NULL, c ? c->length : 0};
  return s;
}
HS_EXPORT void hs_chunk_release(hs_chunk_t *c) {
  if (!c)
    return;
  LOCK(&mutex);
  uncharge(c->instance, c->length);
  if (c->response) {
    c->response->chunks--;
    response_drop(c->response);
  }
  instance_drop(c->instance);
  wake_owner();
  UNLOCK(&mutex);
  free(c->bytes);
  free(c);
}
HS_EXPORT size_t hs_error_copy(int32_t code, char *buf, size_t cap) {
  static const char *messages[] = {
      "Success",     "Configuration error",   "Invalid argument", "I/O error",
      "Closed",      "Unsupported operation", "Upstream error",   "Timeout",
      "Cancelled",   "File changed",          "Resource limit",   "Busy",
      "ABI mismatch"};
  const char *s = code >= 0 && code <= 12 ? messages[code] : "Unknown error";
  size_t n = strlen(s);
  if (buf && cap) {
    size_t copy = n < cap - 1 ? n : cap - 1;
    memcpy(buf, s, copy);
    buf[copy] = 0;
  }
  return n;
}

/* FFI functions below are private symbols, called exclusively on the owner. */
MOONBIT_FFI_EXPORT void hs_bridge_register(void (*entry)(void)) {
  owner_entry = entry;
}
#ifdef _WIN32
MOONBIT_FFI_EXPORT void hs_bridge_attach(HANDLE fd) {
  LOCK(&mutex);
  wake_fd = fd;
  wake_event = CreateEventW(NULL, TRUE, FALSE, NULL);
  wake_pending = 0;
  state = 2;
  wake_owner();
  UNLOCK(&mutex);
}
#else
MOONBIT_FFI_EXPORT void hs_bridge_attach(int fd) {
  LOCK(&mutex);
  wake_fd = fd;
  wake_pending = 0;
  state = 2;
  wake_owner();
  UNLOCK(&mutex);
}
#endif
MOONBIT_FFI_EXPORT void hs_bridge_ack(void) {
  LOCK(&mutex);
#ifdef _WIN32
  if (wake_pending) {
    DWORD n;
    GetOverlappedResult(wake_fd, &wake_overlapped, &n, TRUE);
  }
#endif
  wake_pending = 0;
  UNLOCK(&mutex);
}
MOONBIT_FFI_EXPORT hs_operation_t *hs_bridge_pop(void) {
  LOCK(&mutex);
  hs_operation_t *o = commands;
  if (o) {
    commands = o->next;
    if (!commands)
      commands_tail = NULL;
    o->next = NULL;
  }
  UNLOCK(&mutex);
  return o;
}
MOONBIT_FFI_EXPORT int hs_bridge_idle(void) {
  LOCK(&mutex);
  int stop = instances == 0 && active_ops == 0 && !commands;
  if (stop) {
    state = 3;
#ifdef _WIN32
    wake_fd = NULL;
    CloseHandle(wake_event);
    wake_event = NULL;
#else
    wake_fd = -1;
#endif
  }
  UNLOCK(&mutex);
  return stop;
}
MOONBIT_FFI_EXPORT int hs_bridge_null(void *p) { return p == NULL; }
MOONBIT_FFI_EXPORT int hs_bridge_kind(hs_operation_t *o) { return o->kind; }
MOONBIT_FFI_EXPORT int hs_bridge_id(hs_operation_t *o) { return o->id; }
MOONBIT_FFI_EXPORT int hs_bridge_instance(hs_operation_t *o) {
  return o->instance->id;
}
MOONBIT_FFI_EXPORT int hs_bridge_response_id(hs_operation_t *o) {
  return o->response->id;
}
MOONBIT_FFI_EXPORT int hs_bridge_max_bytes(hs_operation_t *o) {
  return o->max_bytes;
}
MOONBIT_FFI_EXPORT int hs_bridge_read_ready(hs_operation_t *o) {
  LOCK(&mutex);
  int ready = o->response->chunks == 0;
  UNLOCK(&mutex);
  return ready;
}
MOONBIT_FFI_EXPORT int hs_bridge_cancelled(hs_operation_t *o) {
  LOCK(&mutex);
  int c = o->cancelled || (o->kind <= 4 && o->instance->closing) ||
          (o->kind == 4 && o->response->released);
  UNLOCK(&mutex);
  return c;
}
MOONBIT_FFI_EXPORT int hs_bridge_active(hs_operation_t *o) {
  LOCK(&mutex);
  int n = o->instance->active;
  UNLOCK(&mutex);
  return n;
}
MOONBIT_FFI_EXPORT moonbit_bytes_t hs_bridge_input(hs_operation_t *o, int field,
                                                   int index) {
  hs_span_t s = {o->input, (uint64_t)o->input_length};
  if (field == 1)
    s = o->request.method;
  else if (field == 2)
    s = o->request.target;
  else if (field == 3)
    s = o->headers[index].name;
  else if (field == 4)
    s = o->headers[index].value;
  moonbit_bytes_t b = moonbit_make_bytes((int32_t)s.length, 0);
  if (s.length)
    memcpy(b, s.data, (size_t)s.length);
  return b;
}
MOONBIT_FFI_EXPORT int hs_bridge_header_count(hs_operation_t *o) {
  return (int)o->request.header_count;
}
MOONBIT_FFI_EXPORT void hs_bridge_limits(hs_operation_t *o, int capacity,
                                         int block, int budget, int responses) {
  LOCK(&mutex);
  o->instance->capacity = capacity;
  o->instance->block_size = block;
  o->instance->budget = (uint64_t)budget;
  o->instance->response_limit = responses;
  UNLOCK(&mutex);
}
MOONBIT_FFI_EXPORT hs_response_t *hs_bridge_response(hs_operation_t *o, int id,
                                                     int status, int64_t length,
                                                     int count) {
  hs_response_t *r = calloc(1, sizeof(*r));
  if (!r)
    return NULL;
  r->headers = calloc((size_t)count, sizeof(hs_header_t));
  if (count && !r->headers) {
    free(r);
    return NULL;
  }
  r->metadata_charge = sizeof(*r) + (uint64_t)count * sizeof(hs_header_t);
  r->refs = 1;
  r->id = id;
  r->instance = o->instance;
  LOCK(&mutex);
  if (r->instance->response_count >= r->instance->response_limit ||
      !charge(r->instance, r->metadata_charge)) {
    UNLOCK(&mutex);
    free(r->headers);
    free(r);
    return NULL;
  }
  r->instance->response_count++;
  r->instance->refs++;
  UNLOCK(&mutex);
  r->meta.struct_size = sizeof(r->meta);
  r->meta.abi_major = 1;
  r->meta.status = status;
  r->meta.header_count = (uint32_t)count;
  r->meta.headers = r->headers;
  r->meta.has_content_length = length >= 0;
  r->meta.content_length = length >= 0 ? (uint64_t)length : 0;
  o->event.response = r;
  o->event.kind = HS_RESULT_HANDLED;
  return r;
}
MOONBIT_FFI_EXPORT int hs_bridge_set_header(hs_response_t *r, int i,
                                            moonbit_bytes_t k,
                                            moonbit_bytes_t v) {
  hs_span_t a = {k, (uint64_t)Moonbit_array_length(k)},
            b = {v, (uint64_t)Moonbit_array_length(v)};
  LOCK(&mutex);
  uint64_t bytes = a.length + b.length + 2;
  int reserved = charge(r->instance, bytes);
  if (reserved)
    r->metadata_charge += bytes;
  UNLOCK(&mutex);
  if (!reserved)
    return 0;
  return copy_span(&r->headers[i].name, a) &&
         copy_span(&r->headers[i].value, b);
}
MOONBIT_FFI_EXPORT int hs_bridge_chunk(hs_operation_t *o,
                                       moonbit_bytes_t bytes) {
  int n = Moonbit_array_length(bytes);
  LOCK(&mutex);
  hs_chunk_t *c = calloc(1, sizeof(*c));
  if (!c) {
    UNLOCK(&mutex);
    return HS_ERR_LIMIT;
  }
  c->bytes = malloc((size_t)n);
  if (n && !c->bytes) {
    free(c);
    UNLOCK(&mutex);
    return HS_ERR_LIMIT;
  }
  if (!charge(o->instance, (uint64_t)n)) {
    free(c->bytes);
    free(c);
    UNLOCK(&mutex);
    return HS_ERR_LIMIT;
  }
  if (n)
    memcpy(c->bytes, bytes, (size_t)n);
  c->length = (uint64_t)n;
  c->instance = o->instance;
  c->instance->refs++;
  c->response = o->response;
  c->response->refs++;
  c->response->chunks++;
  o->event.chunk = c;
  o->event.kind = HS_RESULT_CHUNK;
  UNLOCK(&mutex);
  return 0;
}
MOONBIT_FFI_EXPORT void hs_bridge_complete(hs_operation_t *o, int code,
                                           int kind) {
  LOCK(&mutex);
  if (o->done) {
    UNLOCK(&mutex);
    return;
  }
  o->done = 1;
  o->event.code = code;
  if (kind >= 0)
    o->event.kind = (uint32_t)kind;
  if (code && o->event.response) {
    response_drop(o->event.response);
    o->event.response = NULL;
  }
  hs_instance *s = o->instance;
  if (o->kind == 1 || o->kind == 2) {
    if (code == 0) {
      s->refs++;
      if (o->kind == 1)
        o->event.engine = (hs_engine_t *)s;
      else
        o->event.server = (hs_server_t *)s;
    } else {
      s->closing = s->closed = 1;
      unlink_instance(s);
      instances--;
      instance_drop(s);
    }
  }
  if (o->kind == 5 || o->kind == 6) {
    s->closed = 1;
    unlink_instance(s);
    instances--;
    instance_drop(s);
    BROADCAST(&changed);
  }
  if (o->response && o->kind == 4)
    o->response->reading = 0;
  s->active--;
  o->next = NULL;
  if (notices_tail)
    notices_tail->next = o;
  else
    notices = o;
  notices_tail = o;
  BROADCAST(&changed);
  wake_owner();
  UNLOCK(&mutex);
}

typedef struct hs_sync {
  int done;
  hs_event_t event;
} hs_sync;
static void sync_callback(void *p, const hs_event_t *e) {
  hs_sync *s = p;
  LOCK(&mutex);
  s->event = *e;
  s->done = 1;
  BROADCAST(&changed);
  UNLOCK(&mutex);
}
HS_EXPORT int32_t hs_server_start(const char *j, size_t n, hs_server_t **out) {
  if (!out)
    return HS_ERR_INVALID_ARG;
  *out = NULL;
  if (is_notifier || is_owner)
    return HS_ERR_BUSY;
  hs_sync s = {0};
  hs_operation_t *o = NULL;
  int rc = hs_server_start_async(j, n, sync_callback, &s, &o);
  if (rc)
    return rc;
  LOCK(&mutex);
  while (!s.done)
    WAIT(&changed, &mutex);
  UNLOCK(&mutex);
  hs_operation_release(o);
  *out = s.event.server;
  return s.event.code;
}
HS_EXPORT int32_t hs_server_stop(hs_server_t *server) {
  if (!server)
    return HS_ERR_INVALID_ARG;
  if (is_notifier || is_owner)
    return HS_ERR_BUSY;
  hs_instance *i = (hs_instance *)server;
  LOCK(&mutex);
  if (i->closing) {
    while (!i->closed)
      WAIT(&changed, &mutex);
    UNLOCK(&mutex);
    return 0;
  }
  UNLOCK(&mutex);
  hs_sync s = {0};
  hs_operation_t *o = NULL;
  int rc = hs_server_stop_async(server, sync_callback, &s, &o);
  if (rc == HS_ERR_CLOSED)
    return hs_server_stop(server);
  if (rc)
    return rc;
  LOCK(&mutex);
  while (!s.done)
    WAIT(&changed, &mutex);
  UNLOCK(&mutex);
  hs_operation_release(o);
  return s.event.code;
}
HS_EXPORT void hs_server_destroy(hs_server_t *s) {
  if (s && hs_server_stop(s) == 0)
    hs_server_release(s);
}
