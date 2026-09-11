# Handoff Report: Milestone 4 Windows Native TransmitFile & IOCP Zero-Copy Investigation (T-031)

**Agent**: explorer_survey_2  
**Handoff Type**: Hard (Investigation complete)  
**Target Milestone**: Milestone 4 (T-031 Windows Native TransmitFile and IOCP zero-copy transmission)  
**Detailed Report**: `E:\project\moonbit\unmbt\http-server-mbt\.agents\explorer_survey_2\report.md`

---

## 1. Observation

1. **Current File Region Body Transmission in `server/server.mbt`**:
   - `server/server.mbt` lines 52–56:
     ```moonbit
     FileRegion(_) => {
       let bytes = response.read(offset=0, max_len=response.body.length())
       conn.write(bytes)
     }
     ```
   - In `engine.mbt` lines 70–72, `response.read` opens the file via `@fs.open(path, mode=ReadOnly)` and reads the bytes into a MoonBit heap `Bytes` array (`file.read_exactly_at(chunk_len, position=read_pos)`). It performs no kernel-level zero-copy and buffers the entire file region in memory.
   - In `server.mbt` line 53, `offset=0` is hardcoded, and `response.body.length()` converts an `Int64` length to `Int`, risking overflow for files $>2\text{ GB}$.

2. **Socket Handle Encapsulation in `moonbitlang/async`**:
   - In `.mooncakes/moonbitlang/async/src/socket/tcp.mbt` line 30:
     ```moonbit
     pub fn Tcp::fd(self : Tcp) -> @fd_util.Fd {
       self.io.fd()
     }
     ```
   - In `.mooncakes/moonbitlang/async/src/types/types.mbt` lines 23–25:
     ```moonbit
     #cfg(platform="windows")
     #external
     pub type Fd
     ```
   - In `.mooncakes/moonbitlang/async/src/internal/fd_util/stub.c` lines 56–62:
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
   - In `.mooncakes/moonbitlang/async/src/http/server.mbt` line 19, `conn : @socket.Tcp` is a private field of `ServerConnection`. However, line 34 defines a public constructor:
     `pub fn ServerConnection::new(conn : @socket.Tcp, headers? : Headers) -> ServerConnection`.
   - In `.mooncakes/moonbitlang/async/src/socket/tcp.mbt` line 68, `@socket.TcpServer::run_forever` accepts connections and yields `(Tcp, Addr)` directly.

3. **Win32 `TransmitFile` and Overlapped Support**:
   - `TransmitFile` is in `mswsock.dll` / `mswsock.lib` and `ws2_32.dll`.
   - MSVC automatically links these libraries with `#pragma comment(lib, "ws2_32.lib")` and `#pragma comment(lib, "mswsock.lib")`, which is already standard across `.mooncakes/moonbitlang/async` (e.g., `io_windows.c`, `socket.c`, `schannel.c`).
   - `OVERLAPPED` has `Offset` and `OffsetHigh` (low/high 32-bit words of a 64-bit file position), matching `FileRegion(path, offset, length)` offsets directly.
   - `GetFileInformationByHandle` retrieves `nFileSizeHigh`, `nFileSizeLow`, and `ftLastWriteTime`, satisfying D-17 in-flight change detection.

4. **MoonBit Native Stub Integration Rules**:
   - Packages declare native C stubs via `options("native-stub": [ "filename.c" ])` in `moon.pkg`.
   - C functions exported as `MOONBIT_FFI_EXPORT` are callable via `extern "C" fn`.
   - On Windows, MoonBit's `String` is UTF-16, passing `LPCWSTR` (`const wchar_t*`) directly to C when decorated with `#borrow(path)`.

5. **Toolchain and Build Execution**:
   - Toolchain: Moon `0.1.20260904`, MSVC `cl.exe` (Windows Kits 10.0.22621.0).
   - Running `moon check --target native` returns exit code 0 (`Finished. moon: no work to do`).
   - Running `moon test --target native` runs 53 tests: 52 passed, 1 failed (`engine_security_directory_adversarial_test.mbt:397`, which belongs to Milestone 3 / Explorer 1).

---

## 2. Logic Chain

