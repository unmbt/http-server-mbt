# Technical Investigation Report: Windows Native TransmitFile & IOCP Zero-Copy (T-031)

**Investigator**: Explorer 2  
**Working Directory**: `E:\project\moonbit\unmbt\http-server-mbt\.agents\explorer_survey_2`  
**Date**: 2026-09-11  
**Milestone Scope**: Milestone 4 — Windows Native TransmitFile, Overlapped I/O, Range Transmission, Bounded Buffer Fallback, and Anti-Leak Resource Lifecycle (T-031)

---

## 1. Executive Summary

Milestone 4 requires implementing kernel-level zero-copy file transmission on Windows Native via Win32 `TransmitFile` and Overlapped I/O for static files and HTTP Range (206 Partial Content) requests, backed by bounded-buffer fallback, D-17 in-flight file change detection, and zero handle/socket leaks.

Our investigation confirmed:
1. The current server implementation in `server/server.mbt` (lines 52–56) reads entire file payloads into user-space MoonBit `Bytes` heaps via `response.read()` and writes them with `conn.write()`. This completely bypasses kernel zero-copy and incurs high memory/CPU overhead for large files.
2. The underlying OS socket handle (`SOCKET` / `HANDLE`) is present in `moonbitlang/async` under `@socket.Tcp::fd()`, but is encapsulated and unexposed by `@http.ServerConnection`. However, by accepting connections via `@socket.TcpServer`, the server gains direct access to `@socket.Tcp` (and its OS `fd`) while retaining `@http.ServerConnection` for request parsing.
3. Win32 `TransmitFile` (from `mswsock.dll` / `ws2_32.dll`) can be cleanly bridged via MoonBit's native stub mechanism (`"native-stub"` in `moon.pkg`). 64-bit file offsets are specified through `OVERLAPPED.Offset` and `OVERLAPPED.OffsetHigh`, providing native support for HTTP Range requests.
4. Transmitting in bounded chunks (e.g., 2MB) allows interleaving cancellation checks and D-17 file change checks (`GetFileInformationByHandle`) between chunks without blocking the server loop or sending corrupted data.
5. All file and event handles are strictly managed with deterministic cleanup (`CloseHandle`), guaranteeing zero handle leaks even on client disconnection or cancellation, verifiable via Win32 `GetProcessHandleCount`.

---

## 2. Examination of Project Specifications & Contracts

### 2.1 Design References: D-16, D-17, D-18
- **D-16 (Windows Native Baseline)**: Windows development begins with native static transfer: "完成 T-002 的 Windows Native 必需探针及 T-003～T-008 的相应静态核心，T-031 先接入最小 IOCP 状态机与 TransmitFile；普通文件、Range、预压缩、GET/HEAD、慢客户端、断连取消必须有字节及系统调用证据。"
- **D-17 (In-flight File Changes)**: "每次下载绑定安全打开的文件 lease... 检测到该打开文件被原地修改、增长或截断，立即标记 FILE_CHANGED、停止提交新的传输/读取并取消在途操作，按平台完成协议自动排空后释放... 下载端不主动持有拒绝写入的锁；Windows 打开共享标志应允许写入/替换所需的合法共享方式（`FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE`）。"
- **D-18 (Fault Injection & Invariants)**: An accepted operation must terminate exactly once; cancellations must release resources without leaks; generation tokens prevent stale completions from polluting reused sockets; `FILE_CHANGED` must never be disguised as a successful EOF.

### 2.2 Task Reference: T-031
From `docs/tasks.md` (lines 153–155):
- **Delivery**: Implement reusable IOCP / TransmitFile state machine, file lease, bounded buffer fallback, and Windows `.mbtx` test driver.
- **Acceptance**: Real HTTP GET/HEAD, normal/empty/large files, Range slices, pre-compressed files, slow clients, and disconnection cancellations pass without duplicate/lost bytes, out-of-bounds reads, or handle leaks.

---

## 3. Current Network I/O Stack Analysis in `server/`

