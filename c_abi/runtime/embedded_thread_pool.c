/* ABI-only policy around async 0.22.7's thread pool. Keep its job and
 * join protocol, but never install process-wide SIGPIPE/SIGUSR2 dispositions.
 * Cancellation of a POSIX blocking job drains its normal completion instead
 * of interrupting it with a host-owned signal. The static engine's file pool
 * is separate and retains its own bounded cancellation protocol. */
#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#include <errno.h>
#ifdef _WIN32
#include <windows.h>
#endif

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
/* async 0.22.7 delegates the native worker implementation to the Moon
 * toolchain runtime. The build supplies $MOON_HOME/lib as an include path;
 * keeping this wrapper around the runtime source preserves the ABI's private
 * signal policy while exporting the moonbit_rt_* symbols expected by async. */
#include <runtime/thread_pool.c>

/* This small async stub remains a package-level symbol in 0.22.7 even
 * though the worker implementation moved into the toolchain runtime. */
MOONBIT_FFI_EXPORT
int32_t moonbitlang_async_errno_is_cancelled(int32_t err) {
#ifdef _WIN32
  return err == ERROR_OPERATION_ABORTED;
#else
  return err == EINTR;
#endif
}
