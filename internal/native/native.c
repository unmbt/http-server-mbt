/* R-SAFE/R-N15: owned native jobs, rooted opens and stable file leases.
 * Workers never enter MoonBit, including reference counting. */
#define _GNU_SOURCE
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>
#include <stdio.h>
#include <moonbit.h>
#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <winsock2.h>
#include <mswsock.h>
#include <windows.h>
#pragma comment(lib, "ws2_32.lib")
#pragma comment(lib, "mswsock.lib")
typedef HANDLE hs_fd;
typedef SRWLOCK hs_mutex;
typedef CONDITION_VARIABLE hs_cond;
#define LOCK(m) AcquireSRWLockExclusive(m)
#define UNLOCK(m) ReleaseSRWLockExclusive(m)
#define WAKE(c) WakeConditionVariable(c)
#else
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <pthread.h>
#include <sys/stat.h>
#include <sys/socket.h>
#include <dirent.h>
#include <stdio.h>
#ifdef __linux__
#include <sys/syscall.h>
#include <linux/openat2.h>
#include <sys/sendfile.h>
#endif
typedef int hs_fd;
typedef pthread_mutex_t hs_mutex;
typedef pthread_cond_t hs_cond;
#define LOCK(m) pthread_mutex_lock(m)
#define UNLOCK(m) pthread_mutex_unlock(m)
#define WAKE(c) pthread_cond_signal(c)
#endif

typedef struct hs_file {
  hs_fd fd;
  int kind;
  int64_t size, seconds, nanos;
  uint64_t generation;
} hs_file;
typedef struct hs_job hs_job;
typedef struct hs_budget hs_budget;
typedef struct hs_pool {
  hs_mutex mutex;
  hs_cond cond;
  int stopping, count, capacity, worker_limit, active, notified, connection_limit;
  hs_fd notify;
  hs_budget *budget;
  struct hs_pool *budget_next;
  int64_t body_limit, directory_limit, body_owned, directory_owned;
#ifdef _WIN32
  OVERLAPPED notification;
  HANDLE notification_event;
  unsigned char notification_byte;
#else
#endif
} hs_pool;
struct hs_budget {
  hs_mutex mutex;
  hs_cond cond;
  int refs, stopping, queued, active, thread_count, connections;
  int64_t body, directory;
  uint64_t next_id, next_generation;
  hs_pool *pools;
  hs_job *head, *tail;
#ifdef _WIN32
  HANDLE threads[64];
#else
  pthread_t threads[64];
#endif
};
#ifdef _MSC_VER
__declspec(thread) static hs_budget *hs_owner_budget;
#else
static _Thread_local hs_budget *hs_owner_budget;
#endif
struct hs_job {
  hs_job *next;
  hs_pool *pool;
  hs_file *file, *result;
  char *path;
  unsigned char *data;
  char **names;
  int names_count, names_capacity, operation, done, cancelled, code, length;
  int64_t offset, value;
  uintptr_t socket;
  int directory_charge;
  uint64_t id, generation;
#ifdef HS_IO_TESTING
  int test_delay_ms, test_error, test_short;
#endif
};
#ifdef HS_IO_TESTING
/* Test-only fault boundary in the real executor; copied into each accepted job
   on the owner before workers can observe it. Never compiled into products. */
static int hs_test_delay_ms, hs_test_error, hs_test_short;
#endif
MOONBIT_FFI_EXPORT int hs_io_reserve(hs_pool *p,int directory,int bytes);
MOONBIT_FFI_EXPORT void hs_io_release(hs_pool *p,int directory,int bytes);
MOONBIT_FFI_EXPORT void hs_io_pool_free(hs_pool *p);

static void hs_file_free(hs_file *f) {
  if (!f) return;
#ifdef _WIN32
  CloseHandle(f->fd);
#else
  close(f->fd);
#endif
  free(f);
}

