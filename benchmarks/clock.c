#include <stdint.h>
#include <moonbit.h>
#ifdef _WIN32
#include <windows.h>
#else
#include <time.h>
#endif

MOONBIT_FFI_EXPORT int64_t hs_benchmark_monotonic_ns(void) {
#ifdef _WIN32
  static LARGE_INTEGER frequency;
  static int initialized;
  if (!initialized) {
    QueryPerformanceFrequency(&frequency);
    initialized = 1;
  }
  LARGE_INTEGER now;
  QueryPerformanceCounter(&now);
  return (int64_t)((now.QuadPart * 1000000000LL) / frequency.QuadPart);
#else
  struct timespec now;
  if (clock_gettime(CLOCK_MONOTONIC, &now) != 0) return 0;
  return (int64_t)now.tv_sec * 1000000000LL + now.tv_nsec;
#endif
}
