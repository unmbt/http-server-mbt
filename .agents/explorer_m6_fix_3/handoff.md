# Handoff Report — explorer_m6_fix_3

**Agent**: explorer_m6_fix_3  
**Working Directory**: `E:\project\moonbit\unmbt\http-server-mbt\.agents\explorer_m6_fix_3`  
**Parent**: orchestrator_m6_gen2 (Conv ID: `dcf6fc8a-69f5-4537-8275-a1f2ab70f9af`)  
**Timestamp**: 2026-09-12T02:45:00Z  
**Type**: Hard Handoff  

---

## 1. Observation

### 1.1 Item 1: AD-03 & C034 (`idle_timeout_ms` & C034.04 1000ms idle disconnect)
- **Specification (`docs/design.md` AD-03)**:
  > "新 API 字段明确为 `idle_timeout_ms`，Server/CLI 默认 120000 ms；CLI `-t` 为秒；迁移显式库数值时按原来的毫秒行为，1000 ms 真实断连必须验证。创建对象的测试不扩写为原来没有的“默认 120 秒已验证”"
- **Task Contract (`docs/tasks.md` C034)**:
  > ".01 无配置创建成功；.02 显式 60 创建成功；.03 0 创建成功并测禁用；.04 1000 ms 空闲触发超时并真实断连；.05 配置 60 时正常请求 200 且非空；.06 对 30/120/300/0 四值分别创建。按 AD-03 不把注释当单位断言"
- **Original Source Reference (`http-server/test/timeout.test.js:75-122`)**:
  ```javascript
  test('timeout: connection actually times out after specified duration', (t) => {
    const timeoutMs = 1000;
    const server = httpServer.createServer({ root, timeout: timeoutMs });
    ...
    // Create a connection but don't send any data
    const socket = require('net').createConnection(port, 'localhost', () => {});
    socket.on('error', () => { /* Connection errors are expected when timeout fires */ });
    ...
  });
  ```
- **Observed in `server/server.mbt`**:
  Lines 3-9 define `pub struct Server`:
  ```moonbit
  pub struct Server {
    inner : @socket.TcpServer
    engine : @root.StaticEngine
    mut stopped : Bool
    mut task : @async.Task[Unit]?
    active_requests : Ref[Int]
  }
  ```
  `Server` struct does not hold `config : @core.Config`.
  In `handle_connection` (lines 163-175) and `handle_single_request` (lines 112-160):
  ```moonbit
  let request = http_conn.read_request() catch { _ => return false }
  ```
  `http_conn.read_request()` blocks indefinitely on idle sockets without inspecting `idle_timeout_ms`.
- **Observed in `server/c_suite_network_lifecycle_test.mbt` lines 238-296**:
  C034 only asserts `@core.validate_config` against `[0, 30000, 60000, 120000, 300000, -1]` and executes a normal 200 request with `60000`. Subcase `.04` (1000ms idle triggering timeout and actual disconnection) is completely missing.
- **Observed in MoonBit async ecosystem (`.mooncakes/moonbitlang/async/src/async.mbt:87-95`)**:
  `@async.with_timeout_opt(time : Int, f : async () -> X) -> X?` is built-in:
  If `time` elapses before `f` completes, `with_timeout_opt` returns `None` and cancels `f`.
  When a TCP connection is closed by remote, `conn.read_some()` unblocks and returns `None` (EOF).

---

### 1.2 Item 2: AD-07 & C040 (WebSocket Upgrade & Error Handling)
- **Specification (`docs/design.md` AD-07)**:
  > "WebSocket 错误案例配置端口 99999 后才在连接时出错；已确认的新契约要求配置错误在监听前失败。C040.04 记录失败时机改变：非法端口返回配置错误且无监听；另用合法但未监听端口验证已开启 upgrade 后的 error/close、不中止主服务。两项均必测，明确这是行为调整，不声称原断言原样通过"
