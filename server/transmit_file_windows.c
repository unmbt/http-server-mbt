#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <winsock2.h>
#include <mswsock.h>
#include <windows.h>
#include <stdint.h>
#include <stdlib.h>
#include <moonbit.h>

#pragma comment(lib, "ws2_32.lib")
#pragma comment(lib, "mswsock.lib")

typedef struct {
    HANDLE hFile;
    HANDLE hEvent;
    SOCKET sock;
    int64_t initial_file_size;
    FILETIME initial_mtime;
    int64_t remaining;
    int64_t current_offset;
    OVERLAPPED ov;
    DWORD current_chunk_bytes;
    int in_flight;
} TfState;

MOONBIT_FFI_EXPORT int64_t http_server_tf_open(
    SOCKET sock,
    const wchar_t* path,
    int64_t offset,
    int64_t length
) {
    if (length < 0 || offset < 0) {
        return 0;
    }

    HANDLE hFile = CreateFileW(
        path,
        GENERIC_READ,
        FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
        NULL,
        OPEN_EXISTING,
        FILE_FLAG_SEQUENTIAL_SCAN,
        NULL
    );

    if (hFile == INVALID_HANDLE_VALUE) {
        return 0;
    }

    BY_HANDLE_FILE_INFORMATION initial_info;
    if (!GetFileInformationByHandle(hFile, &initial_info)) {
        CloseHandle(hFile);
        return 0;
    }

    int64_t initial_file_size = ((int64_t)initial_info.nFileSizeHigh << 32) | (int64_t)initial_info.nFileSizeLow;
    if (offset + length > initial_file_size) {
        CloseHandle(hFile);
        return 0;
    }

    HANDLE hEvent = CreateEventW(NULL, TRUE, FALSE, NULL);
    if (hEvent == NULL) {
        CloseHandle(hFile);
        return 0;
    }

    TfState* s = (TfState*)calloc(1, sizeof(TfState));
    if (s == NULL) {
        CloseHandle(hEvent);
        CloseHandle(hFile);
        return 0;
    }

    s->sock = sock;
    s->hFile = hFile;
    s->hEvent = hEvent;
    s->initial_file_size = initial_file_size;
    s->initial_mtime = initial_info.ftLastWriteTime;
    s->remaining = length;
    s->current_offset = offset;
    s->in_flight = 0;

    return (int64_t)(intptr_t)s;
}

