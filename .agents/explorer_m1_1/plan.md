# Milestone 1 Implementation Plan: Server Transport Decoupling from TLS

**Document**: `plan.md`  
**Working Directory**: `E:\project\moonbit\unmbt\http-server-mbt\.agents\explorer_m1_1`  
**Target Package**: `unmbt/http-server-mbt/server`  
**Date**: 2026-09-18  
**Author**: Server Transport Explorer (`explorer_m1_1`)  
**Parent Orchestrator**: `4e28988c-0fb8-4c25-808e-968dbd1ae0f2`  
**Status**: Ready for Implementation  

---

## 1. Context & Objectives

The `http-server-mbt` project is transitioning to a **layered architecture** supporting dual packaging:
- **`min`**: Lightweight static file HTTP server, with **zero crypto dependencies** and zero compilation of the 109 vendored MbedTLS C source files.
- **`full`**: Complete distribution supporting HTTPS (via MbedTLS) and reverse proxy routing.

Currently, `server/moon.pkg` directly imports `"unmbt/http-server-mbt/tls"`. Because of this single import:
- Every build and test of `server` compiles and links `libtls.lib` (~6.17 MB across 112 object files), even though the compiled server itself is only ~33 KB.
- `cmd/http-server-mbt` transitively pulls in all MbedTLS objects.
- A minimal zero-crypto C library or CLI binary cannot be built.

### Objectives of Milestone 1
1. Decouple `unmbt/http-server-mbt/server` completely from `unmbt/http-server-mbt/tls`.
2. Introduce abstract `Transport` struct and `Acceptor` trait in `server/server.mbt`.
3. Provide built-in `PlainAcceptor` for standard TCP connections.
4. Unify connection processing in `handle_client` consuming `Transport` uniformly.
5. Retain kernel zero-copy `TransmitFile` when `raw_fd` is present, gracefully degrading to 64 KB bounded buffer streaming when absent (e.g. for TLS or virtual transports).
6. Ensure all 183 existing tests continue to pass 100% with zero regressions.

---

## 2. Exhaustive Audit of `@tls` in `server/server.mbt`

Every single occurrence of `@tls` in the `server` package is localized to `server/server.mbt`. No test file, native C file, or auxiliary `.mbt` file in `server/` references `tls`.

| Line Range in `server.mbt` | Current Code / Usage | Problem / Coupling | Target Action |
|---|---|---|---|
| **Line 7** | `tls_acceptor : @tls.TlsAcceptor?` | `Server` struct holds direct reference to MbedTLS acceptor | Replace with `acceptor : &Acceptor` |
| **Lines 38–71** | `async fn build_tls_acceptor(config : @core.Config) -> @tls.TlsAcceptor` | Directly reads cert/key files and calls `@tls.TlsAcceptor::new_server` | Remove from `server/server.mbt`; relocate to integration package `full` |
| **Lines 65–66** | `@tls.TlsAcceptor::new_server(cert, key, ...)` | Instantiates MbedTLS context | Relocate to `full` |
| **Lines 80–97** | `fn tls_preflight_error(err : Error) -> @core.ConfigError` | Pattern matches against `@tls.TlsError::TlsError` variants | Relocate to `full` |
| **Lines 110–118** | Acceptor setup in `with_server_at`: `let tls_acceptor : @tls.TlsAcceptor? = ...` | Hard-wires TLS acceptor construction into plaintext server startup | Accept optional `acceptor? : &Acceptor`; default to `PlainAcceptor::new()`. If omitted and `config.has_tls()` is true, raise `@core.ConfigError::InvalidTls` |
| **Lines 203–206** | `priv enum Transport { Plain(@socket.Tcp), Encrypted(@tls.TlsConn) }` | Enum directly holds `@tls.TlsConn` | Replace with `pub struct Transport` holding `&@io.Reader`, `&@io.Writer`, `raw_fd`, `raw_tcp`, `close_fn` |
| **Lines 211–228** | `async fn Transport::send` | Branches on `Plain(tcp)` vs `Encrypted(conn)` | Replaced by `self.writer.write(data)` |
| **Lines 444–475** | `handle_tls_single_request` | Dedicated TLS request handler using `HttpReader` | Generalized into `handle_stream_single_request` |
| **Lines 478–518** | `handle_connection` | Branches on `match server.tls_acceptor { Some(acc) => ..., None => ... }` | Replaced by `server.acceptor.accept(tcp_conn)` returning `Transport`, delegated to `handle_client` |
| **Lines 598–601** | `send_file_region` | `match transport { Plain(tcp) => transmit_file(tcp.fd(), ...), Encrypted(_) => -1 }` | Replaced by `match transport.raw_fd { Some(fd) => transmit_file(fd, ...), None => -1 }` |