- **Specification (`docs/design.md` AD-06)**:
  > "原版用 Node 的 server 对象、upgrade listener 数量、timeout 事件和 Express next 观察状态。映射为本设计的生命周期、upgrade 能力、超时事件/断连和 `Next`/错误委托，保留其 HTTP 和资源断言，不要求 Node 对象布局"
- **Task Contract (`docs/tasks.md` C040)**:
  > ".01 有 proxy+websocket 注册等价 upgrade 能力，发送 Hello WebSocket! 收到 Echo: Hello WebSocket!；.02 无 proxy、.03 未启用 websocket 均无 upgrade；.04 错误处理按 AD-07 拆为非法端口启动失败与合法不可达端口的运行 error/close，主服务存活"
- **Original Source Reference (`http-server/test/websocket-proxy.test.js`)**:
  - Test 1 (`lines 10-90`): Target echo server on port $P_{target}$, proxy server with `{ proxy: targetUrl, websocket: true }`, client connects to proxy URL via `new WebSocket('ws://...')`, sends `'Hello WebSocket!'`, expects `'Echo: Hello WebSocket!'`.
  - Test 2 (`lines 92-118`): `{ websocket: true }` without `proxy` -> `listeners('upgrade').length == 0`.
  - Test 3 (`lines 120-157`): `{ proxy: targetUrl }` without `websocket` -> `listeners('upgrade').length == 0`.
  - Test 4 (`lines 159-214`): `{ proxy: 'http://localhost:99999', websocket: true }` -> connection error/close handled gracefully, server survives.
- **Observed in `core/config.mbt`**:
  - `Config` struct has `proxy : String?`, `proxy_all : String?`, `proxy_options : Map[String, String]`, but does NOT have `websocket : Bool`.
  - `validate_proxy_url` (lines 253-259) only checks prefix `http://` / `https://`; it does NOT parse or validate the port number in the proxy URL (allowing port 99999 to pass preflight).
- **Observed in `server/server.mbt`**:
  `server` does not implement WebSocket upgrade interception or proxying.
- **Observed in MoonBit async ecosystem (`.mooncakes/moonbitlang/async/src/websocket/`)**:
  MoonBit standard library includes a complete native WebSocket implementation:
  - `@websocket.from_http_server(request, conn)` takes `@http.Request` and `@http.ServerConnection`, replies `101 Switching Protocols`, and returns a WebSocket `Conn`.
  - `@websocket.Conn::connect("ws://...")` connects upstream to another WebSocket server.
  - Full support for `ws.recv()`, `ws.send_text()`, `ws.send_binary()`, `ws.send_close()`, `ws.close()`.

---

### 1.3 Item 3: AD-05 & C019 (Pure HTML Directory Listing Escaping for `<dir>`)
- **Specification (`docs/design.md` AD-05)**:
  > "`pathname-encoding.test.js` 在 Windows 整个文件提前返回，包含 NUL 测试也被跳过。`<dir>` 实体化文件夹案例仅 POSIX；NUL 防崩及纯 HTML 转义测试在三平台新增，不把 Windows 跳过计作通过"
- **Task Contract (`docs/tasks.md` C019)**:
  > ".00 创建 `<dir>` fixture；.01 页面不含裸 `<dir>`，含 `&#x3C;dir&#x3E;`；.02 `%00` 请求服务不崩；.03 清理 fixture。按 AD-05，Windows .00/.01/.03 文件系统案例为条件不适用，.02 与纯渲染在新增测试三平台覆盖"
- **Original Source Reference (`http-server/test/pathname-encoding.test.js:15-18`)**:
  ```javascript
  if (process.platform === 'win32') {
    tap.plan(0, 'Windows is allergic to < in path names');
    return;
  }
  ```
  On Windows NTFS, `<` and `>` are forbidden characters in file/directory paths.
