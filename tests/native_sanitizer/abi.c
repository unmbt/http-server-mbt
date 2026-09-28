/* D-18: production ABI queues/refcounts/owner/notifier under ASan/UBSan.
 * Only the MoonBit dispatcher is replaced. Protocol/file behavior is covered
 * separately by test_async.c linked to the actual MoonBit libraries. */
#include "../../c_abi/runtime/bridge.c"
#include <assert.h>
#include <stdio.h>
moonbit_bytes_t moonbit_make_bytes(int32_t n, int value) {
  moonbit_bytes_t bytes = malloc((size_t)n + 1);
  assert(bytes);
  memset(bytes, value, (size_t)n + 1);
  return bytes;
}
void moonbit_runtime_init(int argc, char **argv) {
  (void)argc;
  (void)argv;
}
static void dispatcher(void) {
  for (;;) {
    LOCK(&mutex);
    while (!commands && (instances || active_ops))
      WAIT(&changed, &mutex);
    if (!commands) {
      UNLOCK(&mutex);
      return;
    }
    if (commands->kind == 1 && commands->input_length == 4 &&
        memcmp(commands->input, "fail", 4) == 0) {
      UNLOCK(&mutex);
      return;
    }
    UNLOCK(&mutex);
    hs_operation_t *o = hs_bridge_pop();
    int code = hs_bridge_cancelled(o) ? HS_ERR_CANCELLED : HS_OK;
    hs_bridge_complete(o, code,
                       o->kind == 1   ? HS_RESULT_ENGINE
                       : o->kind == 3 ? HS_RESULT_NEXT
                                      : HS_RESULT_DONE);
  }
}
void moonbit_init(void) { hs_bridge_register(dispatcher); }
typedef struct completion {
  hs_mutex lock;
  hs_cond changed;
  int done;
  hs_event_t event;
} completion;
static void done(void *ptr, const hs_event_t *e) {
  completion *c = ptr;
  /* Blocking legacy entry must reject callback-thread reentry. */
  hs_server_t *server = NULL;
  assert(hs_server_start("{}", 2, &server) == HS_ERR_BUSY);
  LOCK(&c->lock);
  assert(!c->done);
  c->event = *e;
  c->done = 1;
  BROADCAST(&c->changed);
  UNLOCK(&c->lock);
}
static hs_event_t wait_for(completion *c, hs_operation_t *op) {
  LOCK(&c->lock);
  while (!c->done)
    WAIT(&c->changed, &c->lock);
  hs_event_t e = c->event;
  c->done = 0;
  UNLOCK(&c->lock);
  hs_operation_release(op);
  return e;
}
typedef struct worker {
  hs_engine_t *engine;
  unsigned seed, accepted, rejected;
} worker;
static THREAD_RESULT submitter(void *ptr) {
  worker *w = ptr;
  completion c = {HS_MUTEX_INIT, HS_COND_INIT, 0, {0}};
  const hs_request_t r = {sizeof(r),
                          1,
                          {(const uint8_t *)"GET", 3},
                          {(const uint8_t *)"/", 1},
                          NULL,
                          0,
                          0};
  for (unsigned i = 0; i < 128; i++) {
    w->seed = w->seed * 1664525u + 1013904223u;
    hs_operation_t *op = NULL;
    int rc = hs_submit_async(w->engine, &r, done, &c, &op);
    if (rc) {
      assert((rc == HS_ERR_LIMIT || rc == HS_ERR_CLOSED) && !op);
      w->rejected++;
      continue;
    }
    w->accepted++;
    if (w->seed & 1)
      hs_operation_cancel(op);
    hs_event_t event = wait_for(&c, op);
    assert(event.code == 0 || event.code == HS_ERR_CANCELLED);
  }
  THREAD_RETURN;
}
int main(int argc, char **argv) {
  assert(argc == 2);
  unsigned seed = (unsigned)strtoul(argv[1], NULL, 16);
  completion c = {HS_MUTEX_INIT, HS_COND_INIT, 0, {0}};
  hs_operation_t *op = NULL;
  for (int round = 0; round < 12; round++) {
    assert(hs_engine_create_async("{}", 2, done, &c, &op) == 0);
    hs_event_t created = wait_for(&c, op);
    assert(created.code == 0);
    worker workers[4];
    hs_thread threads[4];
    for (int i = 0; i < 4; i++) {
      workers[i] = (worker){created.engine, seed + (unsigned)i, 0, 0};
      assert(hs_thread_start(&threads[i], submitter, &workers[i]));
    }
    if (round & 1) {
      assert(hs_engine_close_async(created.engine, done, &c, &op) == 0);
      assert(wait_for(&c, op).code == 0);
    }
    for (int i = 0; i < 4; i++)
      hs_thread_join(threads[i]);
    if (!(round & 1)) {
      assert(hs_engine_close_async(created.engine, done, &c, &op) == 0);
      assert(wait_for(&c, op).code == 0);
    }
    hs_engine_release(created.engine);
    LOCK(&mutex);
    assert(!instances && !active_ops && !retained_bytes && !state);
    UNLOCK(&mutex);
  }
  assert(hs_engine_create_async("fail", 4, done, &c, &op) == 0);
  assert(wait_for(&c, op).code == HS_ERR_IO);
  assert(hs_engine_create_async("{}", 2, done, &c, &op) == 0);
  hs_event_t e = wait_for(&c, op);
  assert(e.code == 0);
  assert(hs_engine_close_async(e.engine, done, &c, &op) == 0);
  assert(wait_for(&c, op).code == 0);
  hs_engine_release(e.engine);
  printf("ABI seed=%08x concurrent "
         "submit/cancel/close/restart/bootstrap-failure; drained\n",
         seed);
  return 0;
}
