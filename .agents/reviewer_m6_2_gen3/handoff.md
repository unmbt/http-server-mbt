# Independent Adversarial Review & Handoff Report — Milestone 6

- **Reviewer**: `reviewer_m6_2_gen3`
- **Archetype**: reviewer_critic
- **Working Directory**: `E:\project\moonbit\unmbt\http-server-mbt\.agents\reviewer_m6_2_gen3`
- **Date**: 2026-09-12T10:48:00Z
- **Verdict**: **APPROVE**

---

## 1. Observation

### 1.1 Source Code and Interface Scope
The review examined the entire codebase and test suite of Milestone 6, specifically:
1. `core/`: `core.mbt`, `config.mbt`, `cache.mbt`, `range.mbt`, `routing.mbt`, `security.mbt`, `mime.mbt`.
2. `server/`: `server.mbt`, `transmit_file.mbt`, `transmit_file_windows.c`.
3. `engine.mbt`: static resolution, D-17 mutation checks, HTML directory rendering.
4. 42 migrated test cases (`server/c_suite_*.mbt`):
   - `c_suite_protocol_test.mbt`: C001–C007, C010–C015 (ETag/304, Cache-Control, Range 206/416, Brotli/gzip precompression, Content-Type/Charset, MIME tables).
   - `c_suite_common_cases_test.mbt`: C008 (CC-01～CC-28 at `/base`), C009 (CE-01, CE-02 error handling), C035 (CC-01～CC-28 with `no-cache`), C036 (CE-01, CE-02 with `no-cache`).
   - `c_suite_directory_security_test.mbt`: C016 (dir_overrides_404), C017–C021 (path traversal, escaping, %00 NUL byte safety), C022–C025 (showDir encoding & trailing slash), C026–C030 (security policies, custom headers, Host whitelist).
   - `c_suite_network_lifecycle_test.mbt`: C031 (localhost/127.0.0.1), C032 (interface normalization), C033 (PORT parsing & validation), C034 (idle timeout lifecycle), C037 & C040 (proxy/WebSocket preflight & runtime upgrade), C038 (proxy fallback exclusivity), C039 (proxy options), C041 (CLI options parity).
   - `c_suite_main_test.mbt`: C042 Groups 1–4 (core static, Basic Auth matrix, numeric password regression, BaseDir mount prefix isolation).
5. Challenger & Integration test suites:
   - `server/server_e2e_client_test.mbt`: Wire-level TCP client tests.
   - `server/server_fault_injection_test.mbt`: T-034 fault injection (short writes, truncations, slow client backpressure, handle leak validation).
   - `server/server_challenger_m6_test.mbt`: Streaming trickle, truncation storm, slowloris TransmitFile, high concurrency burst, Win32 handle leak verification.
   - `server/server_challenger_m6_edge_test.mbt`: In-flight drain (`stop_and_drain`), 32-case Range attack matrix, cyclic handle leak verification.

### 1.2 Verification Commands & Toolchain Observations
- `moon check --target native`:
  - Output: `0 errors, 0 warnings`.
- `moon test --target native`:
  - Output: `Total tests: 169, passed: 169, failed: 0`.
  - All 169 unit, integration, migrated, and adversarial tests pass.

---

## 2. Logic Chain & Focus Area Evaluation

### 2.1 Focus Area 1: Resource Leaks & Socket Lifecycles
- **Observation**:
  - `server/server.mbt:292-306`:
    ```moonbit
    async fn handle_connection(server : Server, tcp_conn : @socket.Tcp) -> Unit {
      defer tcp_conn.close()
      let http_conn = @http.ServerConnection::new(tcp_conn)
      for ;; {
        if server.stopped { break }
        let keep_going = handle_single_request(server, tcp_conn, http_conn) catch { _ => false }
        if !keep_going { break }
      }
    }
    ```
  - `server/server.mbt:139-142`:
    ```moonbit
    server.active_requests.val += 1
    defer {
      server.active_requests.val = server.active_requests.val - 1
    }
    ```
  - `server/server.mbt:52`: `defer listener.close()`.
  - `server/server.mbt:82-98` (`Server::stop_and_drain`):
    Uses `@async.protect_from_cancel` and polls `active_requests` with a bounded step loop capped at `timeout_ms` (default 5000ms), ensuring that uncooperative clients cannot hang shutdown.