- **Observed in `engine.mbt`**:
  - `escape_html(s : String) -> String` (lines 189-202):
    ```moonbit
    match c {
      '&' => buf.write_string("&#x26;")
      '<' => buf.write_string("&#x3C;")
      '>' => buf.write_string("&#x3E;")
      '"' => buf.write_string("&#x22;")
      '\'' => buf.write_string("&#x27;")
      _ => buf.write_char(c)
    }
    ```
    Already escapes `<dir>` to `&#x3C;dir&#x3E;`.
  - `render_directory_html(title_path, entries, raw_query, host)` (lines 387-479) escapes `title_path` and `entry.name` via `escape_html`.
  - `render_directory_html` is `fn` (internal to `unmbt/http-server-mbt`).
- **Observed in `server/c_suite_directory_security_test.mbt:147-150`**:
  Only `%00` NUL byte is asserted (`dirsec_get(port, "/%00hello.txt")`). The pure HTML directory listing escaping for `<dir>` (`<dir>` -> `&#x3C;dir&#x3E;`) is not asserted.

---

## 2. Logic Chain

### 2.1 Logic Chain for AD-03 & C034
1. **Requirement & Default Invariant**:
   `core.Config` sets `idle_timeout_ms: 120000` (120s per AD-03) and validates `idle_timeout_ms >= 0` (`0` means disabled).
2. **Current Missing Link**:
   `Server` in `server/server.mbt` does not retain `config : @core.Config`, and `handle_single_request` executes `http_conn.read_request()` with no timeout wrapper. Idle sockets hang indefinitely until the remote side closes or the process exits.
3. **Async Architecture Mapping**:
   In `moonbitlang/async`, `@async.with_timeout_opt(time_ms, f)` runs `f` and returns `None` if `time_ms` expires, automatically cancelling the pending task `f`.
   - When `server.config.idle_timeout_ms > 0`: wrap `http_conn.read_request()` in `@async.with_timeout_opt(server.config.idle_timeout_ms, ...)`.
   - When `server.config.idle_timeout_ms == 0`: invoke `http_conn.read_request()` directly without timeout.
   - If `with_timeout_opt` returns `None`: an idle timeout occurred. `handle_single_request` returns `false`, causing `handle_connection` to break from its loop and execute `defer tcp_conn.close()`.
4. **Verification of C034.04**:
   - Start server with `idle_timeout_ms: 1000`.
   - Connect client via `@socket.Tcp::connect(@socket.Addr::new(0x7F000001, port))`.
   - Client sends NO bytes and waits for read using `@async.with_timeout_opt(3000, () => conn.read_some())`.
   - Server drops the connection after 1000ms. Client receives `None` from `conn.read_some()`.
   - Client asserts elapsed time $\ge 900\text{ms}$ and $\le 2500\text{ms}$, and result is `Some(None)`, proving true idle disconnect.

### 2.2 Logic Chain for AD-07 & C040
1. **Configuration Alignment**:
   In `core/config.mbt`, add `websocket : Bool` (default `false`).
   Add helper `pub fn Config::has_websocket_proxy(self : Config) -> Bool = self.has_proxy() && self.websocket`.
2. **Preflight Port Validation (AD-07 Part 1)**:
   In `core/config.mbt:validate_proxy_url`, parse the authority section of the URL.
   If a port is specified (e.g. `http://localhost:99999`), parse as `Int`.
   If `port < 0 || port > 65535`, raise `ConfigError::InvalidProxy("proxy URL has invalid port: ...")`.
   This ensures port 99999 fails in preflight before listening.
3. **Upgrade Capability Reflection (AD-06 & C040.02 / .03)**:
   In `Server`, add `pub fn Server::has_upgrade_capability(self : Server) -> Bool = self.config.has_websocket_proxy()`.
   - When `proxy` is None or `websocket` is false, `has_upgrade_capability()` returns `false`.
   - When `proxy` is present and `websocket` is true, it returns `true`.
