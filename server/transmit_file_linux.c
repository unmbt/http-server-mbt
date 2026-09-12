/*
 * Linux sendfile zero-copy file transfer backend for the server package.
 *
 * Symbol ownership is complementary with transmit_file_windows.c and
 * transmit_file_darwin.c: the native-stub list compiles every stub file on
 * every platform, so each platform must define http_server_tf_* exactly once.
 *   - _WIN32: symbols come from transmit_file_windows.c; this file is empty.
 *   - __APPLE__: symbols come from transmit_file_darwin.c (Darwin sendfile);
 *     this file is empty.
 *   - __linux__: this file provides the real sendfile backend.
 *   - other Unix: this file provides graceful stubs so the caller degrades
 *     to the bounded-buffer path (transmit_file returns -1).
 *
 * step() return contract (identical to the Windows TransmitFile backend):
 *    0  transfer complete
 *    1  chunk advanced, caller may yield and continue
 *    2  socket write would block, yield to the event loop and retry
 *   -1  invalid state
 *   -2  client disconnected
 *   -3  D-17 FILE_CHANGED (file size or mtime changed mid-transfer)
 *   -4  other I/O error
 */
#if defined(_WIN32)

/* Windows symbols live in transmit_file_windows.c. */

#elif defined(__APPLE__)

/* macOS symbols live in transmit_file_darwin.c (kqueue + Darwin sendfile). */

#else

#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdlib.h>
#include <sys/sendfile.h>
#include <sys/stat.h>
#include <unistd.h>
#ifndef MOONBIT_FFI_EXPORT
#define MOONBIT_FFI_EXPORT
#endif

#ifdef __linux__

typedef struct {
    int sock_fd;
    int file_fd;
    int64_t initial_file_size;
    int64_t initial_mtime_sec;
    int64_t initial_mtime_nsec;
    int64_t remaining;
    int64_t current_offset;
} TfState;

MOONBIT_FFI_EXPORT int64_t http_server_tf_open(
    int sock,
    const char* path,
    int64_t offset,
    int64_t length
) {
    if (sock < 0 || offset < 0 || length < 0 || path == NULL) {
        return 0;
    }

    int fd = open(path, O_RDONLY | O_CLOEXEC);
    if (fd < 0) {
        return 0;
    }

    struct stat st;
    if (fstat(fd, &st) != 0 || !S_ISREG(st.st_mode)) {
        close(fd);
        return 0;
    }

    int64_t file_size = (int64_t)st.st_size;
    if (offset > file_size || length > file_size - offset) {
        close(fd);
        return 0;
    }

    TfState* s = (TfState*)calloc(1, sizeof(TfState));
    if (s == NULL) {
        close(fd);
        return 0;
    }

    s->sock_fd = sock;
    s->file_fd = fd;
    s->initial_file_size = file_size;
    s->initial_mtime_sec = (int64_t)st.st_mtim.tv_sec;
    s->initial_mtime_nsec = (int64_t)st.st_mtim.tv_nsec;
    s->remaining = length;
    s->current_offset = offset;

    /* D-05: prefetch the region so a cold cache is less likely to block the
     * event-loop thread inside a synchronous sendfile call. */
    (void)posix_fadvise(fd, (off_t)offset, (off_t)length, POSIX_FADV_WILLNEED);

    return (int64_t)(intptr_t)s;
}

MOONBIT_FFI_EXPORT int32_t http_server_tf_step(int64_t state_ptr) {
    if (state_ptr == 0) return -1;
    TfState* s = (TfState*)(intptr_t)state_ptr;

    if (s->remaining <= 0) {
        return 0;
    }

    /* D-17 check: validate file size and mtime between chunks. */
    struct stat st;
    if (fstat(s->file_fd, &st) != 0) {
        return -3;
    }
    if ((int64_t)st.st_size != s->initial_file_size ||
        (int64_t)st.st_mtim.tv_sec != s->initial_mtime_sec ||
        (int64_t)st.st_mtim.tv_nsec != s->initial_mtime_nsec) {
        return -3;
    }

    const int64_t CHUNK_SIZE = 64 * 1024;
    size_t chunk = (size_t)(s->remaining > CHUNK_SIZE ? CHUNK_SIZE : s->remaining);

    /* Explicit offset: independent of the shared file position, advanced only
     * by bytes actually sent, so EAGAIN/EINTR never resends completed data. */
    off_t in_offset = (off_t)s->current_offset;
    ssize_t sent;
    do {
        sent = sendfile(s->sock_fd, s->file_fd, &in_offset, chunk);
    } while (sent < 0 && errno == EINTR);

    if (sent > 0) {
        s->current_offset += (int64_t)sent;
        s->remaining -= (int64_t)sent;
        if (s->remaining <= 0) {
            return 0;
        }
        return 1;
    }
    if (sent == 0) {
        /* File shrank below the requested region before completion. */
        return -3;
    }
    if (errno == EAGAIN || errno == EWOULDBLOCK) {
        return 2;
    }
    if (errno == EPIPE || errno == ECONNRESET) {
        return -2;
    }
    return -4;
}

MOONBIT_FFI_EXPORT void http_server_tf_close(int64_t state_ptr) {
    if (state_ptr == 0) return;
    TfState* s = (TfState*)(intptr_t)state_ptr;
    close(s->file_fd);
    free(s);
}

MOONBIT_FFI_EXPORT uint32_t http_server_get_handle_count(void) {
    DIR* dir = opendir("/proc/self/fd");
    if (dir == NULL) {
        return 0;
    }
    uint32_t count = 0;
    struct dirent* entry;
    while ((entry = readdir(dir)) != NULL) {
        if (entry->d_name[0] == '.') continue;
        count += 1;
    }
    closedir(dir);
    return count;
}

#else /* other Unix: no native backend yet, degrade gracefully */

MOONBIT_FFI_EXPORT int64_t http_server_tf_open(int sock, const char* path, int64_t offset, int64_t length) {
    (void)sock; (void)path; (void)offset; (void)length;
    return 0;
}

MOONBIT_FFI_EXPORT int32_t http_server_tf_step(int64_t state_ptr) {
    (void)state_ptr;
    return -1;
}

MOONBIT_FFI_EXPORT void http_server_tf_close(int64_t state_ptr) {
    (void)state_ptr;
}

MOONBIT_FFI_EXPORT uint32_t http_server_get_handle_count(void) {
    return 0;
}

#endif /* __linux__ */

#endif /* !_WIN32 */