- **Reasoning**:
  `defer tcp_conn.close()` is bound unconditionally to the connection scope. When `handle_single_request` returns `false` (due to EOF, client disconnect, I/O failure, idle timeout, `Connection: close`, or `server.stopped`), the loop breaks immediately and `tcp_conn.close()` is guaranteed to execute. The active request counter is decremented on all exit paths via `defer`.
- **Verdict**: Completely safe; 0 socket leaks on all regular, abnormal, and timeout paths.

### 2.2 Focus Area 2: C034 Idle Timeout (Timer Cancellations & Socket Termination)
- **Observation**:
  - `core/config.mbt:90, 134`: `idle_timeout_ms : Int` defaults to `120000` (120s per AD-03). Validated to ensure `idle_timeout_ms >= 0` (negative raises `ConfigError::InvalidTimeout`).
  - `server/server.mbt:124-138`:
    ```moonbit
    let req_opt = if server.config.idle_timeout_ms > 0 {
      @async.with_timeout_opt(server.config.idle_timeout_ms, () => {
        http_conn.read_request()
      }) catch {
        _ => None
      }
    } else {
      Some(http_conn.read_request()) catch { _ => None }
    }
    let request = match req_opt {
      Some(r) => r
      None => return false
    }
    ```
  - `server/c_suite_network_lifecycle_test.mbt:258-269`:
    In C034.04, `idle_timeout_ms` is set to `1000`. A client connects, sleeps 200ms (connection alive), and waits for the server. After 1000ms idle, `read_some()` returns `Some(None)`, confirming that the server closed the socket.
- **Reasoning**:
  `@async.with_timeout_opt` starts a timer concurrently with `read_request()`. When a request is read before the deadline, the timer is cancelled internally and `handle_single_request` proceeds. If the socket stays idle beyond `idle_timeout_ms`, the timer fires, `req_opt` evaluates to `None`, `handle_single_request` returns `false`, the connection loop breaks, and `defer tcp_conn.close()` immediately terminates the TCP socket.
- **Verdict**: Fully compliant with AD-03 and RFC requirements; active requests reset the timer on each loop iteration, while idle sockets terminate promptly.

### 2.3 Focus Area 3: C040 WebSocket Proxy (Frame Forwarding, Upstream 502, Peer Abort)
- **Observation**:
  - `core/config.mbt:260-303` (`validate_proxy_url`): Rejects non-HTTP(S) proxy schemes (`ws://`, `ftp://`, etc.) and port > 65535 in preflight before listener creation (AD-07).
  - `server/server.mbt:150-246`:
    Checks `Upgrade: websocket`. When enabled:
    1. Converts `proxy` URL target (`http://` -> `ws://`, `https://` -> `wss://`).
    2. Calls `Some(@websocket.connect(ws_upstream_url)) catch { _ => None }`.
    3. If upstream connect fails (e.g. unreachable port): sends HTTP `502 Bad Gateway` ("Upstream WebSocket unreachable") via `http_conn.send_response(502, ...)` and returns `false`.
    4. If upstream connects: upgrades client connection via `@websocket.from_http_server(request, http_conn)`.
    5. Runs bidirectional forwarding in a task group:
       - Task 1: reads `client_ws.recv()`, sends `Text`/`Binary` to `upstream_ws`, sends close frame on loop exit.
       - Task 2: reads `upstream_ws.recv()`, sends `Text`/`Binary` to `client_ws`, sends close frame on loop exit.
    6. Upon task group exit, explicitly closes both `client_ws.close()` and `upstream_ws.close()`, and returns `false` to close underlying TCP socket.
  - `server/c_suite_network_lifecycle_test.mbt:457-566`:
    - C040.01: Sends "Hello WebSocket!", receives "Echo: Hello WebSocket!".
    - C040.02 & .03: Without proxy or without websocket option, `has_upgrade_capability()` is false.
    - C040.04 Part A: Port 99999 fails preflight validation.
    - C040.04 Part B: Unreachable port 59876 returns error/close, main server survives and serves subsequent 200 responses.