---

## 3. Detailed Architecture & Interface Design

### 3.1 `Transport` Struct

```moonbit
///|
/// A bidirectional stream connection with optional raw socket handles
/// for platform zero-copy acceleration and protocol upgrade.
pub struct Transport {
  reader : &@io.Reader
  writer : &@io.Writer
  raw_fd : @types.Fd?
  raw_tcp : @socket.Tcp?
  close_fn : () -> Unit
}

///|
/// Create a plain TCP transport with Win32 TransmitFile / sendfile zero-copy capability.
pub fn Transport::plain(tcp : @socket.Tcp) -> Transport {
  {
    reader: tcp,
    writer: tcp,
    raw_fd: Some(tcp.fd()),
    raw_tcp: Some(tcp),
    close_fn: fn() { tcp.close() },
  }
}

///|
/// Create a custom or encrypted transport (TLS, proxy stream, memory buffer).
/// Zero-copy TransmitFile is automatically bypassed, taking the bounded-buffer path.
pub fn Transport::custom(
  reader : &@io.Reader,
  writer : &@io.Writer,
  raw_fd? : @types.Fd,
  raw_tcp? : @socket.Tcp,
  close_fn : () -> Unit,
) -> Transport {
  {
    reader,
    writer,
    raw_fd,
    raw_tcp,
    close_fn,
  }
}

///|
/// Close the transport resources via its registered close callback.
pub fn Transport::close(self : Transport) -> Unit {
  (self.close_fn)()
}

///|
/// Write a data chunk to the transport writer.
pub async fn Transport::send(self : Transport, data : &@io.Data) -> Bool {
  try {
    self.writer.write(data)
    true
  } catch {
    _ => false
  }
}
```

### 3.2 `Acceptor` Trait & `PlainAcceptor`

```moonbit
///|
/// An acceptor upgrades an accepted TCP socket into an active Transport.
/// Plain TCP passes through directly; TLS performs handshake; Proxy intercepts.
pub(open) trait Acceptor {
  async fn accept(Self, @socket.Tcp) -> Transport raise Error
  fn close(Self) -> Unit
}

///|
/// Built-in plaintext acceptor: wraps raw TCP sockets directly into Transport.
pub struct PlainAcceptor {}

///|
pub fn PlainAcceptor::new() -> PlainAcceptor {
  {}
}

///|
pub impl Acceptor for PlainAcceptor with accept(_self, tcp) {
  Transport::plain(tcp)
}

///|
pub impl Acceptor for PlainAcceptor with close(_self) {
  ()
}
```

### 3.3 Updated `Server` Struct

```moonbit
///|
/// A library-managed HTTP server for static files.
pub struct Server {
  inner : @socket.TcpServer
  engine : @root.StaticEngine
  config : @core.Config
  acceptor : &Acceptor
  mut stopped : Bool
  mut task : @async.Task[Unit]?
  active_requests : Ref[Int]
}
```

### 3.4 Updated `with_server_at` & `with_server`

```moonbit
///|
/// Start a server on an explicit TCP port with optional acceptor injection.
/// When acceptor is omitted:
/// - Plain static HTTP server is used by default.
/// - If config.has_tls() is true, raises ConfigError::InvalidTls immediately (D-01 preflight).
pub async fn with_server_at(
  config : @core.Config,
  port : Int,
  acceptor? : &Acceptor,
  action : async (Server) -> Unit,
) -> Unit {
  @core.validate_tls(config)
  let effective_acceptor : &Acceptor = match acceptor {
    Some(acc) => acc
    None => {
      if config.has_tls() {
        raise @core.ConfigError::InvalidTls(
          "TLS is not supported in this server build: use full build or inject a TlsAcceptor",
        )
      }
      PlainAcceptor::new()
    }
  }
  defer effective_acceptor.close()
  let engine = @root.StaticEngine::new(config)
  let listener = @socket.TcpServer(@socket.Addr::new(0, port), reuse_addr=true)
  let server : Server = {
    inner: listener,
    engine,
    config,
    acceptor: effective_acceptor,
    stopped: false,
    task: None,
    active_requests: { val: 0 },
  }
  defer listener.close()
  @async.with_task_group() <| group => {
    let server_task = group.spawn(allow_failure=true, () => {
      listener.run_forever((tcp_conn, _addr) => {
        handle_connection(server, tcp_conn)
      })
    })
    server.task = Some(server_task)
    defer {
      server.stop()
      server_task.cancel()
    }
    let action_res = Ok(action(server)) catch { err => Err(err) }
    server.stop_and_drain()
    server_task.cancel()
    match action_res {
      Ok(_) => ()
      Err(err) => raise err
    }
  }
}

///|
/// Start a server with default port 8080.
pub async fn with_server(
  config : @core.Config,
  acceptor? : &Acceptor,
  action : async (Server) -> Unit,
) -> Unit {
  match acceptor {
    Some(acc) => with_server_at(config, 8080, acceptor=acc, action)
    None => with_server_at(config, 8080, action)
  }
}
```