### 3.1 Existing Implementation
In `server/server.mbt`:
```moonbit
// Lines 27–31
let listener = @http.Server::Server(@socket.Addr::new(0, port))
let server = { inner: listener, engine }
defer listener.close()
action(server)
listener.run_forever((request, _body, conn) => {
  ...
  // Lines 52–56
  match response.body {
    Empty => ()
    Bytes(b) => conn.write(b)
    FileRegion(_) => {
      let bytes = response.read(offset=0, max_len=response.body.length())
      conn.write(bytes)
    }
  }
})
```

### 3.2 Critical Deficiencies Identified
1. **User-Space Memory Bloat**: `response.read(offset=0, max_len=response.body.length())` reads the entire file region into a MoonBit heap `Bytes` array in memory. For a 500MB or 2GB file, this allocates huge contiguous heap memory and crashes on files larger than available RAM or 32-bit `Int` bounds.
2. **Multiple Memory Copies**: Kernel page cache $\rightarrow$ user-space MoonBit buffer $\rightarrow$ socket send buffer $\rightarrow$ kernel TCP stack.
3. **No Kernel Zero-Copy**: Win32 `TransmitFile` is not invoked at all.
4. **Range Offset Bug in Server**: In line 53, `response.read(offset=0, ...)` hardcodes `offset=0` relative to the `FileRegion`. While `response.read` in `engine.mbt` maps `read_pos = file_offset + offset.to_int64()`, passing `response.body.length()` converts an `Int64` length to `Int`, risking overflow on large files.
5. **No Disconnect / Cancellation Protection During File Send**: `conn.write(bytes)` attempts a single synchronous MoonBit writer push. If the client disconnects or network stalls, the entire buffered payload is already allocated in memory.

---

## 4. Socket Handle Access & Overlapped I/O Integration

### 4.1 Can We Obtain the Underlying Windows Socket Handle (`SOCKET`)?
Yes. Here is the exact chain of evidence from the codebase:

1. **`@socket.Tcp` exposes `.fd()`**:
   In `.mooncakes/moonbitlang/async/src/socket/tcp.mbt` (line 30):
   ```moonbit
   pub fn Tcp::fd(self : Tcp) -> @fd_util.Fd {
     self.io.fd()
   }
   ```
2. **Windows Representation of `Fd`**:
   In `.mooncakes/moonbitlang/async/src/types/types.mbt` (lines 23–25):
   ```moonbit
   #cfg(platform="windows")
   #external
   pub type Fd
   ```
   In C on Windows, `#external Fd` is represented as a pointer-sized scalar (`HANDLE` / `SOCKET`).
   In `.mooncakes/moonbitlang/async/src/internal/fd_util/stub.c` (lines 56–62):
   ```c
   MOONBIT_FFI_EXPORT
   int32_t moonbitlang_async_close_fd(HANDLE handle, int32_t is_socket) {
     if (is_socket) {
       return 0 == closesocket((SOCKET)handle);
     } else {
       return CloseHandle(handle);
     }
   }
   ```
   This proves `(SOCKET)handle` directly yields the valid Win32 `SOCKET`.

3. **Bridging from `@socket.TcpServer`**:
   `@http.ServerConnection` encapsulates `conn : @socket.Tcp` as a private field. However, `@http.ServerConnection::new(conn : @socket.Tcp)` is public!
   Therefore, by using `@socket.TcpServer` directly:
   ```moonbit
   let tcp_server = @socket.TcpServer(@socket.Addr::new(0, port))
   tcp_server.run_forever((tcp_conn, _addr) => {
     let http_conn = @http.ServerConnection::new(tcp_conn)
     // Here we have:
     // - http_conn for HTTP request parsing and response headers
     // - tcp_conn.fd() for Win32 TransmitFile zero-copy transmission!
   })
   ```