4. **WebSocket Upgrade & Frame Forwarding (C040.01)**:
   In `server/server.mbt:handle_single_request`:
   When `server.config.has_websocket_proxy()` and `request.headers.get("upgrade")` is `Some("websocket")`:
   - Parse upstream proxy target and convert prefix `http://` $\to$ `ws://` (or `https://` $\to$ `wss://`).
   - Connect upstream via `@websocket.Conn::connect(target_ws_url)`.
   - If upstream connect fails (e.g. unreachable port, AD-07 Part 2):
     Respond with HTTP 502 or close client connection.
     **Crucially**: catch the exception so the server process does NOT terminate, and `server.stopped` remains `false`.
   - If upstream connect succeeds:
     Accept client upgrade via `@websocket.Conn::from_http_server(request, http_conn)` (which issues `101 Switching Protocols` with `Sec-WebSocket-Accept`).
     Spawn bidirectional forwarders in `@async.with_task_group` forwarding `recv()` to `send_text()` / `send_binary()`.
     Upon disconnection of either side, close both WebSockets and exit cleanly.
5. **No-Upgrade Enforcement (C040.02 & C040.03)**:
   If `!(server.config.has_proxy() && server.config.websocket)`, the server treats the request as a normal static GET request, returning 404 Not Found without issuing 101 Switching Protocols.

### 2.3 Logic Chain for AD-05 & C019
1. **NTFS Restriction vs. POSIX**:
   NTFS disallows `<` and `>` in file names. The original test skipped Windows entirely.
   AD-05 specifies: NUL byte test (`/%00`) and pure HTML escaping test for `<dir>` must be executed on Windows.
2. **Direct Rendering Exposure**:
   In `engine.mbt`, `escape_html` already transforms `<dir>` into `&#x3C;dir&#x3E;`.
   To enable clean blackbox assertions across packages without breaking encapsulation:
   Expose:
   ```moonbit
   pub fn render_directory_listing_html(
     title_path : String,
     entry_names : Array[(String, Bool)],
     raw_query? : String,
     host? : String = "localhost",
   ) -> String
   ```
   and `pub fn escape_html(s : String) -> String`.
3. **Assertion Invariants**:
   When rendered with title `/base/<dir>/` and entry `("<dir>", true)`:
   - `!html.contains("<dir>")` (raw tag must never appear)
   - `html.contains("&#x3C;dir&#x3E;")` (escaped HTML entity present)
   - `html.contains("Index of /base/&#x3C;dir&#x3E;/")` (escaped in title and heading)
   - `html.contains("href=\"./%3Cdir%3E/\"")` (URL-percent-encoded in href)

---

## 3. Caveats

1. **Keep-Alive Connection Lifecycle**:
   `idle_timeout_ms` must apply to each successive request on a keep-alive connection, not just the initial handshake. Wrapping `http_conn.read_request()` in the `for ;;` loop in `handle_connection` correctly resets the idle timer for each subsequent request.
2. **Task Group Early Return in WebSocket Proxying**:
   In the bidirectional forwarding task group, `group.return_immediately(())` should be called upon EOF/close of either side so the proxying scope tears down promptly without orphan background tasks.
3. **Win32 Socket Closure Latency & Handle Accounting**:
   On Windows, Winsock socket handle closure can take a few milliseconds to reflect in `GetProcessHandleCount`. Tests asserting 0 handle leaks should yield or sleep briefly (`@async.sleep(50)`) before sampling handle counts.
4. **Proxy Port Preflight vs. Host-Only URLs**:
   Some proxy URLs do not include explicit ports (e.g. `http://example.com` or `https://internal.net`). The port parser must only validate if `:` is present in the authority component.

---

## 4. Conclusion & Concrete Proposal

### 4.1 Changes for Area 1: AD-03 & C034

#### 4.1.1 `server/server.mbt`
1. Add `config : @core.Config` to `pub struct Server`:
   ```moonbit
   pub struct Server {
     inner : @socket.TcpServer
     engine : @root.StaticEngine
     config : @core.Config
     mut stopped : Bool
     mut task : @async.Task[Unit]?
     active_requests : Ref[Int]
   }
   pub fn Server::config(self : Server) -> @core.Config {
     self.config
   }
   ```
2. Pass `config` in `with_server_at`:
   ```moonbit
   let server : Server = {
     inner: listener,
     engine,
     config,
     stopped: false,
     task: None,
     active_requests: { val: 0 },
   }
   ```