### 3.5 Connection Handling & Uniform `handle_client`

```moonbit
///|
async fn handle_connection(server : Server, tcp_conn : @socket.Tcp) -> Unit {
  defer tcp_conn.close()
  let transport = try {
    server.acceptor.accept(tcp_conn)
  } catch {
    _ => return // handshake failed or connection closed: socket cleaned up by defer
  }
  defer transport.close()
  handle_client(server, transport)
}

///|
/// Uniformly handle an accepted client transport connection.
async fn handle_client(server : Server, transport : Transport) -> Unit {
  match transport.raw_tcp {
    Some(tcp) => {
      // Plain TCP path: leverages ServerConnection for WebSocket upgrade (C040)
      let http_conn = @http.ServerConnection::new(tcp)
      for ;; {
        if server.stopped {
          break
        }
        let keep_going = handle_single_request(server, transport, http_conn) catch {
          _ => false
        }
        if !keep_going {
          break
        }
      }
    }
    None => {
      // Stream path (TLS, virtual stream, proxy): uses HttpReader
      let reader = HttpReader::new(transport.reader)
      for ;; {
        if server.stopped {
          break
        }
        let keep_going = handle_stream_single_request(server, transport, reader) catch {
          _ => false
        }
        if !keep_going {
          break
        }
      }
    }
  }
}

///|
/// Stream-path request handling: operates over generic `HttpReader`.
async fn handle_stream_single_request(
  server : Server,
  transport : Transport,
  reader : HttpReader,
) -> Bool {
  let req_opt = if server.config.idle_timeout_ms > 0 {
    @async.with_timeout_opt(server.config.idle_timeout_ms, () => {
      reader.read_request()
    }) catch {
      _ => None
    }
  } else {
    Some(reader.read_request()) catch {
      _ => None
    }
  }
  let request = match req_opt {
    Some(r) => r
    None => return false
  }
  server.active_requests.val += 1
  defer {
    server.active_requests.val = server.active_requests.val - 1
  }
  dispatch_engine_request(
    server,
    transport,
    map_request_method(request.meth),
    lower_headers(request.headers),
    request.path,
  )
}
```

### 3.6 TransmitFile Kernel Zero-Copy & Fallback in `send_file_region`

```moonbit
///|
async fn send_file_region(
  transport : Transport,
  response : @root.Response,
  path : String,
  offset : Int64,
  length : Int64,
) -> Bool {
  if length <= 0L {
    return true
  }
  // Zero-copy TransmitFile runs when a raw socket FD is available.
  // TLS and virtual transports have raw_fd == None, returning -1 to take bounded buffer.
  let ret = match transport.raw_fd {
    Some(fd) => transmit_file(fd, path, offset, length)
    None => -1
  }
  if ret == 0 {
    return true
  }
  if ret == -2 {
    // Client disconnected
    return false
  }
  if ret == -3 {
    // D-17: File modified or truncated during transfer (FILE_CHANGED)
    return false
  }
  // Fallback: bounded 64KB chunk streaming
  send_file_region_bounded_buffer(transport, response, length)
}
```

`server/transmit_file.mbt` remains **100% untouched**. Its signature:
`pub async fn transmit_file(sock : @types.Fd, path : String, offset : Int64, length : Int64) -> Int`
accepts `@types.Fd`, which is precisely `transport.raw_fd`.

---

## 4. Manifest Cleanup (`server/moon.pkg`)

### Change in `server/moon.pkg`
Delete line 4:
```diff
--- a/server/moon.pkg
+++ b/server/moon.pkg
@@ -1,7 +1,6 @@
 import {
   "unmbt/http-server-mbt" @root,
   "unmbt/http-server-mbt/core",
-  "unmbt/http-server-mbt/tls",
   "moonbitlang/async",
   "moonbitlang/async/http",
   "moonbitlang/async/socket",
```

Additionally, to eliminate compiler warnings identified during `moon check`, add `"moonbitlang/core/cmp"` and `"moonbitlang/core/string"`:
```diff
+  "moonbitlang/core/cmp",
+  "moonbitlang/core/string",
```

---

## 5. Integration Package `full` (for TLS Injected Builds)

When TLS functionality is needed, it is supplied by an integration package (e.g. `unmbt/http-server-mbt/full`):

### `full/moon.pkg`
```moonbit
import {
  "unmbt/http-server-mbt/server",
  "unmbt/http-server-mbt/tls",
  "unmbt/http-server-mbt/core",
  "moonbitlang/async",
  "moonbitlang/async/fs",
  "moonbitlang/core/encoding/utf8",
}
```

