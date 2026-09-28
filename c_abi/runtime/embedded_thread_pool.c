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