#ifdef _WIN32
static wchar_t *hs_wide(const char *s) {
  int n = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, s, -1, NULL, 0);
  if (!n) return NULL;
  wchar_t *w = calloc((size_t)n, sizeof(wchar_t));
  if (w) MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, s, -1, w, n);
  return w;
}
static wchar_t *hs_final_path(HANDLE f) {
  DWORD n = GetFinalPathNameByHandleW(f, NULL, 0, FILE_NAME_NORMALIZED);
  if (!n) return NULL;
  wchar_t *p = calloc((size_t)n + 1, sizeof(wchar_t));
  if (!p) return NULL;
  if (!GetFinalPathNameByHandleW(f, p, n + 1, FILE_NAME_NORMALIZED)) { free(p); return NULL; }
  return p;
}
static int hs_beneath(hs_file *root, hs_file *f) {
  wchar_t *r = hs_final_path(root->fd), *p = hs_final_path(f->fd);
  int ok = 0;
  if (r && p) {
    size_t n = wcslen(r);
    while (n > 4 && (r[n-1] == L'\\' || r[n-1] == L'/')) n--;
    ok = _wcsnicmp(r, p, n) == 0 && (p[n] == 0 || p[n] == L'\\' || p[n] == L'/');
    if (ok) {
      /* A textual prefix alone is insufficient for case-sensitive directories
         and a root component exchanged concurrently with resolution. */
      wchar_t saved=p[n];p[n]=0;
      HANDLE parent=CreateFileW(p,FILE_READ_ATTRIBUTES,
        FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_SHARE_DELETE,NULL,OPEN_EXISTING,
        FILE_FLAG_BACKUP_SEMANTICS,NULL);
      p[n]=saved;
      BY_HANDLE_FILE_INFORMATION a,b;
      ok=parent!=INVALID_HANDLE_VALUE && GetFileInformationByHandle(parent,&a) &&
        GetFileInformationByHandle(root->fd,&b) && a.dwVolumeSerialNumber==b.dwVolumeSerialNumber &&
        a.nFileIndexHigh==b.nFileIndexHigh && a.nFileIndexLow==b.nFileIndexLow;
      if(parent!=INVALID_HANDLE_VALUE)CloseHandle(parent);
    }
  }
  free(r); free(p); return ok;
}
static int hs_stat(hs_file *f, int save) {
  BY_HANDLE_FILE_INFORMATION s;
  if (!GetFileInformationByHandle(f->fd, &s)) return -4;
  int64_t size = ((int64_t)s.nFileSizeHigh << 32) | s.nFileSizeLow;
  uint64_t ticks = ((uint64_t)s.ftLastWriteTime.dwHighDateTime << 32) | s.ftLastWriteTime.dwLowDateTime;
  int64_t sec = (int64_t)(ticks / 10000000) - 11644473600LL;
  int64_t ns = (int64_t)(ticks % 10000000) * 100;
  if (save) { f->size = size; f->seconds = sec; f->nanos = ns; f->kind = (s.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) ? 2 : 1; return 0; }
  return size == f->size && sec == f->seconds && ns == f->nanos ? 0 : -3;
}
#else
static int hs_fd_path(int fd, char *buf) {
#ifdef __APPLE__
  return fcntl(fd, F_GETPATH, buf) == 0;
#else
  char link[64]; snprintf(link, sizeof(link), "/proc/self/fd/%d", fd);
  ssize_t n = readlink(link, buf, PATH_MAX - 1);
  if (n < 0) return 0;
  buf[n] = 0; return 1;
#endif
}
static int hs_beneath(hs_file *root, hs_file *f) {
  char r[PATH_MAX], p[PATH_MAX];
  if (!hs_fd_path(root->fd, r) || !hs_fd_path(f->fd, p)) return 0;
  size_t n = strlen(r);
  while (n > 1 && r[n-1] == '/') n--;
  return strncmp(r,p,n) == 0 && (n == 1 || p[n] == 0 || p[n] == '/');
}
static int hs_stat(hs_file *f, int save) {
  struct stat s;
  if (fstat(f->fd, &s)) return -4;
#ifdef __APPLE__
  int64_t sec = s.st_mtimespec.tv_sec, ns = s.st_mtimespec.tv_nsec;
#else
  int64_t sec = s.st_mtim.tv_sec, ns = s.st_mtim.tv_nsec;
#endif
  if (save) { f->size = s.st_size; f->seconds = sec; f->nanos = ns; f->kind = S_ISDIR(s.st_mode) ? 2 : S_ISREG(s.st_mode) ? 1 : 0; return 0; }
  return s.st_size == f->size && sec == f->seconds && ns == f->nanos ? 0 : -3;
}
#endif

#ifndef _WIN32
/* Portable openat2 fallback: never follow an unchecked component. Symlinks
   expand back into the bounded component queue and cannot pop above root. */
