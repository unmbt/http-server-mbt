/* R-N14/T-021: evhttp owns HTTP; hs_* owns file I/O and cancellation.
 * /__shutdown is a loopback-only demonstration lifecycle endpoint. */
#include "../../c_abi/runtime/platform.h"
#include "http_server.h"
#include <event2/buffer.h>
#include <event2/event.h>
#include <event2/http.h>
#include <event2/keyvalq_struct.h>
#include <event2/util.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef HS_EXAMPLE_DYNAMIC
#ifndef _WIN32
#include <dlfcn.h>
#endif
static struct {
  int32_t (*engine_create)(const char *, size_t, hs_callback_t, void *,
                           hs_operation_t **);
  int32_t (*engine_close)(hs_engine_t *, hs_callback_t, void *,
                          hs_operation_t **);
  void (*engine_release)(hs_engine_t *);
  int32_t (*submit)(hs_engine_t *, const hs_request_t *, hs_callback_t, void *,
                    hs_operation_t **);
  void (*cancel)(hs_operation_t *);
  void (*operation_release)(hs_operation_t *);
  int32_t (*meta)(hs_response_t *, hs_response_meta_t *);
  int32_t (*read)(hs_response_t *, uint32_t, hs_callback_t, void *,
                  hs_operation_t **);
  void (*response_release)(hs_response_t *);
  hs_span_t (*chunk_data)(const hs_chunk_t *);
  void (*chunk_release)(hs_chunk_t *);
} api;
static void *library;
static void *load_symbol(const char *name) {
#ifdef _WIN32
  return (void *)GetProcAddress((HMODULE)library, name);
#else
  return dlsym(library, name);
#endif
}
static int load_library(const char *path) {
#ifdef _WIN32
  library = (void *)LoadLibraryA(path);
#else
  library = dlopen(path, RTLD_NOW | RTLD_LOCAL);
#endif
  if (!library)
    return 0;
#define LOAD(field, name)                                                      \
  do {                                                                         \
    void *symbol = load_symbol(name);                                          \
    if (!symbol)                                                               \
      return 0;                                                                \
    memcpy(&api.field, &symbol, sizeof(symbol));                               \
  } while (0)
  LOAD(engine_create, "hs_engine_create_async");
  LOAD(engine_close, "hs_engine_close_async");
  LOAD(engine_release, "hs_engine_release");
  LOAD(submit, "hs_submit_async");
  LOAD(cancel, "hs_operation_cancel");
  LOAD(operation_release, "hs_operation_release");
  LOAD(meta, "hs_response_meta");
  LOAD(read, "hs_response_read_async");
  LOAD(response_release, "hs_response_release");
  LOAD(chunk_data, "hs_chunk_data");
  LOAD(chunk_release, "hs_chunk_release");
#undef LOAD
  return 1;
}
#define hs_engine_create_async api.engine_create
#define hs_engine_close_async api.engine_close
#define hs_engine_release api.engine_release
#define hs_submit_async api.submit
#define hs_operation_cancel api.cancel
#define hs_operation_release api.operation_release
#define hs_response_meta api.meta
#define hs_response_read_async api.read
#define hs_response_release api.response_release
#define hs_chunk_data api.chunk_data
#define hs_chunk_release api.chunk_release
#endif

typedef struct request_state {
  struct evhttp_request *request;
  struct evhttp_connection *connection;
  hs_response_t *response;
  hs_chunk_t *chunk;
  hs_operation_t *operation;
  int pending, disconnected, started;
} request_state;
typedef struct notice {
  request_state *request;
  hs_event_t event;
  struct notice *next;
} notice;
static hs_mutex queue_mutex = HS_MUTEX_INIT;
static notice *queue_head, *queue_tail;
static struct event_base *base;
static struct evhttp *http;
static struct evhttp_bound_socket *listener;
static hs_engine_t *engine;
static evutil_socket_t wake_pair[2];
static int wake_sent, stopping;

