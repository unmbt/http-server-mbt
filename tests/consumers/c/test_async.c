/* N-13/N-19/N-20: real public async ABI, no engine polling. */
#include "../../../c_abi/runtime/platform.h"
#include "http_server.h"
#include <assert.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
typedef struct waiter {
  hs_mutex mutex;
  hs_cond cond;
  int done, count;
  hs_event_t event;
} waiter;
static void completed(void *p, const hs_event_t *e) {
  hs_server_t *server = NULL;
  assert(hs_server_start("{}", 2, &server) == HS_ERR_BUSY);
  waiter *w = p;
  LOCK(&w->mutex);
  assert(!w->done);
  w->event = *e;
  w->done = 1;
  w->count++;
  BROADCAST(&w->cond);
  UNLOCK(&w->mutex);
}
static void signal_handler(int number) { (void)number; }
static hs_event_t result(waiter *w, hs_operation_t *op) {
  LOCK(&w->mutex);
  while (!w->done)
    WAIT(&w->cond, &w->mutex);
  hs_event_t e = w->event;
  w->done = 0;
  UNLOCK(&w->mutex);
  hs_operation_release(op);
  return e;
}
static hs_span_t span(const char *s) {
  hs_span_t r = {(const uint8_t *)s, strlen(s)};
  return r;
}
static hs_engine_t *engine(waiter *w) {
  hs_operation_t *op = NULL;
  const char *config =
      "{\"root\":\".\",\"handle_error\":false,\"cache_control\":\"no-cache\"}";
  assert(hs_engine_create_async(config, strlen(config), completed, w, &op) ==
         0);
  hs_event_t e = result(w, op);
  assert(e.code == 0 && e.kind == HS_RESULT_ENGINE);
  return e.engine;
}
static hs_event_t request(waiter *w, hs_engine_t *engine, const char *verb,
                          const char *path, hs_header_t *headers, uint32_t n) {
  hs_request_t req = {sizeof(req), 1, {0}, {0}, headers, n, 0};
  req.method = span(verb);
  req.target = span(path);
  hs_operation_t *op = NULL;
  assert(hs_submit_async(engine, &req, completed, w, &op) == 0);
  return result(w, op);
}
static void close_engine(waiter *w, hs_engine_t *engine) {
  hs_operation_t *op = NULL;
  assert(hs_engine_close_async(engine, completed, w, &op) == 0);
  assert(result(w, op).code == 0);
  hs_engine_release(engine);
}
int main(void) {
  waiter w = {HS_MUTEX_INIT, HS_COND_INIT, 0, 0, {0}};
  assert(hs_abi_version() == HS_ABI_VERSION);
  signal(SIGTERM, signal_handler);
#ifndef _WIN32
  signal(SIGPIPE, signal_handler);
  signal(SIGUSR2, signal_handler);
#endif
  FILE *f = fopen("async-fixture.txt", "wb");
  assert(f);
  fputs("hello async ABI\n", f);
  fclose(f);
  hs_engine_t *first = engine(&w), *second = engine(&w);
#ifndef _WIN32
  assert(signal(SIGPIPE, signal_handler) == signal_handler);
  assert(signal(SIGUSR2, signal_handler) == signal_handler);
#endif
  hs_event_t e = request(&w, first, "GET", "/async-fixture.txt", NULL, 0);
  assert(e.code == 0 && e.kind == HS_RESULT_HANDLED);
  hs_response_t *response = e.response;
  hs_response_meta_t meta = {sizeof(meta), 1};
  assert(hs_response_meta(response, &meta) == 0);
  assert(meta.status == 200 && meta.has_content_length &&
         meta.content_length == 16);
  hs_operation_t *op = NULL;
  assert(hs_response_read_async(response, 5, completed, &w, &op) == 0);
  e = result(&w, op);
  assert(e.code == 0 && e.kind == HS_RESULT_CHUNK);
  hs_chunk_t *retained = e.chunk;
  hs_span_t bytes = hs_chunk_data(retained);
  assert(bytes.length == 5 && memcmp(bytes.data, "hello", 5) == 0);
  /* Holding a chunk deliberately stalls the next read. A concurrent read is
   * rejected without a callback; cancellation must wake the stalled read. */
  assert(hs_response_read_async(response, 5, completed, &w, &op) == 0);
  hs_operation_t *rejected = NULL;
  assert(hs_response_read_async(response, 5, completed, &w, &rejected) ==
             HS_ERR_BUSY &&
         !rejected);
  hs_operation_cancel(op);
  assert(result(&w, op).code == HS_ERR_CANCELLED);
  close_engine(&w, first);
  assert(memcmp(hs_chunk_data(retained).data, "hello", 5) == 0);
  assert(hs_response_read_async(response, 5, completed, &w, &op) ==
             HS_ERR_CLOSED &&
         !op);
  hs_chunk_release(retained);
  hs_response_release(response);
  e = request(&w, second, "HEAD", "/async-fixture.txt", NULL, 0);
  assert(e.code == 0);
  assert(hs_response_read_async(e.response, 0, completed, &w, &op) == 0);
  response = e.response;
  e = result(&w, op);
  assert(e.kind == HS_RESULT_EOF);
  hs_response_release(response);
  e = request(&w, second, "GET", "/missing-async-fixture", NULL, 0);
  assert(e.code == 0 && e.kind == HS_RESULT_NEXT);
  hs_header_t range = {span("Range"), span("bytes=2-5")};
  e = request(&w, second, "GET", "/async-fixture.txt", &range, 1);
  assert(e.code == 0);
  response = e.response;
  meta.struct_size = sizeof(meta);
  meta.abi_major = 1;
  assert(hs_response_meta(response, &meta) == 0 && meta.status == 206);
  assert(hs_response_read_async(response, 0, completed, &w, &op) == 0);
  e = result(&w, op);
  bytes = hs_chunk_data(e.chunk);
  assert(bytes.length == 4 && memcmp(bytes.data, "llo ", 4) == 0);
  hs_chunk_release(e.chunk);
  hs_response_release(response);
  hs_header_t ambiguous[2] = {{span("Host"), span("a")},
                              {span("host"), span("b")}};
  e = request(&w, second, "GET", "/async-fixture.txt", ambiguous, 2);
  assert(e.code == HS_ERR_INVALID_ARG);
  hs_header_t invalid = {span("Bad\tHeader"), span("value")};
  e = request(&w, second, "GET", "/async-fixture.txt", &invalid, 1);
  assert(e.code == HS_ERR_INVALID_ARG);
  e = request(&w, second, "GET", "/async-fixture.txt", NULL, 0);
  assert(e.code == 0);
  response = e.response;
  assert(hs_response_read_async(response, 5, completed, &w, &op) == 0);
  e = result(&w, op);
  assert(e.kind == HS_RESULT_CHUNK);
  hs_chunk_release(e.chunk);
  f = fopen("async-fixture.txt", "wb");
  assert(f);
  fputs("changed", f);
  fclose(f);
  assert(hs_response_read_async(response, 5, completed, &w, &op) == 0);
  e = result(&w, op);
  assert(e.code == HS_ERR_FILE_CHANGED && !e.chunk);
  hs_response_release(response);
  close_engine(&w, second);
  for (int n = 0; n < 10; n++) {
    hs_engine_t *restart = engine(&w);
    close_engine(&w, restart);
  }
  assert(hs_engine_create_async("{bad", 4, completed, &w, &op) == 0);
  assert(result(&w, op).code == HS_ERR_CONFIG);
  const char *small = "{\"root\":\".\",\"limits\":{\"queued_operations\":1}}";
  assert(hs_engine_create_async(small, strlen(small), completed, &w, &op) == 0);
  e = result(&w, op);
  assert(e.code == 0);
  hs_engine_t *limited = e.engine;
  e = request(&w, limited, "GET", "/async-fixture.txt", NULL, 0);
  assert(e.code == 0);
  response = e.response;
  assert(hs_response_read_async(response, 1, completed, &w, &op) == 0);
  e = result(&w, op);
  assert(e.kind == HS_RESULT_CHUNK);
  retained = e.chunk;
  assert(hs_response_read_async(response, 1, completed, &w, &op) == 0);
  hs_request_t req = {sizeof(req), 1, {0}, {0}, NULL, 0, 0};
  req.method = span("GET");
  req.target = span("/");
  assert(hs_submit_async(limited, &req, completed, &w, &rejected) ==
             HS_ERR_LIMIT &&
         !rejected);
  waiter close_waiter = {HS_MUTEX_INIT, HS_COND_INIT, 0, 0, {0}};
  hs_operation_t *closing = NULL;
  assert(hs_engine_close_async(limited, completed, &close_waiter, &closing) ==
         0);
  assert(result(&w, op).code == HS_ERR_CANCELLED);
  assert(result(&close_waiter, closing).code == 0);
  hs_engine_release(limited);
  hs_response_release(response);
  hs_chunk_release(retained);
  assert(signal(SIGTERM, SIG_DFL) == signal_handler);
#ifndef _WIN32
  assert(signal(SIGPIPE, SIG_DFL) == signal_handler);
  assert(signal(SIGUSR2, SIG_DFL) == signal_handler);
#endif
  remove("async-fixture.txt");
  puts("Async ABI: create/read/HEAD/Range/Next/headers/close/chunk/restart "
       "PASS");
  return 0;
}