static int hs_open_components(hs_file *root,const char *relative) {
  char todo[PATH_MAX], link[PATH_MAX], next[PATH_MAX], root_path[PATH_MAX];
  int dirs[256], depth=0, links=0, result=-1;
  if(strlen(relative)>=sizeof(todo)){errno=ENAMETOOLONG;return -1;}
  strcpy(todo,relative[0]?relative:".");dirs[0]=root->fd;
  while(todo[0]) {
    char *rest=strchr(todo,'/');
    if(rest){*rest++=0;while(*rest=='/')rest++;} else rest=todo+strlen(todo);
    if(!strcmp(todo,".")) {memmove(todo,rest,strlen(rest)+1);continue;}
    if(!strcmp(todo,"..")) {
      if(depth==0){errno=EPERM;goto done;}
      close(dirs[depth--]);memmove(todo,rest,strlen(rest)+1);continue;
    }
    struct stat s;
    if(fstatat(dirs[depth],todo,&s,AT_SYMLINK_NOFOLLOW))goto done;
    if(S_ISLNK(s.st_mode)) {
      if(++links>40){errno=ELOOP;goto done;}
      ssize_t n=readlinkat(dirs[depth],todo,link,sizeof(link)-1);
      if(n<0)goto done;
      if(n==(ssize_t)sizeof(link)-1){errno=ENAMETOOLONG;goto done;}
      link[n]=0;
      char *target=link;
      if(link[0]=='/') {
        if(!hs_fd_path(root->fd,root_path)){errno=EPERM;goto done;}
        size_t base=strlen(root_path);
        while(base>1 && root_path[base-1]=='/')base--;
        if(strncmp(link,root_path,base) || (base>1 && link[base] && link[base]!='/')){errno=EPERM;goto done;}
        target=link+base;while(*target=='/')target++;
        while(depth>0)close(dirs[depth--]);
      }
      int count=snprintf(next,sizeof(next),"%s%s%s",target,*rest?"/":"",rest);
      if(count<0 || count>=(int)sizeof(next)){errno=ENAMETOOLONG;goto done;}
      strcpy(todo,next);continue;
    }
    int fd=openat(dirs[depth],todo,O_RDONLY|O_CLOEXEC|O_NONBLOCK|O_NOFOLLOW|(*rest?O_DIRECTORY:0));
    if(fd<0)goto done;
    if(!*rest){result=fd;goto done;}
    if(depth==255){close(fd);errno=ELOOP;goto done;}
    dirs[++depth]=fd;memmove(todo,rest,strlen(rest)+1);
  }
  result=openat(dirs[depth],".",O_RDONLY|O_CLOEXEC|O_DIRECTORY|O_NOFOLLOW);
done:;
  int error=errno;
  while(depth>0)close(dirs[depth--]);
  errno=error;return result;
}
#endif

static int hs_open(hs_job *j) {
  hs_file *f = calloc(1, sizeof(*f));
  if (!f) return -7;
#ifdef _WIN32
  wchar_t *name = hs_wide(j->path), *base = NULL, *joined = NULL;
  if (!name) { free(f); return -5; }
  /* Extended Windows paths do not normalize forward or repeated separators. */
  size_t dst = 0;
  for (size_t src = 0; name[src]; src++) {
    wchar_t c = name[src] == L'/' ? L'\\' : name[src];
    if (j->file && c == L'\\' && dst && name[dst-1] == L'\\') continue;
    name[dst++] = c;
  }
  name[dst] = 0;
  if (j->file) {
    base = hs_final_path(j->file->fd);
    if (base) {
      size_t n = wcslen(base) + wcslen(name) + 2;
      joined = calloc(n, sizeof(wchar_t));
      if (joined) {
        size_t base_len=wcslen(base), name_len=wcslen(name);
        memcpy(joined,base,base_len*sizeof(wchar_t));
        if(name_len) {joined[base_len++]=L'\\';memcpy(joined+base_len,name,(name_len+1)*sizeof(wchar_t));}
        size_t used=wcslen(joined);
        while(used>7 && (joined[used-1]==L'/' || joined[used-1]==L'\\')) joined[--used]=0;
      }
    }
    if (!joined) { free(name); free(base); free(f); return -5; }
  }
  f->fd = CreateFileW(joined ? joined : name, GENERIC_READ,
      FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, NULL, OPEN_EXISTING,
      FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OVERLAPPED, NULL);
  DWORD err = GetLastError();
  free(name); free(base); free(joined);
  if (f->fd == INVALID_HANDLE_VALUE) {
    free(f);
    return err == ERROR_FILE_NOT_FOUND || err == ERROR_PATH_NOT_FOUND || err == ERROR_DIRECTORY ? -6 : err == ERROR_ACCESS_DENIED || err == ERROR_CANT_RESOLVE_FILENAME ? -5 : -4;
  }
#else
  f->fd = -1;
  if (j->file) {
#ifdef __linux__
    struct open_how how = {0};
    how.flags = O_RDONLY | O_CLOEXEC | O_NONBLOCK;
    how.resolve = RESOLVE_BENEATH | RESOLVE_NO_MAGICLINKS;
    f->fd = (int)syscall(SYS_openat2, j->file->fd, j->path[0] ? j->path : ".", &how, sizeof(how));
    /* Absolute in-root symlinks are supported by opening then validating the
       final handle. No data or metadata is exposed before that validation. */
    if (f->fd < 0 && (errno == ENOSYS || errno == EINVAL || errno == EXDEV))
#endif
      f->fd = hs_open_components(j->file, j->path);
  } else f->fd = open(j->path, O_RDONLY | O_CLOEXEC | O_NONBLOCK | O_DIRECTORY);
  if (f->fd < 0) {
    int e = errno; free(f);
    return e == ENOENT || e == ENOTDIR ? -6 : e == EACCES || e == EPERM || e == ELOOP || e == EXDEV ? -5 : -4;
  }
#endif
  if (j->file && !hs_beneath(j->file, f)) { hs_file_free(f); return -5; }
  int code = hs_stat(f, 1);
  if (code || !f->kind || (!j->file && f->kind != 2)) { hs_file_free(f); return code ? code : -5; }
  j->result = f; return 0;
}