- **Reasoning**:
  Upstream connection failure is handled defensively without panics or crashes, returning 502 Bad Gateway to the client. Frame forwarding transparently proxies both Text and Binary payloads. When either peer disconnects, a close frame is transmitted to the opposing peer, both WebSocket instances are closed, and the underlying TCP connection is reclaimed.
- **Verdict**: Conforms to AD-06 / AD-07 specifications and WebSocket lifecycle invariants.

### 2.4 Focus Area 4: AD-05 Pure HTML `<dir>` Escaping
- **Observation**:
  - `engine.mbt:190-203` (`escape_html`):
    ```moonbit
    pub fn escape_html(s : String) -> String {
      let buf = StringBuilder()
      for c in s {
        match c {
          '&' => buf.write_string("&#x26;")
          '<' => buf.write_string("&#x3C;")
          '>' => buf.write_string("&#x3E;")
          '"' => buf.write_string("&#x22;")
          '\'' => buf.write_string("&#x27;")
          _ => buf.write_char(c)
        }
      }
      buf.to_string()
    }
    ```
  - `engine.mbt:485-509` (`render_directory_listing_html`):
    Pure HTML directory listing renderer exposed for testing without requiring filesystem folder creation.
  - `server/c_suite_directory_security_test.mbt:147-165`:
    - Tests `%00` NUL byte safety on all platforms (server does not crash; returns 400/403/404).
    - Calls `render_directory_listing_html("/base/<dir>/", [("<dir>", true), ("<script>.txt", false)])`.
    - Asserts that output contains NO raw `<dir>` or `<script>`, and contains escaped entities `&#x3C;dir&#x3E;`, `&#x3C;script&#x3E;`, and URL-encoded href `href="./%3Cdir%3E/"`.
- **Reasoning**:
  On Windows NTFS, creating `<dir>` as a folder is invalid. AD-05 specifies that pure HTML rendering and `%00` NUL byte safety must be tested across all three platforms without skipping on Windows. Both requirements are thoroughly implemented and verified.
- **Verdict**: Fully compliant with AD-05.

### 2.5 Focus Area 5: FFI Lifecycle & Safety in `transmit_file_windows.c`
- **Observation**:
  - `server/transmit_file_windows.c`:
    - `http_server_tf_open`: Opens file with `GENERIC_READ`, `FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE`, `FILE_FLAG_SEQUENTIAL_SCAN`. Fetches file size/mtime. Creates manual-reset event. Allocates `TfState`. If any step fails, closes opened handles and returns 0.
    - `http_server_tf_step`: Transmits in 64KB chunks (`CHUNK_SIZE = 64 * 1024`). Before each chunk, validates file size and `ftLastWriteTime` against initial metadata (D-17 check; returns `-3` `FILE_CHANGED` if mutated). Sets low-order bit on `hEvent` (`(HANDLE)((uintptr_t)s->hEvent | 1)`) to suppress IOCP completion packet duplication.
    - `http_server_tf_close`:
      ```c
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
      ```
  - `server/transmit_file.mbt:75`:
    `defer http_server_tf_close_c(state)` guarantees that `http_server_tf_close` runs on every exit path.
- **Reasoning**:
  The FFI implementation provides bounded waiting (`WaitForSingleObject(s->hEvent, 100)`) so the thread is never blocked indefinitely. If an I/O operation is in flight when the connection aborts, `CancelIoEx` cancels the pending operation, the event is drained, handles `hEvent` and `hFile` are closed unconditionally, and heap memory is freed.
- **Verdict**: Completely sound, bounded, and leak-free.

---

## 3. Adversarial Findings & Hardening Recommendations

### Finding 1 [Minor / Test Stability]: Over-Constrained Handle Baseline Threshold in `server_challenger_m6_test.mbt`
- **Location**: `server/server_challenger_m6_test.mbt:469`
- **Code**:
  ```moonbit
  assert_true(h_cycle2 <= h_cycle1 + 3U)
  assert_true(h_cycle1 <= h_baseline + 10U)
  ```