static hs_span_t span(const char *s) {
  hs_span_t r = {(const uint8_t *)s, strlen(s)};
  return r;
}
static void notify(void *data, const hs_event_t *event) {
  notice *n = calloc(1, sizeof(*n));
  if (!n)
    abort();
  n->request = data;
  n->event = *event;
  LOCK(&queue_mutex);
  if (queue_tail)
    queue_tail->next = n;
  else
    queue_head = n;
  queue_tail = n;
  if (!wake_sent) {
    char byte = 1;
    wake_sent = 1;
    (void)send(wake_pair[1], &byte, 1, 0);
  }
  UNLOCK(&queue_mutex);
}
static void release_request(request_state *s) {
  if (s->pending || !s->disconnected)
    return;
  if (s->chunk)
    hs_chunk_release(s->chunk);
  if (s->response)
    hs_response_release(s->response);
  if (s->request)
    evhttp_request_free(s->request);
  free(s);
}
static void disconnected(struct evhttp_connection *connection, void *data) {
  (void)connection;
  request_state *s = data;
  s->connection = NULL;
  s->disconnected = 1;
  if (s->operation)
    hs_operation_cancel(s->operation);
  release_request(s);
}
static void sent(struct evhttp_request *request, void *data) {
  (void)request;
  request_state *s = data;
  if (s->connection)
    evhttp_connection_set_closecb(s->connection, NULL, NULL);
  s->request = NULL;
  s->disconnected = 1;
  release_request(s);
}
static void fail_response(request_state *s, int code) {
  if (s->disconnected) {
    release_request(s);
    return;
  }
  if (s->started) {
    evhttp_connection_free(s->connection);
    return;
  }
  evhttp_send_error(s->request, code == HS_ERR_LIMIT ? 503 : 500,
                    "Static engine error");
}
static void read_next(request_state *s) {
  if (s->disconnected) {
    release_request(s);
    return;
  }
  s->pending = 1;
  int rc = hs_response_read_async(s->response, 65536, notify, s, &s->operation);
  if (rc) {
    s->pending = 0;
    fail_response(s, rc);
  }
}
static void chunk_sent(struct evhttp_connection *connection, void *data) {
  (void)connection;
  request_state *s = data;
  if (s->chunk) {
    hs_chunk_release(s->chunk);
    s->chunk = NULL;
  }
  read_next(s);
}
static void deliver(request_state *s, hs_event_t *e) {
  hs_operation_release(s->operation);
  s->operation = NULL;
  s->pending = 0;
  if (s->disconnected) {
    if (e->response)
      hs_response_release(e->response);
    if (e->chunk)
      hs_chunk_release(e->chunk);
    release_request(s);
    return;
  }
  if (e->code) {
    fail_response(s, e->code);
    return;
  }
  if (e->kind == HS_RESULT_NEXT) {
    struct evbuffer *body = evbuffer_new();
    evbuffer_add_printf(body, "dynamic libevent route\n");
    evhttp_send_reply(s->request, 200, "OK", body);
    evbuffer_free(body);
  } else if (e->kind == HS_RESULT_HANDLED) {
    s->response = e->response;
    hs_response_meta_t meta = {sizeof(meta), 1};
    hs_response_meta(s->response, &meta);
    struct evkeyvalq *headers = evhttp_request_get_output_headers(s->request);
    for (uint32_t i = 0; i < meta.header_count; i++)
      evhttp_add_header(headers, (const char *)meta.headers[i].name.data,
                        (const char *)meta.headers[i].value.data);
    s->started = 1;
    evhttp_send_reply_start(s->request, meta.status, NULL);
    read_next(s);
  } else if (e->kind == HS_RESULT_CHUNK) {
    s->chunk = e->chunk;
    hs_span_t bytes = hs_chunk_data(e->chunk);
    struct evbuffer *body = evbuffer_new();
    evbuffer_add(body, bytes.data, (size_t)bytes.length);
    evhttp_send_reply_chunk_with_cb(s->request, body, chunk_sent, s);
    evbuffer_free(body);
  } else if (e->kind == HS_RESULT_EOF) {
    evhttp_send_reply_end(s->request);
  }
}
static void on_wake(evutil_socket_t fd, short events, void *unused) {
  (void)events;
  (void)unused;
  char bytes[128];
  while (recv(fd, bytes, sizeof(bytes), 0) > 0) {
  }
  for (;;) {
    LOCK(&queue_mutex);
    notice *n = queue_head;
    if (n) {
      queue_head = n->next;
      if (!queue_head)
        queue_tail = NULL;
    } else
      wake_sent = 0;
    UNLOCK(&queue_mutex);
    if (!n)
      break;
    if (n->request)
      deliver(n->request, &n->event);
    else {
      hs_engine_release(engine);
      engine = NULL;
      evhttp_free(http);
      http = NULL;
      event_base_loopbreak(base);
    }
    free(n);
  }
}
static void shutdown_sent(struct evhttp_request *request, void *unused) {
  (void)request;
  (void)unused;
  hs_operation_t *op = NULL;
  if (hs_engine_close_async(engine, notify, NULL, &op) == 0)
    hs_operation_release(op);
}
static void on_request(struct evhttp_request *request, void *unused) {
  (void)unused;
  if (strcmp(evhttp_request_get_uri(request), "/__shutdown") == 0 &&
      !stopping) {
    stopping = 1;
    evhttp_request_set_on_complete_cb(request, shutdown_sent, NULL);
    evhttp_del_accept_socket(http, listener);
    listener = NULL;
    evhttp_send_reply(request, 200, "Stopping", NULL);
    return;
  }
  if (stopping) {
    evhttp_send_error(request, 503, "Stopping");
    return;
  }
  request_state *s = calloc(1, sizeof(*s));
  if (!s) {
    evhttp_send_error(request, 503, "Memory");
    return;
  }
  s->request = request;
  s->connection = evhttp_request_get_connection(request);
  evhttp_request_own(request);
  evhttp_connection_set_closecb(s->connection, disconnected, s);
  evhttp_request_set_on_complete_cb(request, sent, s);
  hs_header_t headers[256];
  uint32_t count = 0;
  struct evkeyvalq *input = evhttp_request_get_input_headers(request);
  for (struct evkeyval *h = input->tqh_first; h; h = h->next.tqe_next) {
    if (count == 256) {
      evhttp_send_error(request, 431, "Too many headers");
      return;
    }
    headers[count].name = span(h->key);
    headers[count].value = span(h->value);
    count++;
  }
  const char *method =
      evhttp_request_get_command(request) == EVHTTP_REQ_GET    ? "GET"
      : evhttp_request_get_command(request) == EVHTTP_REQ_HEAD ? "HEAD"
                                                               : "POST";
  hs_request_t r = {sizeof(r), 1, {0}, {0}, headers, count, 0};
  r.method = span(method);
  r.target = span(evhttp_request_get_uri(request));
  s->pending = 1;
  int rc = hs_submit_async(engine, &r, notify, s, &s->operation);
  if (rc) {
    s->pending = 0;
    fail_response(s, rc);
  }
}
typedef struct startup {
  hs_mutex mutex;
  hs_cond cond;
  int done;
  hs_event_t event;
} startup;
static void ready(void *data, const hs_event_t *event) {
  startup *s = data;
  LOCK(&s->mutex);
  s->event = *event;
  s->done = 1;
  BROADCAST(&s->cond);
  UNLOCK(&s->mutex);
}
int main(int argc, char **argv) {
  if (argc < 3) {
    fprintf(stderr, "usage: libevent_server CONFIG_JSON PORT [LIBRARY]\n");
    return 2;
  }
#ifdef HS_EXAMPLE_DYNAMIC
  if (argc < 4 || !load_library(argv[3])) {
    fprintf(stderr, "Cannot load ABI library\n");
    return 2;
  }
#endif
#ifdef _WIN32
  WSADATA ws;
  WSAStartup(MAKEWORD(2, 2), &ws);
#endif
  startup start = {HS_MUTEX_INIT, HS_COND_INIT, 0, {0}};
  hs_operation_t *op = NULL;
  if (hs_engine_create_async(argv[1], strlen(argv[1]), ready, &start, &op))
    return 2;
  LOCK(&start.mutex);
  while (!start.done)
    WAIT(&start.cond, &start.mutex);
  UNLOCK(&start.mutex);
  hs_operation_release(op);
  if (start.event.code) {
    fprintf(stderr, "Engine configuration failed: %d\n", start.event.code);
    return 2;
  }
  engine = start.event.engine;
  base = event_base_new();
  http = evhttp_new(base);
  /* This static/health-route demonstration accepts no request bodies. Do not
   * let evhttp buffer an arbitrarily large body before invoking on_request. */
  evhttp_set_max_body_size(http, 0);
  if (evutil_socketpair(AF_UNIX, SOCK_STREAM, 0, wake_pair))
    return 2;
  evutil_make_socket_nonblocking(wake_pair[0]);
  evutil_make_socket_nonblocking(wake_pair[1]);
  struct event *waker =
      event_new(base, wake_pair[0], EV_READ | EV_PERSIST, on_wake, NULL);
  event_add(waker, NULL);
  evhttp_set_gencb(http, on_request, NULL);
  listener = evhttp_bind_socket_with_handle(http, "127.0.0.1",
                                            (unsigned short)atoi(argv[2]));
  if (!listener) {
    fprintf(stderr, "Cannot listen\n");
    return 2;
  }
  struct sockaddr_in address;
  ev_socklen_t length = sizeof(address);
  getsockname(evhttp_bound_socket_get_fd(listener), (struct sockaddr *)&address,
              &length);
  printf("LISTENING %u\n", (unsigned)ntohs(address.sin_port));
  fflush(stdout);
  event_base_dispatch(base);
  event_free(waker);
  evutil_closesocket(wake_pair[0]);
  evutil_closesocket(wake_pair[1]);
  event_base_free(base);
#ifdef HS_EXAMPLE_DYNAMIC
#ifdef _WIN32
  FreeLibrary((HMODULE)library);
#else
  dlclose(library);
#endif
#endif
  return 0;
}