static int hs_read(hs_job *j) {
  int code = hs_stat(j->file, 0);
  if (code) return code;
  if (j->offset < 0 || j->length < 0 || j->offset > j->file->size || j->length > j->file->size - j->offset) return -3;
  j->data = malloc((size_t)j->length + 1);
  if (!j->data) return -7;
  int n = 0;
  while (n < j->length) {
    LOCK(&j->pool->mutex);int cancelled=j->cancelled;UNLOCK(&j->pool->mutex);
    if(cancelled)return -9;
    int request=j->length-n;
#ifdef HS_IO_TESTING
    if(j->test_short>0 && request>j->test_short)request=j->test_short;
#endif
#ifdef _WIN32
    OVERLAPPED ov = {0};
    int64_t pos = j->offset + n;
    ov.Offset = (DWORD)pos; ov.OffsetHigh = (DWORD)((uint64_t)pos >> 32);
    ov.hEvent = CreateEventW(NULL, TRUE, FALSE, NULL);
    if (!ov.hEvent) return -4;
    DWORD got = 0;
    BOOL ok = ReadFile(j->file->fd, j->data+n, request, &got, &ov);
    if (!ok && GetLastError() == ERROR_IO_PENDING) {
      while(WaitForSingleObject(ov.hEvent,10)==WAIT_TIMEOUT) {
        LOCK(&j->pool->mutex);cancelled=j->cancelled;UNLOCK(&j->pool->mutex);
        if(cancelled)CancelIoEx(j->file->fd,&ov);
      }
      ok=GetOverlappedResult(j->file->fd,&ov,&got,TRUE);
    }
    CloseHandle(ov.hEvent);
    if (!ok) return -4;
    int count = (int)got;
#else
    ssize_t count = pread(j->file->fd, j->data+n, (size_t)request, (off_t)(j->offset+n));
    if (count < 0 && errno == EINTR) continue;
    if (count < 0) return -4;
#endif
    if (!count) return -3;
    n += (int)count;
  }
  j->value = n;
  return hs_stat(j->file, 0);
}

static int hs_add_name(hs_job *j, const char *name, int64_t *used) {
  if (!strcmp(name,".") || !strcmp(name,"..")) return 0;
  size_t n = strlen(name) + 1;
  *used += (int64_t)n + 64;
  if (*used > j->offset || j->names_count == INT_MAX) return -7;
  /* Covers native names, UTF-16 decoding, entry/map/sort storage and row text. */
  /* UTF-16 names, sort/maps, escaped UTF-16 + UTF-8 HTML row coexist. */
  int64_t charge=(int64_t)n*32+2048;
  if(charge>INT_MAX-j->directory_charge || !hs_io_reserve(j->pool,1,(int)charge)) return -7;
  j->directory_charge+=(int)charge;
  if (j->names_count == j->names_capacity) {
    int capacity = j->names_capacity ? j->names_capacity * 2 : 64;
    if (capacity < j->names_capacity) return -7;
    char **names = realloc(j->names, (size_t)capacity*sizeof(char*));
    if (!names) return -7;
    j->names = names; j->names_capacity = capacity;
  }
  char *copy = malloc(n);
  if (!copy) return -7;
  memcpy(copy,name,n); j->names[j->names_count++] = copy; return 0;
}
static int hs_list(hs_job *j) {
  int64_t used = 0;
  if (j->file->kind != 2) return -6;
  if(!hs_io_reserve(j->pool,1,65536))return -7;
  j->directory_charge+=65536;
#ifdef _WIN32
  /* Enumeration is bound to the open directory, not a path reopened by FindFirstFile. */
  unsigned char *buffer = malloc(65536);
  if (!buffer) return -7;
  int first = 1, result = 0;
  for (;;) {
    FILE_INFO_BY_HANDLE_CLASS cls = first ? FileIdBothDirectoryRestartInfo : FileIdBothDirectoryInfo;
    first = 0;
    if (!GetFileInformationByHandleEx(j->file->fd, cls, buffer, 65536)) {
      result = GetLastError() == ERROR_NO_MORE_FILES ? 0 : -4; break;
    }
    FILE_ID_BOTH_DIR_INFO *entry = (FILE_ID_BOTH_DIR_INFO*)buffer;
    for (;;) {
      int bytes = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, entry->FileName, entry->FileNameLength/2, NULL, 0, NULL, NULL);
      char *name = malloc((size_t)bytes+1);
      if (!name || !bytes) { free(name); result=-4; break; }
      WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, entry->FileName, entry->FileNameLength/2, name, bytes, NULL, NULL);
      name[bytes]=0; result=hs_add_name(j,name,&used); free(name);
      if (result || !entry->NextEntryOffset) break;
      entry=(FILE_ID_BOTH_DIR_INFO*)((unsigned char*)entry+entry->NextEntryOffset);
    }
    if (result) break;
  }
  free(buffer); return result;