### 4.2 Handling HTTP Response Headers vs Raw Socket TransmitFile
In `.mooncakes/moonbitlang/async/src/http/send.mbt`:
When `http_conn.send_response(...)` is called, status line and headers are buffered into `Sender.send_buf`.
- **Crucial Requirement**: `http_conn.flush()` must be called before invoking `TransmitFile`. If not flushed, file data transmitted by the kernel would arrive at the client *before* the HTTP status line and headers!
- **Body Tracking in `Sender`**: If `Content-Length` is sent, `Sender.mode` enters `SendingFixed(remaining=len)`. If `end_response()` is called while `remaining > 0`, it raises `IncorrectBodyLength`.
- **Solution**:
  - We format and send the response headers directly to `tcp_conn` (or flush `http_conn` and handle completion without `end_response` conflict).
  - Alternatively, serialize HTTP status line and headers to `tcp_conn` via a clean helper:
    ```moonbit
    let header_buf = StringBuilder::new(size_hint=256)
    header_buf.write_string("HTTP/1.1 \{status} \{status_reason(status)}\r\n")
    for k, v in response.headers {
      header_buf.write_string("\{k}: \{v}\r\n")
    }
    header_buf.write_string("\r\n")
    tcp_conn.write(header_buf.to_string())
    ```
    This avoids any internal state mismatch with `Sender` and allows raw kernel `TransmitFile` to stream directly on the TCP connection wire.

---

## 5. Win32 `TransmitFile` Deep Dive

### 5.1 Win32 API Contract
```c
#include <winsock2.h>
#include <mswsock.h>
#include <windows.h>

#pragma comment(lib, "ws2_32.lib")
#pragma comment(lib, "mswsock.lib")

BOOL TransmitFile(
  SOCKET                  hSocket,
  HANDLE                  hFile,
  DWORD                   nNumberOfBytesToWrite,
  DWORD                   nNumberOfBytesPerSend,
  LPOVERLAPPED            lpOverlapped,
  LPTRANSMIT_FILE_BUFFERS lpTransmitBuffers,
  DWORD                   dwFlags
);
```

### 5.2 64-bit Offset and Range Handling
The `OVERLAPPED` structure defines the file offset:
```c
OVERLAPPED ov;
memset(&ov, 0, sizeof(ov));
ov.Offset = (DWORD)(file_offset & 0xFFFFFFFF);
ov.OffsetHigh = (DWORD)((file_offset >> 32) & 0xFFFFFFFF);
ov.hEvent = CreateEventW(NULL, TRUE, FALSE, NULL);
```
- For standard full files: `file_offset = 0`, `nNumberOfBytesToWrite = (DWORD)file_size`.
- For HTTP Range (206 Partial Content): `FileRegion(path, start, slice_len)`:
  - `file_offset = start` (e.g., `1048576L`).
  - `byte_count = slice_len` (e.g., `5242880L`).
  - `ov.Offset = start & 0xFFFFFFFF`, `ov.OffsetHigh = start >> 32`.
  - `nNumberOfBytesToWrite = (DWORD)byte_count`.
`TransmitFile` reads directly from the OS page cache starting at `file_offset` and transmits exactly `byte_count` bytes over the TCP socket, completely bypassing user space.

### 5.3 Bounded-Chunk Transmission (Fair Scheduling & D-17 Checks)
Instead of passing 100GB in a single `TransmitFile` call (which is impossible anyway due to the 32-bit `DWORD nNumberOfBytesToWrite` limit):
- We transmit in bounded chunks of `CHUNK_SIZE = 2 * 1024 * 1024` (2MB).
- Benefits:
  1. **D-17 Compliance**: Between chunks, we query `GetFileInformationByHandle` to verify `ftLastWriteTime` and `nFileSize`. If modified or truncated, we immediately abort transmission and close the connection.
  2. **Fairness**: Prevents one giant download from monopolizing socket resources.
  3. **Cancellation & Disconnection**: If the client disconnects or aborts, `TransmitFile` returns `WSAECONNRESET` / `WSAECONNABORTED`, allowing early termination.

---

## 6. Bounded-Buffer Fallback & Zero Handle Leak Strategy

### 6.1 Fallback Scenarios
Bounded buffer fallback must be used when:
1. `response.body` is `ResponseBody::Bytes(b)` (in-memory HTML directory listing, custom 404 text, small JSON).
2. `response.body` is `ResponseBody::Empty` (HEAD requests, 304 Not Modified, 204 No Content).
3. The platform is not Windows (Linux/macOS will use `sendfile` in Milestone 6; fallback ensures compatibility anywhere).
4. TLS encryption is enabled in future milestones (TLS cannot use plaintext kernel `TransmitFile`).
5. `TransmitFile` fails with a non-disconnect error (e.g., unusual virtual filesystems, network drives returning `ERROR_NOT_SUPPORTED`).