MOONBIT_FFI_EXPORT int32_t http_server_tf_step(int64_t state_ptr) {
    if (state_ptr == 0) return -1;
    TfState* s = (TfState*)(intptr_t)state_ptr;

    if (s->remaining <= 0) {
        return 0; // All requested bytes sent
    }

    if (s->in_flight) {
        DWORD transferred = 0;
        BOOL wait_ok = GetOverlappedResult((HANDLE)s->sock, &s->ov, &transferred, FALSE);
        if (wait_ok) {
            s->in_flight = 0;
            s->remaining -= s->current_chunk_bytes;
            s->current_offset += s->current_chunk_bytes;
            if (s->remaining <= 0) {
                return 0;
            }
            return 1;
        } else {
            DWORD err = GetLastError();
            DWORD wsa_err = WSAGetLastError();
            if (err == ERROR_IO_INCOMPLETE || wsa_err == ERROR_IO_INCOMPLETE ||
                err == ERROR_IO_PENDING || wsa_err == WSA_IO_PENDING) {
                return 2; // Still pending, yield to event loop
            }
            if (err == WSAECONNRESET || err == WSAECONNABORTED ||
                err == WSAESHUTDOWN || err == ERROR_NETNAME_DELETED ||
                err == ERROR_OPERATION_ABORTED ||
                wsa_err == WSAECONNRESET || wsa_err == WSAECONNABORTED ||
                wsa_err == WSAESHUTDOWN || wsa_err == ERROR_NETNAME_DELETED ||
                wsa_err == ERROR_OPERATION_ABORTED) {
                return -2; // Client disconnected
            }
            return -4; // Other I/O error
        }
    }

    // D-17 Check: Validate file mtime and size between chunks
    BY_HANDLE_FILE_INFORMATION cur_info;
    if (!GetFileInformationByHandle(s->hFile, &cur_info)) {
        return -3; // FILE_CHANGED
    }

    int64_t cur_file_size = ((int64_t)cur_info.nFileSizeHigh << 32) | (int64_t)cur_info.nFileSizeLow;
    if (cur_file_size != s->initial_file_size ||
        cur_info.ftLastWriteTime.dwLowDateTime != s->initial_mtime.dwLowDateTime ||
        cur_info.ftLastWriteTime.dwHighDateTime != s->initial_mtime.dwHighDateTime) {
        return -3; // FILE_CHANGED
    }

    const int64_t CHUNK_SIZE = 64 * 1024; // 64KB chunk
    DWORD bytes_to_send = (DWORD)(s->remaining > CHUNK_SIZE ? CHUNK_SIZE : s->remaining);

    ResetEvent(s->hEvent);
    memset(&s->ov, 0, sizeof(s->ov));
    s->ov.Offset = (DWORD)(s->current_offset & 0xFFFFFFFF);
    s->ov.OffsetHigh = (DWORD)((s->current_offset >> 32) & 0xFFFFFFFF);
    s->ov.hEvent = (HANDLE)((uintptr_t)s->hEvent | 1);
    s->current_chunk_bytes = bytes_to_send;

    BOOL ok = TransmitFile(
        s->sock,
        s->hFile,
        bytes_to_send,
        0,
        &s->ov,
        NULL,
        0
    );

    if (ok) {
        s->remaining -= bytes_to_send;
        s->current_offset += bytes_to_send;
        if (s->remaining <= 0) {
            return 0;
        }
        return 1;
    }

    DWORD err = WSAGetLastError();
    DWORD win_err = GetLastError();
    if (err == ERROR_IO_PENDING || err == WSA_IO_PENDING ||
        win_err == ERROR_IO_PENDING) {
        s->in_flight = 1;
        DWORD transferred = 0;
        if (GetOverlappedResult((HANDLE)s->sock, &s->ov, &transferred, FALSE)) {
            s->in_flight = 0;
            s->remaining -= bytes_to_send;
            s->current_offset += bytes_to_send;
            if (s->remaining <= 0) {
                return 0;
            }
            return 1;
        }
        return 2;
    }

    if (err == WSAECONNRESET || err == WSAECONNABORTED ||
        err == WSAESHUTDOWN || err == ERROR_NETNAME_DELETED ||
        err == ERROR_OPERATION_ABORTED ||
        win_err == WSAECONNRESET || win_err == WSAECONNABORTED ||
        win_err == WSAESHUTDOWN || win_err == ERROR_NETNAME_DELETED ||
        win_err == ERROR_OPERATION_ABORTED) {
        return -2;
    }
    return -4;
}

MOONBIT_FFI_EXPORT void http_server_tf_close(int64_t state_ptr) {
    if (state_ptr == 0) return;
    TfState* s = (TfState*)(intptr_t)state_ptr;
    if (s->in_flight) {
        CancelIoEx((HANDLE)s->sock, &s->ov);
        WaitForSingleObject(s->hEvent, 100);
        DWORD transferred = 0;
        GetOverlappedResult((HANDLE)s->sock, &s->ov, &transferred, FALSE);
        s->in_flight = 0;
    }
    CloseHandle(s->hEvent);
    CloseHandle(s->hFile);
    free(s);
}

MOONBIT_FFI_EXPORT uint32_t http_server_get_handle_count(void) {
    DWORD count = 0;
    GetProcessHandleCount(GetCurrentProcess(), &count);
    return (uint32_t)count;
}

#else

#include <stdint.h>
#ifndef MOONBIT_FFI_EXPORT
#define MOONBIT_FFI_EXPORT
#endif

MOONBIT_FFI_EXPORT int64_t http_server_tf_open(intptr_t sock, const void* path, int64_t offset, int64_t length) {
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

#endif