3. Wrap `read_request` in `handle_single_request` with `with_timeout_opt`:
   ```moonbit
   let req_opt = if server.config.idle_timeout_ms > 0 {
     @async.with_timeout_opt(server.config.idle_timeout_ms, () => {
       http_conn.read_request()
     }) catch {
       _ => None
     }
   } else {
     try {
       Some(http_conn.read_request())
     } catch {
       _ => None
     }
   }
   let request = match req_opt {
     Some(r) => r
     None => return false
   }
   ```

#### 4.1.2 `server/c_suite_network_lifecycle_test.mbt`
Expand C034 test to cover `.01` to `.06` including `.04`:
```moonbit
async test "C034: Idle timeout configuration and request lifecycle (.01 - .06)" {
  let base_cfg = @core.Config::default("testdata/public")

  // .01: No timeout configuration (uses default 120000 ms)
  @server.with_server_at(base_cfg, 0, async fn(server) {
    assert_eq(server.config().idle_timeout_ms, 120000)
  })

  // .02: Explicit 60s creation succeeds
  let cfg_60 = { ..base_cfg, idle_timeout_ms: 60000 }
  @server.with_server_at(cfg_60, 0, async fn(server) {
    assert_eq(server.config().idle_timeout_ms, 60000)
  })

  // .03: 0 creates successfully and disables timeout
  let cfg_0 = { ..base_cfg, idle_timeout_ms: 0 }
  @server.with_server_at(cfg_0, 0, async fn(server) {
    assert_eq(server.config().idle_timeout_ms, 0)
  })

  // .04: 1000 ms idle triggers timeout and actual disconnection
  let cfg_1s = { ..base_cfg, idle_timeout_ms: 1000 }
  @server.with_server_at(cfg_1s, 0, async fn(server) {
    let port = server.port()
    let conn = @socket.Tcp::connect(@socket.Addr::new(0x7F000001, port))
    defer conn.close()
    let t0 = @async.now()
    // Do not send any data; wait for server-initiated idle disconnect
    let read_res = @async.with_timeout_opt(3500, () => conn.read_some())
    let t1 = @async.now()
    let elapsed = t1 - t0
    // read_some() returning None indicates connection closed by peer (EOF)
    assert_true(read_res is Some(None))
    assert_true(elapsed >= 900L)
  })

  // .05: Normal request with 60s timeout succeeds with 200 and non-empty body
  @server.with_server_at(cfg_60, 0, async fn(server) {
    let (status, _, body) = net_test_get(server.port(), "localhost")
    assert_eq(status, 200)
    assert_true(body.length() > 0)
  })

  // .06: Four values (30s, 120s, 300s, 0) validate and create servers
  for ms in [30000, 120000, 300000, 0] {
    let cfg = { ..base_cfg, idle_timeout_ms: ms }
    @server.with_server_at(cfg, 0, async fn(server) {
      assert_eq(server.config().idle_timeout_ms, ms)
    })
  }
}
```

---

### 4.2 Changes for Area 2: AD-07 & C040

#### 4.2.1 `core/config.mbt`
1. Add `websocket : Bool` to `Config`:
   ```moonbit
   pub(all) struct Config {
     ...
     proxy : String?
     proxy_all : String?
     proxy_options : Map[String, String]
     websocket : Bool // Enable WebSocket proxy upgrade capability (default false)
     ...
   }
   ```
2. Update `Config::default`: `websocket: false`.
3. Add helper method:
   ```moonbit
   pub fn Config::has_websocket_proxy(self : Config) -> Bool {
     self.has_proxy() && self.websocket
   }
   ```