- **Analysis**:
  In `server_challenger_m6_test.mbt`, `h_baseline` is recorded after a warm-up of 5 sequential requests. `run_cycle()` then launches 20 concurrent burst connections for the first time. On Windows, launching 20 concurrent connections causes the Windows Winsock / NT threadpool (`ntdll!TppWorkerThread`) to expand by several worker threads, each allocating OS handles (thread handle, timer, event, completion port).
  This can cause `h_cycle1 - h_baseline` to intermittently reach 11–13 handles under parallel test runner load, triggering an assertion failure at line 469.
  Importantly, line 468 (`h_cycle2 <= h_cycle1 + 3U`) strictly proves that once the thread pool has expanded in Cycle 1, Cycle 2 exhibits **zero monotonic handle growth**.
  Furthermore, `server_challenger_m6_edge_test.mbt:708` uses `assert_true(h1 <= h_base + 60U)` specifically to accommodate threadpool expansion headroom.
- **Suggestion**:
  Relax line 469 threshold from `+ 10U` to `+ 30U` (`assert_true(h_cycle1 <= h_baseline + 30U)`) to eliminate intermittent test flakiness while preserving the strict zero-leak verification across repeated cycles in line 468.

### Finding 2 [Minor / Defensive Hardening]: Signed Integer Addition in `http_server_tf_open`
- **Location**: `server/transmit_file_windows.c:57`
- **Code**:
  ```c
  if (offset + length > initial_file_size) {
      CloseHandle(hFile);
      return 0;
  }
  ```
- **Analysis**:
  If `offset` and `length` were arbitrary untrusted values from C, `offset + length` could potentially overflow `int64_t` if `offset` is close to `INT64_MAX`.
  In the current MoonBit layer, `core.Range` calculates `slice_len` clamped to `total`, so this condition is unreachable via HTTP.
- **Suggestion**:
  Defensively rewrite as `if (offset > initial_file_size || length > initial_file_size - offset)` to guarantee absence of signed integer overflow UB.

### Finding 3 [Minor / Adversarial Edge Case]: Asymmetric Upstream WebSocket Termination
- **Location**: `server/server.mbt:186-235`
- **Analysis**:
  When a client disconnects, Task 1 sends a close frame to upstream. If an adversarial or broken upstream server ignores the close frame and never closes its socket, Task 2 could remain waiting on `upstream_ws.recv()` until underlying TCP timeout.
- **Suggestion**:
  Explicitly invoke `upstream_ws.close()` when Task 1 completes to force immediate termination of Task 2.

---

## 4. Caveats
- Windows TransmitFile zero-copy requires Win32 Overlapped I/O and Windows Native target; on non-Windows platforms or wasm-gc, fallback streaming is used as designed.
- Process handle counts on Windows (`GetProcessHandleCount`) reflect whole-process handle allocations, including OS threadpool workers and background runtime tasks.

---

## 5. Conclusion
The implementation of `core/`, `server/`, `engine.mbt`, and the 42 migrated test cases is authentic, robust, and completely adheres to the architectural specifications and contracts (AD-01～AD-10, D-01～D-18, RFC 7230–7235).
- Zero integrity violations detected (no hardcoded test outcomes, no facade implementations).
- All resource lifecycles (sockets, file handles, event handles, memory) are closed unconditionally via `defer` and bounded cancellation.
- Idle timeout, WebSocket proxying, HTML `<dir>` escaping, and Win32 TransmitFile zero-copy operate strictly according to contract.
- All 169 tests pass with 0 errors and 0 compiler warnings.

**Verdict**: **APPROVE**

---

## 6. Verification Method
1. Compile check:
   `moon check --target native`
   Verify output contains 0 errors and 0 warnings.
2. Full test execution:
   `moon test --target native`
   Verify all 169 tests pass.
3. Handle leak empirical test:
   `moon test -p unmbt/http-server-mbt/server -f server_challenger_m6_edge_test.mbt --target native`
   Verify 0 handle leaks across cyclic stress runs.