#else
  int fd = openat(j->file->fd, ".", O_RDONLY|O_CLOEXEC|O_DIRECTORY);
  if (fd < 0) return -4;
  DIR *d = fdopendir(fd);
  if (!d) {close(fd); return -4;}
  int result=0; struct dirent *e;
  errno=0;
  while ((e=readdir(d))) { if ((result=hs_add_name(j,e->d_name,&used))) break; errno=0; }
  if (!result && errno) result=-4;
  closedir(d); return result;
#endif
}

static int hs_send(hs_job *j) {
  int code=hs_stat(j->file,0);
  if (code) return code;
  if (j->offset < 0 || j->length < 0 || j->offset > j->file->size || j->length > j->file->size-j->offset) return -3;
  /* TransmitFile length zero means "whole file", not an empty region. */
  if (!j->length) { j->value=0;return 0; }
#ifdef _WIN32
  OVERLAPPED ov={0}; ov.Offset=(DWORD)j->offset; ov.OffsetHigh=(DWORD)((uint64_t)j->offset>>32);
  HANDLE event=CreateEventW(NULL,TRUE,FALSE,NULL); if (!event) return -4;
  ov.hEvent=(HANDLE)((uintptr_t)event|1);
  BOOL ok=TransmitFile((SOCKET)j->socket,j->file->fd,(DWORD)j->length,0,&ov,NULL,0);
  DWORD sent=0;
  if (!ok && WSAGetLastError()==WSA_IO_PENDING) {
    for (;;) {
      DWORD wait=WaitForSingleObject(event,10);
      LOCK(&j->pool->mutex); int cancelled=j->cancelled; UNLOCK(&j->pool->mutex);
      if (cancelled) CancelIoEx((HANDLE)j->socket,&ov);
      if (wait==WAIT_OBJECT_0) break;
    }
    ok=GetOverlappedResult((HANDLE)j->socket,&ov,&sent,TRUE);
  } else if (ok) GetOverlappedResult((HANDLE)j->socket,&ov,&sent,TRUE);
  CloseHandle(event);
  if (!ok) return -4;
  j->value=sent ? sent : j->length;
#elif defined(__linux__)
  off_t off=(off_t)j->offset;
  ssize_t n=sendfile((int)j->socket,j->file->fd,&off,(size_t)j->length);
  if (n<0) {if (errno==EAGAIN || errno==EINTR) {j->value=0; return 0;} return errno==EINVAL || errno==ENOSYS || errno==EOPNOTSUPP ? -8 : -4;}
  j->value=n;
#elif defined(__APPLE__)
  off_t count=j->length;
  int ret=sendfile(j->file->fd,(int)j->socket,(off_t)j->offset,&count,NULL,0);
  j->value=count;
  if (ret<0 && !count && errno!=EAGAIN && errno!=EINTR) return errno==EINVAL || errno==ENOTSUP ? -8 : -4;
#else
  return -8;
#endif
  if (!j->value && j->length && hs_stat(j->file,0)) return -3;
  return hs_stat(j->file,0);
}