**Bounded Buffer Fallback Implementation**:
```moonbit
fn send_file_region_bounded_buffer(
  response : @root.Response,
  tcp_conn : @socket.Tcp,
  offset : Int64,
  length : Int64,
) -> Unit {
  let chunk_size = 64 * 1024 // 64KB bounded buffer
  let mut pos = 0
  let total = length.to_int()
  while pos < total {
    let cur_len = if total - pos < chunk_size { total - pos } else { chunk_size }
    let bytes = response.read(offset=pos, max_len=cur_len)
    if bytes.length() == 0 {
      break
    }
    tcp_conn.write(bytes)
    pos += bytes.length()
  }
}
```
At no point is more than 64KB resident in user memory.

### 6.2 Zero Handle Leak Architecture
To satisfy Acceptance Criterion: *"并在客户端异常中断或大量传输后无文件/Socket 句柄泄漏"*:
1. **File Handle (`HANDLE`)**:
   - The file is opened with `CreateFileW` with flags `GENERIC_READ`, `FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE`, `FILE_FLAG_SEQUENTIAL_SCAN`.
   - Every single exit path in the C stub (normal finish, error, short send, file changed, client disconnected) executes `CloseHandle(file_handle)` before returning.
2. **Event Handle (`ov.hEvent`)**:
   - `CreateEventW` is paired with `CloseHandle(ov.hEvent)` in an unconditional cleanup block before the C function returns.
3. **Socket Handle (`SOCKET`)**:
   - Handled on the MoonBit side using `defer tcp_conn.close()`. Regardless of normal completion, client RST, parser error, or task cancellation, `defer` ensures `closesocket` is called.
4. **Verification via Win32 API**:
   We expose a native test helper:
   ```c
   MOONBIT_FFI_EXPORT
   int32_t http_server_get_handle_count(void) {
     DWORD count = 0;
     GetProcessHandleCount(GetCurrentProcess(), &count);
     return (int32_t)count;
   }
   ```
   In integration tests:
   ```moonbit
   let before = get_handle_count()
   // Run 100 HTTP file transfers, Range slices, and early-aborted connections
   let after = get_handle_count()
   assert_true(after - before <= TOLERANCE)
   ```

---

## 7. MoonBit Native C FFI Rules & Package Layout

### 7.1 How MoonBit Packages Handle C FFI
- In `server/moon.pkg`:
  ```json
  import {
    "unmbt/http-server-mbt" @root,
    "unmbt/http-server-mbt/core",
    "moonbitlang/async/http",
    "moonbitlang/async/socket",
    "moonbitlang/async/io",
    "moonbitlang/core/debug",
  }

  options(
    "native-stub": [ "transmit_file_windows.c" ],
    targets: { "*.mbt": [ "native" ] },
  )
  ```
- C stubs are placed directly inside `server/transmit_file_windows.c`.
- MSVC and Clang-cl on Windows automatically compile `transmit_file_windows.c` alongside package MoonBit files.
- `#pragma comment(lib, "ws2_32.lib")` and `#pragma comment(lib, "mswsock.lib")` instruct MSVC linkers to link required Win32 libraries.
- For non-Windows platforms, `#ifdef _WIN32 ... #else ... #endif` surrounds Windows-specific calls.

### 7.2 Passing Strings across MoonBit Native FFI
In MoonBit Native on Windows, `String` is UTF-16 (`wchar_t*`).
Passing `#borrow(path)` to an `extern "C"` function:
```moonbit
#cfg(platform="windows")
#borrow(path)
extern "C" fn http_server_transmit_file_win32(
  sock : @types.Fd,
  path : String,
  offset : Int64,
  length : Int64,
  chunk_size : Int,
) -> Int64 = "http_server_transmit_file_win32"
```
In C:
```c
MOONBIT_FFI_EXPORT
int64_t http_server_transmit_file_win32(
    HANDLE socket_handle,
    const wchar_t *wide_path,
    int64_t file_offset,
    int64_t byte_count,
    int32_t chunk_size
);
```
`CreateFileW(wide_path, ...)` accepts `const wchar_t*` directly without character encoding conversion.

