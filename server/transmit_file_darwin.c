/*
 * Darwin (macOS) sendfile zero-copy file transfer backend for the server
 * package.
 *
 * Symbol ownership is complementary across the native-stub list: every stub
 * file compiles on every platform, so each platform must define
 * http_server_tf_* exactly once.
 *   - _WIN32: symbols come from transmit_file_windows.c; this file is empty.
 *   - __linux__ / other Unix: symbols come from transmit_file_linux.c (real
 *     sendfile backend / graceful stubs).
 *   - __APPLE__: this file provides the real Darwin sendfile backend.
 *
 * Darwin sendfile differs from Linux (D-05 macOS row):
 *   - declared in <sys/socket.h> as
 *       int sendfile(int fd, int s, off_t offset, off_t *len,
 *                    struct sf_hdtr *hdtr, int flags);
 *     with *len as a value-result parameter (input: bytes to send, output:
 *     bytes actually sent). Linux's explicit in-out offset pointer and
 *     ssize_t return value do not exist here.
 *   - the return value and the actual bytes sent must both be inspected:
 *     a non-blocking socket reports partial progress as -1/EAGAIN with *len
 *     advanced, and EINTR may return *len == 0 without meaning EOF.
 *   - short writes must advance the offset by the bytes actually sent; the
 *     explicit per-call offset never resends completed data.
 *
 * step() return contract (identical to the Windows/Linux backends):
 *    0  transfer complete
 *    1  chunk advanced, caller may yield and continue
 *    2  socket write would block, yield to the event loop and retry
 *   -1  invalid state
 *   -2  client disconnected
 *   -3  D-17 FILE_CHANGED (file size or mtime changed mid-transfer)
 *   -4  other I/O error
 */
#ifdef __APPLE__

#include <errno.h>
#include <fcntl.h>
#include <libproc.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#ifndef MOONBIT_FFI_EXPORT
#define MOONBIT_FFI_EXPORT
#endif

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
    s->initial_mtime_sec = (int64_t)st.st_mtimespec.tv_sec;
    s->initial_mtime_nsec = (int64_t)st.st_mtimespec.tv_nsec;
    s->remaining = length;
    s->current_offset = offset;

    /* D-05: prefetch the region so a cold cache is less likely to block the
     * event-loop thread inside a synchronous sendfile call. Darwin has no
     * posix_fadvise(POSIX_FADV_WILLNEED); F_RDADVISE is its counterpart and
     * failures are advisory-only. */
    struct radvisory ra;
    memset(&ra, 0, sizeof(ra));
    ra.ra_offset = (off_t)offset;
    ra.ra_count = length > 0x7fffffffLL ? 0x7fffffff : (int)length;
    (void)fcntl(fd, F_RDADVISE, &ra);

    return (int64_t)(intptr_t)s;
}

MOONBIT_FFI_EXPORT int32_t http_server_tf_step(int64_t state_ptr) {
    if (state_ptr == 0) return -1;
    TfState* s = (TfState*)(intptr_t)state_ptr;

    if (s->remaining <= 0) {
        return 0;
    }

    /* D-17 check: validate file size and mtime between chunks. Darwin names
     * the nanosecond field st_mtimespec (Linux uses st_mtim). */
    struct stat st;
    if (fstat(s->file_fd, &st) != 0) {
        return -3;
    }
    if ((int64_t)st.st_size != s->initial_file_size ||
        (int64_t)st.st_mtimespec.tv_sec != s->initial_mtime_sec ||
        (int64_t)st.st_mtimespec.tv_nsec != s->initial_mtime_nsec) {
        return -3;
    }

    const int64_t CHUNK_SIZE = 64 * 1024;
    int64_t chunk = s->remaining > CHUNK_SIZE ? CHUNK_SIZE : s->remaining;

    /* Value-result len: input is the bytes to send, output is the bytes
     * actually sent. EINTR before any data may report len == 0, so only
     * retry when nothing was sent; partial progress falls through and is
     * credited below. */
    off_t len = (off_t)chunk;
    int rc;
    do {
        len = (off_t)chunk;
        rc = sendfile(s->file_fd, s->sock_fd, (off_t)s->current_offset, &len, NULL, 0);
    } while (rc < 0 && errno == EINTR && len == 0);

    int64_t sent = (int64_t)len;
    if (sent > 0) {
        s->current_offset += sent;
        s->remaining -= sent;
        if (s->remaining <= 0) {
            return 0;
        }
        return 1;
    }
    if (rc == 0) {
        /* sendfile succeeded but transferred nothing: the file shrank below
         * the requested region between fstat and the transfer. */
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
    /* Darwin has no /proc/self/fd; count open descriptors via proc_pidinfo.
     * A NULL buffer query reports the required size. On any failure return 0
     * and the handle-leak assertions degrade to no-ops. */
    int needed = proc_pidinfo(getpid(), PROC_PIDLISTFDS, 0, NULL, 0);
    if (needed <= 0) {
        return 0;
    }
    struct proc_fdinfo* buf = (struct proc_fdinfo*)malloc((size_t)needed);
    if (buf == NULL) {
        return 0;
    }
    int got = proc_pidinfo(getpid(), PROC_PIDLISTFDS, 0, buf, needed);
    uint32_t count = 0;
    if (got > 0) {
        count = (uint32_t)((size_t)got / sizeof(struct proc_fdinfo));
    }
    free(buf);
    return count;
}

#endif /* __APPLE__ */