4. Update `validate_proxy_url` with port range validation:
   ```moonbit
   pub fn validate_proxy_url(url : String) -> Unit raise ConfigError {
     if !url.has_prefix("http://") && !url.has_prefix("https://") {
       raise ConfigError::InvalidProxy(
         "proxy URL must start with http:// or https://",
       )
     }
     let prefix_len = if url.has_prefix("https://") { 8 } else { 7 }
     let rest = url[prefix_len:]
     let auth_end = match rest.find("/") {
       Some(idx) => idx
       None => match rest.find("?") {
         Some(idx) => idx
         None => rest.length()
       }
     }
     let authority = rest[:auth_end].to_owned()
     match authority.find(":") {
       Some(colon_idx) => {
         let port_str = authority[colon_idx + 1:].to_owned()
         let mut p = 0
         if port_str.length() == 0 {
           raise ConfigError::InvalidProxy("proxy URL missing port number after ':'")
         }
         for c in port_str {
           if c < '0' || c > '9' {
             raise ConfigError::InvalidProxy("proxy URL has invalid non-numeric port: " + port_str)
           }
           p = p * 10 + (c.to_int() - '0'.to_int())
           if p > 65535 {
             raise ConfigError::InvalidProxy("proxy URL port exceeds 65535: " + port_str)
           }
         }
       }
       None => ()
     }
   }
   ```

#### 4.2.2 `server/moon.pkg`
Add `"moonbitlang/async/websocket"` to imports:
```json
import {
  "unmbt/http-server-mbt" @root,
  "unmbt/http-server-mbt/core",
  "moonbitlang/async",
  "moonbitlang/async/http",
  "moonbitlang/async/socket",
  "moonbitlang/async/io",
  "moonbitlang/async/types",
  "moonbitlang/async/websocket",
}
```

#### 4.2.3 `server/server.mbt`
1. Add `has_upgrade_capability`:
   ```moonbit
   pub fn Server::has_upgrade_capability(self : Server) -> Bool {
     self.config.has_websocket_proxy()
   }
   ```
2. In `handle_single_request`, intercept WebSocket upgrade when `server.has_upgrade_capability()` is true:
   ```moonbit
   let is_ws_upgrade = match request.headers.get("upgrade") {
     Some(u) => u.to_lower() == "websocket"
     None => false
   }
   if server.has_upgrade_capability() && is_ws_upgrade {
     let proxy_target = server.config.proxy.unwrap_or("")
     let ws_upstream_url = if proxy_target.has_prefix("https://") {
       "wss://" + proxy_target[8:].to_owned() + request.path
     } else if proxy_target.has_prefix("http://") {
       "ws://" + proxy_target[7:].to_owned() + request.path
     } else {
       "ws://" + proxy_target + request.path
     }
     let upstream_opt = try {
       Some(@websocket.Conn::connect(ws_upstream_url))
     } catch {
       _ => None
     }
     match upstream_opt {
       None => {
         // Upstream unreachable: respond 502 or close without terminating main server
         let _ = try {
           http_conn..send_response(502, "Bad Gateway")..write("Upstream WebSocket unreachable").end_response()
         } catch { _ => () }
         return false
       }
       Some(upstream_ws) => {
         let client_ws_res = try {
           Ok(@websocket.Conn::from_http_server(request, http_conn))
         } catch {
           err => Err(err)
         }
         match client_ws_res {
           Err(_) => {
             upstream_ws.close()
             return false
           }
           Ok(client_ws) => {
             @async.with_task_group() <| group => {
               group.spawn_bg(no_wait=true) <| () => {
                 defer client_ws.close()
                 defer upstream_ws.close()
                 for ;; {
                   let msg = client_ws.recv() catch { _ => break }
                   match msg.kind {
                     Text => {
                       let txt = msg.read_all().text() catch { _ => break }
                       upstream_ws.send_text(txt) catch { _ => break }
                     }
                     Binary => {
                       let bin = msg.read_all().binary() catch { _ => break }
                       upstream_ws.send_binary(bin) catch { _ => break }
                     }
                   }
                 }
                 group.return_immediately(())
               }
               group.spawn_bg(no_wait=true) <| () => {
                 defer client_ws.close()
                 defer upstream_ws.close()
                 for ;; {
                   let msg = upstream_ws.recv() catch { _ => break }
                   match msg.kind {
                     Text => {
                       let txt = msg.read_all().text() catch { _ => break }
                       client_ws.send_text(txt) catch { _ => break }
                     }
                     Binary => {
                       let bin = msg.read_all().binary() catch { _ => break }
                       client_ws.send_binary(bin) catch { _ => break }
                     }
                   }
                 }
                 group.return_immediately(())
               }
             }
             return false
           }
         }
       }
     }
   }
   ```