### `full/full.mbt`
```moonbit
///|
pub struct TlsServerAcceptor {
  tls_acc : @tls.TlsAcceptor
}

///|
pub fn TlsServerAcceptor::new(tls_acc : @tls.TlsAcceptor) -> TlsServerAcceptor {
  { tls_acc }
}

///|
pub impl @server.Acceptor for TlsServerAcceptor with accept(self, tcp) {
  let conn = self.tls_acc.accept(reader=tcp, writer=tcp)
  @server.Transport::custom(
    conn,
    conn,
    close_fn=fn() {
      conn.close()
      tcp.close()
    },
  )
}

///|
pub impl @server.Acceptor for TlsServerAcceptor with close(self) {
  self.tls_acc.close()
}

///|
pub async fn build_tls_acceptor(config : @core.Config) -> @tls.TlsAcceptor {
  let cert_path = match config.cert_file {
    Some(p) => p
    None => ""
  }
  let key_path = match config.key_file {
    Some(p) => p
    None => ""
  }
  let cert = @fs.read_file(cert_path).binary() catch {
    err =>
      raise @core.ConfigError::InvalidTls(
        "cannot read cert_file \{cert_path}: \{err}",
      )
  }
  let key = @fs.read_file(key_path).binary() catch {
    err =>
      raise @core.ConfigError::InvalidTls(
        "cannot read key_file \{key_path}: \{err}",
      )
  }
  let passphrase = match config.key_passphrase {
    Some(p) => Some(@utf8.encode(p))
    None => None
  }
  try {
    match passphrase {
      Some(pass) => @tls.TlsAcceptor::new_server(cert, key, passphrase=pass)
      None => @tls.TlsAcceptor::new_server(cert, key)
    }
  } catch {
    err => raise tls_preflight_error(err)
  }
}

///|
fn tls_preflight_error(err : Error) -> @core.ConfigError {
  match err {
    @tls.TlsError::TlsError(code=-15232, ..) =>
      @core.ConfigError::InvalidTls(
        "key passphrase mismatch (check --key-passphrase)",
      )
    @tls.TlsError::TlsError(code=-15360, ..) =>
      @core.ConfigError::InvalidTls(
        "key is encrypted: --key-passphrase is required",
      )
    @tls.TlsError::TlsError(code=-15616, ..) =>
      @core.ConfigError::InvalidTls(
        "key parse failed: wrong key file or wrong passphrase",
      )
    @tls.TlsError::TlsError(code~, message~) =>
      @core.ConfigError::InvalidTls("\{message} (mbedtls \{code})")
    _ => @core.ConfigError::InvalidTls("\{err}")
  }
}

///|
pub async fn with_full_server_at(
  config : @core.Config,
  port : Int,
  action : async (@server.Server) -> Unit,
) -> Unit {
  let acceptor : &@server.Acceptor = if config.has_tls() {
    let tls_acc = build_tls_acceptor(config)
    TlsServerAcceptor::new(tls_acc)
  } else {
    @server.PlainAcceptor::new()
  }
  @server.with_server_at(config, port, acceptor=acceptor, action)
}
```

---

## 6. Verification & Quality Gates

The implementer must run these commands sequentially to guarantee zero regressions:

1. **Static Type Checking**:
   ```bash
   moon check --target native
   ```
   *Expected*: 0 errors.

2. **Full Test Suite Execution**:
   ```bash
   moon test --target native
   ```
   *Expected*: 183 tests total, 183 passed, 0 failed. All 75 tests in `server/` pass without MbedTLS linkage.

3. **Interface Update & Diff Check**:
   ```bash
   moon info --target native
   ```
   *Expected*: `server/pkg.generated.mbti` removes `@tls.TlsAcceptor`, adding `Transport`, `Acceptor`, and `PlainAcceptor`.

4. **Code Formatting**:
   ```bash
   moon fmt
   ```

---

## 7. Summary of Deliverables & File Changes

| File | Nature of Change | Key Changes |
|---|---|---|
| `server/moon.pkg` | Dependency removal | Remove `"unmbt/http-server-mbt/tls"` |
| `server/server.mbt` | Refactor | Add `Transport`, `Acceptor`, `PlainAcceptor`, `handle_client`; update `with_server_at` and `send_file_region`; remove `build_tls_acceptor`, `tls_preflight_error`, `@tls` enum |
| `server/transmit_file.mbt` | **No change** | Reused as-is; `raw_fd` maps cleanly to `sock : @types.Fd` |
| `server/*_test.mbt` | **No change** | All 75 tests continue to pass without modification |
| `tls/` | **No change** | All 5 loopback tests pass in isolation |
