/* C ABI-only substitute for async@0.21.3 signal.c. The host owns signals.
 * These symbols are hidden by the ABI export whitelist. CLI builds continue
 * to use the unmodified upstream object. No managed pointers are retained. */
#include <stdint.h>
int moonbitlang_async_get_signal_by_index(int32_t code) {
  (void)code;
  return -1;
}
void moonbitlang_async_set_global_cancellation_signals(int32_t *a, int32_t n,
                                                       int32_t *b, int32_t m) {
  (void)a;
  (void)n;
  (void)b;
  (void)m;
}
int moonbitlang_async_set_console_control_handler(int32_t add) {
  (void)add;
  return 1;
}
void moonbitlang_async_start_signal_handler(void) {}
void moonbitlang_async_terminate_signal_handler(void) {}
void moonbitlang_async_terminate_process_by_signal(int32_t signal) {
  (void)signal;
}