#### 4.2.4 `server/c_suite_network_lifecycle_test.mbt`
Add comprehensive C040 `.01` to `.04` test suite:
```moonbit
async test "C040: WebSocket proxy upgrade, echo, and error handling (.01 - .04)" {
  let base_cfg = @core.Config::default("testdata/public")

  // .01: Proxy + WebSocket enabled registers upgrade capability and echoes messages
  @async.with_task_group() <| group => {
    // 1. Start target WebSocket echo server on random port
    let target_server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    let target_port = target_server.addr().port()
    group.spawn_bg(no_wait=true) <| () => {
      target_server.run_forever() <| ((req, _, conn) => {
        let ws = @websocket.from_http_server(req, conn)
        defer ws.close()
        for ;; {
          let msg = ws.recv() catch { _ => break }
          match msg.kind {
            Text => {
              let t = msg.read_all().text() catch { _ => break }
              ws.send_text("Echo: " + t) catch { _ => break }
            }
            Binary => {
              let b = msg.read_all().binary() catch { _ => break }
              ws.send_binary(b) catch { _ => break }
            }
          }
        }
      })
    }

    // 2. Start proxy http-server with proxy and websocket enabled
    let proxy_cfg : @core.Config = {
      ..base_cfg,
      proxy: Some("http://127.0.0.1:\{target_port}"),
      websocket: true,
    }
    @server.with_server_at(proxy_cfg, 0, async fn(server) {
      assert_true(server.has_upgrade_capability())
      let proxy_port = server.port()

      // 3. Connect client via WebSocket to proxy
      let client_ws = @websocket.Conn::connect("ws://127.0.0.1:\{proxy_port}/ws")
      defer client_ws.close()

      // 4. Send "Hello WebSocket!" and receive "Echo: Hello WebSocket!"
      client_ws.send_text("Hello WebSocket!")
      let resp = client_ws.recv()
      assert_eq(resp.read_all().text(), "Echo: Hello WebSocket!")
      client_ws.send_close()
    })
    target_server.close()
    group.return_immediately(())
  }

  // .02: No proxy configured -> no upgrade capability (.listeners('upgrade').length == 0)
  let cfg_no_proxy : @core.Config = { ..base_cfg, proxy: None, websocket: true }
  @server.with_server_at(cfg_no_proxy, 0, async fn(server) {
    assert_false(server.has_upgrade_capability())
    // Attempting upgrade fails with 404 (not upgraded)
    let ws_attempt = try {
      Some(@websocket.Conn::connect("ws://127.0.0.1:\{server.port()}/ws"))
    } catch {
      _ => None
    }
    assert_true(ws_attempt is None)
  })

  // .03: WebSocket option not set -> no upgrade capability
  let cfg_no_ws : @core.Config = {
    ..base_cfg,
    proxy: Some("http://127.0.0.1:3000"),
    websocket: false,
  }
  @server.with_server_at(cfg_no_ws, 0, async fn(server) {
    assert_false(server.has_upgrade_capability())
    let ws_attempt = try {
      Some(@websocket.Conn::connect("ws://127.0.0.1:\{server.port()}/ws"))
    } catch {
      _ => None
    }
    assert_true(ws_attempt is None)
  })

  // .04: Error handling per AD-07:
  // Part A: Illegal port (99999) fails in preflight before listening
  let bad_port_cfg : @core.Config = {
    ..base_cfg,
    proxy: Some("http://localhost:99999"),
    websocket: true,
  }
  let preflight_failed = try {
    @core.validate_config(bad_port_cfg)
    false
  } catch {
    _ => true
  }
  assert_true(preflight_failed)

  // Part B: Legal but unreachable port runs, client gets error/close, main server survives
  let unreachable_port = 59876
  let unreachable_cfg : @core.Config = {
    ..base_cfg,
    proxy: Some("http://127.0.0.1:\{unreachable_port}"),
    websocket: true,
  }
  @server.with_server_at(unreachable_cfg, 0, async fn(server) {
    assert_true(server.has_upgrade_capability())
    let port = server.port()
    let ws_attempt = try {
      Some(@websocket.Conn::connect("ws://127.0.0.1:\{port}/ws"))
    } catch {
      _ => None
    }
    assert_true(ws_attempt is None)

    // Verify main server survives: standard HTTP GET still succeeds with 200 OK
    let (status, _, body) = net_test_get(port, "localhost")
    assert_eq(status, 200)
    assert_eq(@utf8.decode_lossy(body), "hello moonbit\n")
  })
}
```

