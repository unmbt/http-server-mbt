/* ABI-only policy around pinned async 0.21.3's thread pool. Keep its job and
 * join protocol, but never install process-wide SIGPIPE/SIGUSR2 dispositions.
 * Cancellation of a POSIX blocking job drains its normal completion instead
 * of interrupting it with a host-owned signal. The static engine's file pool
 * is separate and retains its own bounded cancellation protocol. */
#ifndef _WIN32
#include <pthread.h>
#include <signal.h>
static int hs_embedded_worker_signal(pthread_t thread, int signal_number) {
  if (signal_number == SIGUSR2)
    return 0;
  /* SIGUSR1 is consumed only by this library's private worker sigwait. */
  return pthread_kill(thread, signal_number);
}
#define signal(number, handler) ((void)(number), (void)(handler), SIG_DFL)
#define sigaction(number, action, previous)                                    \
  ((void)(number), (void)(action), (void)(previous), 0)
#define pthread_kill(thread, number) hs_embedded_worker_signal(thread, number)
#endif
#include "../../.mooncakes/moonbitlang/async/src/internal/event_loop/thread_pool.c"

/* Forwarding bridges for runtime symbols expected by compiler-generated
 * objects (e.g. fs.c) under MoonBit toolchain 0.10.16+. */
MOONBIT_FFI_EXPORT
void *moonbit_rt_make_job(int32_t size, void (*free)(void *),
                          int32_t (*worker)(void *, int32_t *),
                          int32_t (*cancel_handler)(void *)) {
  return moonbitlang_async_make_job(size, free, worker, cancel_handler);
}

MOONBIT_FFI_EXPORT
void moonbit_rt_leave_cancellable_region(struct worker *worker) {
  moonbitlang_async_leave_cancellable_region(worker);
}

MOONBIT_FFI_EXPORT
int32_t moonbit_rt_enter_cancellable_region(struct worker *worker) {
  return moonbitlang_async_enter_cancellable_region(worker);
}

MOONBIT_FFI_EXPORT
void moonbit_rt_notify_event_loop(int32_t data) {
  moonbitlang_async_notify_event_loop(data);
}

MOONBIT_FFI_EXPORT
struct worker *moonbit_rt_get_current_worker(void) {
  return moonbitlang_async_get_current_worker();
}

MOONBIT_FFI_EXPORT
int32_t moonbit_rt_get_platform(void) {
  return moonbitlang_async_get_platform();
}

MOONBIT_FFI_EXPORT
void moonbit_rt_free_job(void *payload_ptr) {
  moonbitlang_async_free_job(payload_ptr);
}

MOONBIT_FFI_EXPORT
int32_t moonbit_rt_job_get_ret(void *job) {
  return moonbitlang_async_job_get_ret(job);
}

MOONBIT_FFI_EXPORT
int32_t moonbit_rt_job_get_err(void *job) {
  return moonbitlang_async_job_get_err(job);
}

MOONBIT_FFI_EXPORT
void moonbit_rt_wake_worker(struct worker *worker, struct job *job) {
  moonbitlang_async_wake_worker(worker, job);
}

MOONBIT_FFI_EXPORT
void moonbit_rt_worker_enter_idle(struct worker *worker) {
  moonbitlang_async_worker_enter_idle(worker);
}

MOONBIT_FFI_EXPORT
int32_t moonbit_rt_cancel_worker(struct worker *worker) {
  return moonbitlang_async_cancel_worker(worker);
}

MOONBIT_FFI_EXPORT
int32_t moonbit_rt_worker_check_cancellation_retry(struct worker *worker) {
  return moonbitlang_async_worker_check_cancellation_retry(worker);
}

MOONBIT_FFI_EXPORT
void moonbit_rt_free_worker(struct worker *worker) {
  moonbitlang_async_free_worker(worker);
}

MOONBIT_FFI_EXPORT
void moonbit_rt_destroy_thread_pool(void) {
  moonbitlang_async_destroy_thread_pool();
}

MOONBIT_FFI_EXPORT
int32_t moonbit_rt_fetch_completion(int notify_recv, int32_t *output) {
  return moonbitlang_async_fetch_completion(notify_recv, output);
}