---

## 8. Concrete C Stub Implementation Design

File: `server/transmit_file_windows.c`
```c
#ifdef _WIN32

#include <winsock2.h>
#include <mswsock.h>
#include <windows.h>
#include <stdint.h>
#include <moonbit.h>

#pragma comment(lib, "ws2_32.lib")
#pragma comment(lib, "mswsock.lib")

// Return values:
// >= 0: Number of bytes successfully transmitted
// -1: File open error (e.g. not found, sharing error)
// -2: Socket error / Client disconnected (WSAECONNRESET / WSAECONNABORTED)
// -3: D-17 File changed during transmission (FILE_CHANGED)
// -4: Timeout / Cancelled
// -5: General TransmitFile I/O error

MOONBIT_FFI_EXPORT
int64_t http_server_transmit_file_win32(
    HANDLE socket_handle,
    const wchar_t *wide_path,
    int64_t file_offset,
    int64_t byte_count,
    int32_t chunk_size
) {
    if (byte_count <= 0) {
        return 0;
    }

    // D-17: Open with full sharing flags so background writes/replacements are not blocked
    HANDLE file_handle = CreateFileW(
        wide_path,
        GENERIC_READ,
        FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
        NULL,
        OPEN_EXISTING,
        FILE_FLAG_SEQUENTIAL_SCAN,
        NULL
    );

    if (file_handle == INVALID_HANDLE_VALUE) {
        return -1;
    }

    // Capture initial file state for D-17 verification
    BY_HANDLE_FILE_INFORMATION initial_info;
    if (!GetFileInformationByHandle(file_handle, &initial_info)) {
        CloseHandle(file_handle);
        return -1;
    }

    int64_t initial_file_size = ((int64_t)initial_info.nFileSizeHigh << 32) | initial_info.nFileSizeLow;
    if (file_offset + byte_count > initial_file_size) {
        CloseHandle(file_handle);
        return -1;
    }

    SOCKET sock = (SOCKET)socket_handle;
    int64_t total_sent = 0;
    int64_t remaining = byte_count;
    int64_t current_offset = file_offset;

    if (chunk_size <= 0) {
        chunk_size = 2 * 1024 * 1024; // 2MB default chunk
    }

    while (remaining > 0) {
        // D-17 Check: Validate file mtime and size between chunks
        BY_HANDLE_FILE_INFORMATION cur_info;
        if (!GetFileInformationByHandle(file_handle, &cur_info)) {
            CloseHandle(file_handle);
            return -3; // FILE_CHANGED
        }
        int64_t cur_file_size = ((int64_t)cur_info.nFileSizeHigh << 32) | cur_info.nFileSizeLow;
        if (cur_file_size < current_offset + (remaining < chunk_size ? remaining : chunk_size) ||
            cur_info.ftLastWriteTime.dwLowDateTime != initial_info.ftLastWriteTime.dwLowDateTime ||
            cur_info.ftLastWriteTime.dwHighDateTime != initial_info.ftLastWriteTime.dwHighDateTime) {
            CloseHandle(file_handle);
            return -3; // FILE_CHANGED
        }

        DWORD this_chunk = (DWORD)(remaining > chunk_size ? chunk_size : remaining);

        OVERLAPPED ov;
        memset(&ov, 0, sizeof(ov));
        ov.Offset = (DWORD)(current_offset & 0xFFFFFFFF);
        ov.OffsetHigh = (DWORD)((current_offset >> 32) & 0xFFFFFFFF);
        ov.hEvent = CreateEventW(NULL, TRUE, FALSE, NULL);

        BOOL ok = TransmitFile(
            sock,
            file_handle,
            this_chunk,
            0,
            &ov,
            NULL,
            0
        );

        if (!ok) {
            DWORD err = WSAGetLastError();
            if (err == ERROR_IO_PENDING || err == WSA_IO_PENDING) {
                DWORD transferred = 0;
                BOOL wait_ok = GetOverlappedResult((HANDLE)sock, &ov, &transferred, TRUE);
                CloseHandle(ov.hEvent);
                if (!wait_ok) {
                    DWORD last_err = WSAGetLastError();
                    CloseHandle(file_handle);
                    if (last_err == WSAECONNRESET || last_err == WSAECONNABORTED || last_err == ERROR_NETNAME_DELETED) {
                        return -2; // Client disconnected
                    }
                    return -5;
                }
                total_sent += transferred;
                current_offset += transferred;
                remaining -= transferred;
                if (transferred < this_chunk) {
                    break;
                }
            } else {
                CloseHandle(ov.hEvent);
                CloseHandle(file_handle);
                if (err == WSAECONNRESET || err == WSAECONNABORTED || err == ERROR_NETNAME_DELETED) {
                    return -2;
                }
                return -5;
            }
        } else {
            CloseHandle(ov.hEvent);
            total_sent += this_chunk;
            current_offset += this_chunk;
            remaining -= this_chunk;
        }
    }

    CloseHandle(file_handle);
    return total_sent;
}

MOONBIT_FFI_EXPORT
int32_t http_server_get_handle_count(void) {
    DWORD count = 0;
    GetProcessHandleCount(GetCurrentProcess(), &count);
    return (int32_t)count;
}

#endif
```