1. From **Observation 1**, `server/server.mbt` currently buffers entire files in memory via `response.read()` and `conn.write()`, failing requirement R2 / T-031 for zero-copy file transmission.
2. From **Observation 2**, `@http.ServerConnection` does not expose `.fd()`, but accepting connections through `@socket.TcpServer::run_forever` gives access to `@socket.Tcp` (`conn`), which has `pub fn Tcp::fd(self : Tcp) -> @fd_util.Fd`. In C on Windows, `(SOCKET)handle` converts this directly into the Win32 `SOCKET`.
3. From **Observation 3**, Win32 `TransmitFile` accepts a connected `SOCKET`, an open file `HANDLE`, byte count, and an `OVERLAPPED` pointer specifying the 64-bit file offset. This maps 1:1 to `ResponseBody::FileRegion(path, offset, length)`. Range requests (206) are served by setting `Offset`/`OffsetHigh` to the range start, with zero intermediate copies.
4. From **Observations 3 & 4**, chunking the transfer into 2MB blocks allows querying `GetFileInformationByHandle` between chunks to detect modification/truncation (D-17 `FILE_CHANGED`) and abort immediately without corrupting output.
5. From **Observation 4**, placing `transmit_file_windows.c` in `server/` with `"native-stub"` in `server/moon.pkg` integrates seamlessly into MoonBit Native compilation.
6. Combining all steps yields a clean architecture:
   - Header transmission flushed to wire.
   - `TransmitFile` invoked on `tcp_conn.fd()`.
   - 64KB bounded-buffer fallback for in-memory responses, non-Windows, or TransmitFile failure.
   - Unconditional `CloseHandle` on file and event handles + `defer tcp_conn.close()` guarantees 0 handle/socket leaks.

---

## 3. Caveats

1. **Milestone 3 Dependency**: `moon test --target native` currently fails 1 test in `engine_security_directory_adversarial_test.mbt` (terminal 404 on non-existent fallback). That is under active fix by Explorer 1 / implementer and does not affect the network I/O design of Milestone 4.
2. **Linux & macOS Scope**: Milestone 4 specifically targets Windows Native `TransmitFile`. Linux `sendfile` / macOS Darwin `sendfile` are assigned to Milestone 6 (T-017 / T-032). The proposed implementation includes `#cfg(platform="windows")` and `#cfg(not(platform="windows"))` stubs so cross-platform compilation is never broken.
3. **TLS Interaction**: Plaintext `TransmitFile` operates on unencrypted sockets. Future TLS support (Milestone 6) will automatically route through the bounded-buffer streaming fallback path unless Windows KTLS is explicitly enabled.

---

## 4. Conclusion

- **Feasibility**: 100% feasible and ready for implementation. No blocker or missing toolchain capability exists.
- **Architecture**:
  - `server/transmit_file_windows.c`: Win32 `TransmitFile` stub in 2MB chunks with D-17 `GetFileInformationByHandle` verification and `GetProcessHandleCount` probe.
  - `server/transmit_file.mbt`: MoonBit FFI declarations with `#cfg(platform="windows")`.
  - `server/server.mbt`: Loop using `@socket.TcpServer::run_forever` paired with `@http.ServerConnection`, zero-copy dispatch for `FileRegion`, and 64KB bounded-buffer fallback.
  - `server/server_test.mbt`: End-to-end integration tests for normal files, large files, Range (206), client disconnections, D-17 in-flight changes, and handle leak verification.

---

## 5. Verification Method

1. **Compilation & Type Check**:
   ```powershell
   moon check --target native
   ```
   Must yield 0 errors and 0 warnings.

2. **Integration Tests & Zero Handle Leak Verification**:
   ```powershell
   moon test --target native
   ```
   Must pass all tests, including new `server/server_test.mbt` covering:
   - Full static file download (hash match).
   - Range slice download (`Range: bytes=1000-4999`, exact 4000 bytes).
   - Early client disconnect (server logs clean closure, zero crash).
   - In-flight file truncation (response immediately aborts, connection closed).
   - Handle count stability: `GetProcessHandleCount` before and after 100 requests remains constant.

3. **Interface & Formatting Stability**:
   ```powershell
   moon info --target native
   moon fmt
   ```
   Inspect `.mbti` diffs to confirm no private types leaked into public interfaces.