---

### 4.3 Changes for Area 3: AD-05 & C019

#### 4.3.1 `engine.mbt`
Make `escape_html` public and expose `render_directory_listing_html`:
```moonbit
///|
/// Escape characters for safe HTML rendering.
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

///|
/// Pure HTML directory listing renderer for testing and embedding (AD-05).
pub fn render_directory_listing_html(
  title_path : String,
  entry_names : Array[(String, Bool)],
  raw_query? : String,
  host? : String = "localhost",
) -> String {
  let entries : Array[ListingEntry] = []
  for item in entry_names {
    let (name, is_dir) = item
    entries.push({
      name,
      is_dir,
      size: 0L,
      mtime_sec: 0L,
      is_companion: false,
      has_br: false,
      has_gz: false,
    })
  }
  render_directory_html(title_path, entries, raw_query, host)
}
```

#### 4.3.2 `server/c_suite_directory_security_test.mbt`
In test `"C017 ~ C021: Path handling, ENOTDIR, escaping, and malformed encoding"` (around line 147):
```moonbit
    // C019: Pathname encoding safety with NUL byte (%00)
    let (s_nul, _, _) = dirsec_get(port, "/%00hello.txt")
    assert_true(s_nul == 403 || s_nul == 400 || s_nul == 404)

    // C019: Pure HTML directory listing escaping for `<dir>` per AD-05
    // On Windows NTFS, creating `<dir>` folder fails at filesystem level.
    // Per AD-05, pure HTML escaping is verified on all three platforms:
    let html = @root.render_directory_listing_html(
      "/base/<dir>/",
      [("<dir>", true), ("<script>.txt", false)],
      raw_query=None,
    )
    assert_true(!html.contains("<dir>"))
    assert_true(!html.contains("<script>"))
    assert_true(html.contains("&#x3C;dir&#x3E;"))
    assert_true(html.contains("&#x3C;script&#x3E;"))
    assert_true(html.contains("Index of /base/&#x3C;dir&#x3E;/"))
    assert_true(html.contains("href=\"./%3Cdir%3E/\""))
```

---

## 5. Verification Method

Once implemented by worker, independently verify as follows:

1. **Compilation Check**:
   ```powershell
   moon check --target native
   ```
   *Expectation*: 0 errors, 0 warnings.

2. **Run C_Suite Tests**:
   ```powershell
   moon test --target native -p unmbt/http-server-mbt/server -f c_suite_network_lifecycle_test.mbt
   moon test --target native -p unmbt/http-server-mbt/server -f c_suite_directory_security_test.mbt
   ```
   *Expectation*: All tests in both files PASS, including C034 (.01-.06), C040 (.01-.04), and C019 pure HTML escaping.

3. **Update Interface Files and Format**:
   ```powershell
   moon info --target native
   moon fmt
   git status --short
   ```
   *Expectation*: `.mbti` files updated with new public items (`websocket`, `has_websocket_proxy`, `has_upgrade_capability`, `render_directory_listing_html`, `escape_html`), no formatting diffs.

4. **Full Test Suite Run**:
   ```powershell
   moon test --target native
   ```