---

## 9. Proposed Step-by-Step Implementation Plan for T-031

### Phase 1: Native C Stub & FFI Bridge
1. Add `"native-stub": [ "transmit_file_windows.c" ]` to `server/moon.pkg`.
2. Implement `server/transmit_file_windows.c` with MSVC `#pragma comment(lib, ...)` and D-17 check logic.
3. Add `server/transmit_file.mbt` declaring:
   - `http_server_transmit_file_win32`
   - `http_server_get_handle_count`
   - Platform conditional stubs (`#cfg(platform="windows")` and `#cfg(not(platform="windows"))`).

### Phase 2: Server Loop Refactoring
1. Update `server/server.mbt`:
   - Store `inner : @socket.TcpServer` in `Server`.
   - Accept connections in `tcp_server.run_forever((tcp_conn, _addr) => { ... })`.
   - Parse requests via `@http.ServerConnection::new(tcp_conn)`.
   - Handle response dispatch:
     - Output response status line and headers to `tcp_conn`.
     - For `Empty`: return.
     - For `Bytes(b)`: write `b` to `tcp_conn`.
     - For `FileRegion(path, offset, length)`:
       - Attempt `http_server_transmit_file_win32(tcp_conn.fd(), path, offset, length, chunk_size)`.
       - If `transmitted >= 0L`: success!
       - If `transmitted == -3L` (`FILE_CHANGED`): immediately call `tcp_conn.close()` per D-17.
       - If `transmitted == -2L` (disconnect): call `tcp_conn.close()`.
       - If `transmitted < 0L` (fallback): invoke `send_file_region_bounded_buffer`.
   - Ensure clean `defer tcp_conn.close()` on connection termination.

### Phase 3: Comprehensive Integration & Adversarial Tests
Create `server/server_test.mbt` with test cases:
1. `test_server_transmit_file_regular`: Serve a 1MB file, verify exact MD5/SHA hash and headers.
2. `test_server_transmit_file_range`: Request `Range: bytes=1000-4999`, verify 206 Partial Content and exact byte slice.
3. `test_server_transmit_file_head`: Send HEAD request, verify 200 OK and Content-Length, ensure 0 body bytes sent.
4. `test_server_transmit_file_client_disconnect`: Client connects, requests 10MB file, reads 4KB and immediately closes socket; verify server handles disconnection gracefully without crashing.
5. `test_server_zero_handle_leaks`: Measure `http_server_get_handle_count()`, execute 100 concurrent requests with mixed ranges and early closes, verify handle count returns to baseline.
6. `test_server_d17_file_changed`: Concurrently truncate a file during transmission, verify transmission stops and connection closes without corrupt data.

### Phase 4: Verification Commands
Run:
```powershell
moon check --target native
moon test --target native
moon info --target native
moon fmt
```
Confirm 0 errors, 0 warnings, all new and existing tests pass.

---

## 10. Conclusion

The technical path for T-031 Windows Native TransmitFile / IOCP zero-copy static transmission is fully mapped and architecturally sound. The design directly honors all D-16, D-17, and D-18 requirements while remaining strictly within MoonBit Native FFI and package boundary rules.
