#ifndef HS_PLATFORM_H
#define HS_PLATFORM_H
#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <winsock2.h>
typedef SRWLOCK hs_mutex;
typedef CONDITION_VARIABLE hs_cond;
typedef HANDLE hs_thread;
#define HS_MUTEX_INIT SRWLOCK_INIT
#define HS_COND_INIT CONDITION_VARIABLE_INIT
#define LOCK(m) AcquireSRWLockExclusive(m)
#define UNLOCK(m) ReleaseSRWLockExclusive(m)
#define BROADCAST(c) WakeAllConditionVariable(c)
#define WAIT(c, m) SleepConditionVariableSRW(c, m, INFINITE, 0)
#define THREAD_RESULT DWORD WINAPI
#define THREAD_RETURN return 0
static int hs_thread_start(hs_thread *t, LPTHREAD_START_ROUTINE f, void *p) {
  *t = CreateThread(NULL, 0, f, p, 0, NULL);
  return *t != NULL;
}
static void hs_thread_join(hs_thread t) {
  WaitForSingleObject(t, INFINITE);
  CloseHandle(t);
}
#define HS_LOCAL __declspec(thread)
#else
#include <errno.h>
#include <pthread.h>
#include <unistd.h>
typedef pthread_mutex_t hs_mutex;
typedef pthread_cond_t hs_cond;
typedef pthread_t hs_thread;
#define HS_MUTEX_INIT PTHREAD_MUTEX_INITIALIZER
#define HS_COND_INIT PTHREAD_COND_INITIALIZER
#define LOCK(m) pthread_mutex_lock(m)
#define UNLOCK(m) pthread_mutex_unlock(m)
#define BROADCAST(c) pthread_cond_broadcast(c)
#define WAIT(c, m) pthread_cond_wait(c, m)
#define THREAD_RESULT void *
#define THREAD_RETURN return NULL
static int hs_thread_start(hs_thread *t, void *(*f)(void *), void *p) {
  return pthread_create(t, NULL, f, p) == 0;
}
static void hs_thread_join(hs_thread t) { pthread_join(t, NULL); }
#define HS_LOCAL _Thread_local
#endif
#endif