static void hs_notify(hs_pool *p) {
  LOCK(&p->mutex);
  if (p->notified) { UNLOCK(&p->mutex); return; }
  p->notified = 1;
  UNLOCK(&p->mutex);
  unsigned char byte=1;
#ifdef _WIN32
  /* A zero-buffer named pipe write can remain pending until the owner reads.
     Workers must never wait for it: the owner may already have seen done. */
  ResetEvent(p->notification_event);
  DWORD wrote=0;
  WriteFile(p->notify,&p->notification_byte,1,&wrote,&p->notification);
#else
  ssize_t n; do {n=write(p->notify,&byte,1);} while(n<0 && errno==EINTR);
#endif
}
static void hs_wait(hs_cond *cond, hs_mutex *mutex) {
#ifdef _WIN32
  SleepConditionVariableSRW(cond,mutex,INFINITE,0);
#else
  pthread_cond_wait(cond,mutex);
#endif
}
static void hs_wake_all(hs_cond *cond) {
#ifdef _WIN32
  WakeAllConditionVariable(cond);
#else
  pthread_cond_broadcast(cond);
#endif
}
static int hs_worker_limit(hs_budget *b) {
  int limit=64;
  for(hs_pool *p=b->pools;p;p=p->budget_next)
    if(p->worker_limit<limit)limit=p->worker_limit;
  return limit;
}
#ifdef _WIN32
static DWORD WINAPI hs_worker(void *arg) {
#else
static void *hs_worker(void *arg) {
#endif
  hs_budget *b=arg;
  for (;;) {
    LOCK(&b->mutex);
    while ((!b->head || b->active>=hs_worker_limit(b)) && !b->stopping)
      hs_wait(&b->cond,&b->mutex);
    if (!b->head && b->stopping) {UNLOCK(&b->mutex);break;}
    hs_job *j=b->head; hs_pool *p=j->pool;
    b->head=j->next;if(!b->head)b->tail=NULL;
    b->queued--;p->count--;b->active++;p->active++;
    UNLOCK(&b->mutex);
#ifdef HS_IO_TESTING
    if(j->test_delay_ms) {
#ifdef _WIN32
      Sleep(j->test_delay_ms);
#else
      usleep((useconds_t)j->test_delay_ms*1000);
#endif
    }
#endif
    LOCK(&p->mutex);int cancelled=j->cancelled;UNLOCK(&p->mutex);
    int code=-9;
    if(!cancelled) {
#ifdef HS_IO_TESTING
      if(j->test_error)code=j->test_error;else
#endif
      switch(j->operation) {
        case 0:code=hs_open(j);break;
        case 1:code=hs_read(j);break;
        case 2:code=hs_stat(j->file,0);break;
        case 3:code=hs_list(j);break;
        case 4:code=hs_send(j);break;
      }
    }
    LOCK(&p->mutex);
    if(j->result)j->result->generation=j->id;
    j->code=j->cancelled?-9:code;j->done=1;
    UNLOCK(&p->mutex);
    /* Do not touch j after publishing done; the owner may already free it.
       p remains alive until its active count reaches zero after notification. */
    hs_notify(p);
    LOCK(&b->mutex);p->active--;b->active--;hs_wake_all(&b->cond);UNLOCK(&b->mutex);
  }
  return 0;
}
MOONBIT_FFI_EXPORT hs_pool *hs_io_pool_new(int count,int capacity,hs_fd notify,int body_limit,int directory_limit) {
  if(count<1 || count>64 || capacity<1)return NULL;
  hs_pool *p=calloc(1,sizeof(*p));if(!p)return NULL;
#ifdef _WIN32
  InitializeSRWLock(&p->mutex);
  p->notification_event=CreateEventW(NULL,TRUE,FALSE,NULL);
  if(!p->notification_event){free(p);return NULL;}
  p->notification.hEvent=(HANDLE)((uintptr_t)p->notification_event|1);
  p->notification_byte=1;
#else
  pthread_mutex_init(&p->mutex,NULL);
#endif
  hs_budget *b=hs_owner_budget;
  if(!b) {
    b=calloc(1,sizeof(*b));
    if(!b) {
#ifdef _WIN32
      CloseHandle(p->notification_event);
#else
      pthread_mutex_destroy(&p->mutex);
#endif
      free(p);return NULL;
    }
#ifdef _WIN32
    InitializeSRWLock(&b->mutex);InitializeConditionVariable(&b->cond);
#else
    pthread_mutex_init(&b->mutex,NULL);pthread_cond_init(&b->cond,NULL);
#endif
    hs_owner_budget=b;
  }
  p->budget=b;p->capacity=capacity;p->worker_limit=count;p->notify=notify;
  p->body_limit=body_limit;p->directory_limit=directory_limit;p->connection_limit=1024;
  LOCK(&b->mutex);
  p->budget_next=b->pools;b->pools=p;b->refs++;
  /* One executor per owner; capacity never scales with instance count.
     Workers above the minimum live limit remain asleep for later reuse. */
  while(b->thread_count<count) {
    int i=b->thread_count;
#ifdef _WIN32
    b->threads[i]=CreateThread(NULL,0,hs_worker,b,0,NULL);
    if(!b->threads[i])break;
#else
    if(pthread_create(&b->threads[i],NULL,hs_worker,b))break;
#endif
    b->thread_count++;
  }
  int ok=b->thread_count>=count;
  UNLOCK(&b->mutex);
  if(!ok){hs_io_pool_free(p);return NULL;}
  return p;
}
MOONBIT_FFI_EXPORT void hs_io_pool_free(hs_pool *p) {
  if(!p)return;
  hs_budget *b=p->budget;
  LOCK(&b->mutex);p->stopping=1;
  while(p->count || p->active)hs_wait(&b->cond,&b->mutex);
  b->body-=p->body_owned;b->directory-=p->directory_owned;
  hs_pool **entry=&b->pools;
  while(*entry && *entry!=p)entry=&(*entry)->budget_next;
  if(*entry)*entry=p->budget_next;
  int last=--b->refs==0;
  if(last)b->stopping=1;
  hs_wake_all(&b->cond);UNLOCK(&b->mutex);
  if(last) {
    for(int i=0;i<b->thread_count;i++) {
#ifdef _WIN32
      WaitForSingleObject(b->threads[i],INFINITE);CloseHandle(b->threads[i]);
#else
      pthread_join(b->threads[i],NULL);
#endif
    }
#ifndef _WIN32
    pthread_mutex_destroy(&b->mutex);pthread_cond_destroy(&b->cond);
#endif
    hs_owner_budget=NULL;free(b);
  }
#ifdef _WIN32
  if(p->notified){DWORD wrote;CancelIoEx(p->notify,&p->notification);GetOverlappedResult(p->notify,&p->notification,&wrote,TRUE);}
  CloseHandle(p->notification_event);
#else
  pthread_mutex_destroy(&p->mutex);
#endif
  free(p);
}
/* Shared credits; directory workers also acquire these under the mutex. */
MOONBIT_FFI_EXPORT int hs_io_reserve(hs_pool *p,int directory,int bytes) {
  hs_budget *b=p->budget;
  LOCK(&b->mutex);
  int64_t limit=INT64_MAX;
  for(hs_pool *q=b->pools;q;q=q->budget_next) {
    int64_t n=directory?q->directory_limit:q->body_limit;
    if(n<limit)limit=n;
  }
  int64_t *used=directory?&b->directory:&b->body;
  if(bytes<0 || *used>limit-bytes) {UNLOCK(&b->mutex);return 0;}
  *used+=bytes;
  if(directory)p->directory_owned+=bytes;else p->body_owned+=bytes;
  UNLOCK(&b->mutex);return 1;
}
MOONBIT_FFI_EXPORT void hs_io_release(hs_pool *p,int directory,int bytes) {
  int64_t *used=directory?&p->budget->directory:&p->budget->body;
  LOCK(&p->budget->mutex);
  int64_t *owned=directory?&p->directory_owned:&p->body_owned;
  if(bytes>=0 && *owned>=bytes){*used-=bytes;*owned-=bytes;}
  UNLOCK(&p->budget->mutex);
}
/* These entry points are called only by the current MoonBit owner thread. */
MOONBIT_FFI_EXPORT void hs_io_connection_limit(hs_pool *p,int limit) {
  LOCK(&p->budget->mutex);p->connection_limit=limit;UNLOCK(&p->budget->mutex);
}
MOONBIT_FFI_EXPORT int hs_io_connection_acquire(void) {
  hs_budget *b=hs_owner_budget;if(!b)return 0;
  LOCK(&b->mutex);int limit=INT_MAX;
  for(hs_pool *p=b->pools;p;p=p->budget_next)if(p->connection_limit<limit)limit=p->connection_limit;
  int ok=b->connections<limit;if(ok)b->connections++;
  UNLOCK(&b->mutex);return ok;
}
MOONBIT_FFI_EXPORT void hs_io_connection_release(void) {
  hs_budget *b=hs_owner_budget;if(!b)return;
  LOCK(&b->mutex);if(b->connections>0)b->connections--;UNLOCK(&b->mutex);
}
MOONBIT_FFI_EXPORT int hs_io_body_acquire(int bytes) {
  hs_budget *b=hs_owner_budget;if(!b || bytes<0)return 0;
  LOCK(&b->mutex);int64_t limit=INT64_MAX;
  for(hs_pool *p=b->pools;p;p=p->budget_next)if(p->body_limit<limit)limit=p->body_limit;
  int ok=b->body<=limit-bytes;if(ok)b->body+=bytes;
  UNLOCK(&b->mutex);return ok;
}
MOONBIT_FFI_EXPORT void hs_io_body_release(int bytes) {
  hs_budget *b=hs_owner_budget;if(!b)return;
  LOCK(&b->mutex);if(bytes>=0 && b->body>=bytes)b->body-=bytes;UNLOCK(&b->mutex);
}
MOONBIT_FFI_EXPORT int hs_io_shutdown_write(uintptr_t socket) {
#ifdef _WIN32
  return shutdown((SOCKET)socket,SD_SEND)==0;
#else
  return shutdown((int)socket,SHUT_WR)==0;
#endif
}
MOONBIT_FFI_EXPORT hs_job *hs_io_submit(hs_pool *p,int operation,hs_file *file,const char *path,int64_t offset,int length,uintptr_t sock) {
  hs_job *j=calloc(1,sizeof(*j)); if(!j)return NULL;
  size_t n=strlen(path)+1; j->path=malloc(n);
  if(!j->path){free(j);return NULL;} memcpy(j->path,path,n);
  j->pool=p;j->operation=operation;j->file=file;j->offset=offset;j->length=length;j->socket=sock;
  hs_budget *b=p->budget;
  LOCK(&b->mutex);
  int limit=INT_MAX;
  for(hs_pool *q=b->pools;q;q=q->budget_next)if(q->capacity<limit)limit=q->capacity;
  if(p->stopping || b->queued>=limit){UNLOCK(&b->mutex);free(j->path);free(j);return NULL;}
  j->id=++b->next_id;j->generation=file?file->generation:0;
#ifdef HS_IO_TESTING
  j->test_delay_ms=hs_test_delay_ms;j->test_error=hs_test_error;j->test_short=hs_test_short;
#endif
  if(b->tail)b->tail->next=j;else b->head=j;b->tail=j;b->queued++;p->count++;
  WAKE(&b->cond);UNLOCK(&b->mutex);
  return j;
}
MOONBIT_FFI_EXPORT int hs_io_null(void *p){return p==NULL;}
MOONBIT_FFI_EXPORT void hs_io_ack(hs_pool *p){
  LOCK(&p->mutex);
#ifdef _WIN32
  DWORD wrote;
  GetOverlappedResult(p->notify,&p->notification,&wrote,TRUE);
#endif
  p->notified=0;UNLOCK(&p->mutex);
}
MOONBIT_FFI_EXPORT int hs_io_done(hs_job *j){LOCK(&j->pool->mutex);int d=j->done;UNLOCK(&j->pool->mutex);return d;}
MOONBIT_FFI_EXPORT void hs_io_cancel(hs_job *j){LOCK(&j->pool->mutex);j->cancelled=1;UNLOCK(&j->pool->mutex);}
MOONBIT_FFI_EXPORT int hs_io_code(hs_job *j){return j->code;}
MOONBIT_FFI_EXPORT int64_t hs_io_value(hs_job *j){return j->value;}
MOONBIT_FFI_EXPORT hs_file *hs_io_take_file(hs_job *j){hs_file*f=j->result;j->result=NULL;return f;}
MOONBIT_FFI_EXPORT moonbit_bytes_t hs_io_bytes(hs_job*j){int n=(int)j->value;moonbit_bytes_t b=moonbit_make_bytes(n,0);if(n)memcpy(b,j->data,(size_t)n);return b;}
MOONBIT_FFI_EXPORT int hs_io_names_count(hs_job*j){return j->names_count;}
MOONBIT_FFI_EXPORT int hs_io_take_directory_charge(hs_job*j){int n=j->directory_charge;j->directory_charge=0;return n;}
MOONBIT_FFI_EXPORT moonbit_bytes_t hs_io_name(hs_job*j,int i){int n=(int)strlen(j->names[i]);moonbit_bytes_t b=moonbit_make_bytes(n,0);memcpy(b,j->names[i],(size_t)n);return b;}
MOONBIT_FFI_EXPORT void hs_io_job_free(hs_job*j){if(!j)return;hs_io_release(j->pool,1,j->directory_charge);hs_file_free(j->result);for(int i=0;i<j->names_count;i++)free(j->names[i]);free(j->names);free(j->path);free(j->data);free(j);}
MOONBIT_FFI_EXPORT void hs_io_file_free(hs_file*f){hs_file_free(f);}
MOONBIT_FFI_EXPORT int hs_io_file_kind(hs_file*f){return f->kind;}
MOONBIT_FFI_EXPORT int64_t hs_io_file_size(hs_file*f){return f->size;}
MOONBIT_FFI_EXPORT int64_t hs_io_file_time(hs_file*f){return f->seconds;}
MOONBIT_FFI_EXPORT void *hs_io_no_file(void){return NULL;}
MOONBIT_FFI_EXPORT uint32_t hs_io_process_handles(void) {
#ifdef _WIN32
  DWORD count=0;if(!GetProcessHandleCount(GetCurrentProcess(),&count))return 0;return count;
#else
  DIR *dir=opendir(
#ifdef __APPLE__
    "/dev/fd"
#else
    "/proc/self/fd"
#endif
  );
  if(!dir)return 0;
  uint32_t count=0;struct dirent *entry;
  while((entry=readdir(dir)))if(entry->d_name[0]!='.')count++;
  closedir(dir);return count;
#endif
}
