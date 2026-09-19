# Milestone 1: TLS Dependency Injection & Full Server Integration Plan

**Author**: TLS Injection Explorer (`explorer_m1_2`)  
**Date**: 2026-09-18  
**Scope**: `unmbt/http-server-mbt/server`, `unmbt/http-server-mbt/tls`, and new integration package `unmbt/http-server-mbt/full`  
**Parent Task**: Milestone 1 of `min` & `full` layered packaging, TLS decoupling, and Proxy readiness  

---

## 1. Executive Summary & Objectives

The goal of Milestone 1 is to decouple the core HTTP server (`server`) from the TLS engine (`tls`), allowing `server` to compile with zero cryptographic dependencies, zero MbedTLS C source files, and a compiled archive size reduction from 6.2 MB to ~33 KB.

This plan details:
1. The exact transport and acceptor abstraction in `server` (`Transport`, `Acceptor`, `PlainAcceptor`).
2. The location and design of the TLS integration layer (`full/` package).
3. The dependency injection mechanism: how `full` constructs `TlsAcceptor` from `config` and injects it into `server.with_server_at(config, port, acceptor=..., action)`.
4. The preflight configuration validation mechanism: in `min` mode (when no acceptor is supplied), if `config.has_tls()` is true, `server.with_server_at` immediately raises `@core.ConfigError::InvalidTls("TLS is not supported in min build; use full build")` before binding or listening.
5. The step-by-step implementation guide ensuring zero regression across all 183 existing test cases.

---

## 2. Examination of Existing TLS Components

### 2.1 `tls/acceptor.mbt`
- **File path**: `E:\project\moonbit\unmbt\http-server-mbt\tls\acceptor.mbt`
- **Primary Type**: `pub struct TlsAcceptor { handle : Int64, obj : AcceptorObj, mut closed : Bool }`
- **Key Methods**:
  - `TlsAcceptor::new_server(cert_pem : Bytes, key_pem : Bytes, passphrase? : Bytes) -> TlsAcceptor raise TlsError`:
    - Calls `tls_global_init()` (initializes PSA crypto subsystem).
    - Bridges to `tls_acceptor_new_server_c` with NUL-terminated certificate and key buffers.
    - Returns an initialized server acceptor handle.
  - `TlsAcceptor::new_client(ca? : Bytes, insecure? : Bool = false) -> TlsAcceptor raise TlsError`:
    - Creates a client TLS acceptor for upstream verification.
  - `TlsAcceptor::close(self : TlsAcceptor) -> Unit`:
    - Releases underlying MbedTLS configuration state (idempotent).
  - `tls_acceptor_count() -> Int`:
    - Diagnostic probe for handle and resource leak testing.

### 2.2 `tls/conn.mbt`
- **File path**: `E:\project\moonbit\unmbt\http-server-mbt\tls\conn.mbt`
- **Primary Type**: `pub struct TlsConn` (implements `@io.Reader` and `@io.Writer`).
- **Connection Bridge**:
  - `TlsAcceptor::accept(self : TlsAcceptor, reader~ : &@io.Reader, writer~ : &@io.Writer) -> TlsConn`:
    - Asynchronous handshake (`conn.handshake()`).
    - Feeds ciphertext from `reader` into MbedTLS input ring (`feed_input()`), drains ciphertext from bridge output ring to `writer` (`drain_output()`).
    - Handshake failure raises `TlsError` or `TlsUnexpectedEof`.
  - `TlsConn::close(self : TlsConn) -> Unit`:
    - Releases MbedTLS connection state.
  - `TlsConn::shutdown(self : TlsConn) -> Bool`:
    - Sends clean TLS `close_notify`.
- **Key Insight**: `TlsConn` is a purely virtual streaming transport over generic `&@io.Reader` and `&@io.Writer`. It does **not** expose a raw OS socket file descriptor (`raw_fd`). Therefore, platform zero-copy (`TransmitFile` / `sendfile`) cannot operate on TLS streams; TLS streams must always use the bounded-buffer transfer path (D-05 / T-017).

### 2.3 Existing Coupling in `server/server.mbt`
In the current implementation, `server/server.mbt` directly imports `unmbt/http-server-mbt/tls` and references it across 10 sites:
1. Line 7: `tls_acceptor : @tls.TlsAcceptor?` in `Server` struct.
2. Lines 38–71: `build_tls_acceptor(config : @core.Config) -> @tls.TlsAcceptor` reads cert/key files and calls `@tls.TlsAcceptor::new_server`.
3. Lines 80–97: `tls_preflight_error(err : Error) -> @core.ConfigError` maps MbedTLS error codes (-15232, -15360, -15616) to `@core.ConfigError::InvalidTls`.
4. Lines 110–118: `with_server_at` conditionally creates `build_tls_acceptor(config)`.
5. Lines 203–206: `priv enum Transport { Plain(@socket.Tcp); Encrypted(@tls.TlsConn) }`.
6. Lines 220–226: `Transport::send` branches on `Encrypted(conn)`.
7. Lines 444–475: `handle_tls_single_request` uses `reader : HttpReader`.
8. Lines 480–501: `handle_connection` matches `server.tls_acceptor`: `Some(acceptor) => ... | None => ...`.
9. Lines 598–601: `send_file_region` matches `Plain(tcp) => transmit_file(...) | Encrypted(_) => -1`.
10. `server/moon.pkg` line 4: `"unmbt/http-server-mbt/tls"`.

---

## 3. Architecture of the Integration Layer

### 3.1 Evaluation of Placement Options

| Option | Candidate Location | Architectural Evaluation | Verdict |
| :--- | :--- | :--- | :--- |
| **Option A** | Inside `tls/` (e.g. `tls/server_acceptor.mbt`) | Would require `tls` to import `server`. This violates Dependency Inversion. When reverse proxy (T-013) needs upstream TLS client connections in `server`, having `tls` depend on `server` would create a **circular package dependency** (`server` ↔ `tls`). | **REJECTED** |
| **Option B** | Inside new package `full/` (`unmbt/http-server-mbt/full`) | Clean composition root. `server` has 0 crypto dependencies; `tls` is a reusable standalone TLS library; `full` combines them. Fits standard layered architecture. Matches `PROJECT.md` line 7 & 113. | **RECOMMENDED & ACCEPTED** |
| **Option C** | Subpackage `server/full/` | Valid MoonBit subpackage, but creates deeper hierarchy and separates CLI/ABI symmetry (`cmd/http-server-min` vs `cmd/http-server-full`, `min` DLL vs `full` DLL). | Less idiomatic than Option B |

**Decision**: The TLS acceptor implementation and server integration will live in a new top-level package: `unmbt/http-server-mbt/full` (directory `full/`).

### 3.2 Target Package Dependency Graph

```
                   ┌────────────────────────────────┐
                   │  unmbt/http-server-mbt/core    │  (Config, Types, Errors, MIME)
                   │  0 external deps, 0 crypto     │
                   └───────▲────────────────▲───────┘
                           │                │
          ┌────────────────┴──────┐         │
          │ unmbt/http-server-mbt │         │
          │ (StaticEngine, leases)│         │
          └───────────▲───────────┘         │
                      │                     │
┌─────────────────────┴─────────────────────┴┐       ┌──────────────────────────────┐
│        unmbt/http-server-mbt/server        │       │  unmbt/http-server-mbt/tls   │
│  - Transport & Acceptor abstractions       │       │  - MbedTLS 4.2.0 + TF-PSA    │
│  - PlainAcceptor (TransmitFile zero-copy)  │       │  - TlsAcceptor & TlsConn     │
│  - 0 crypto dependencies, ~33 KB archive   │       │  - Standalone TLS library    │
└─────────────────────▲──────────────────────┘       └──────────────▲───────────────┘
                      │                                             │
                      └──────────────────────┬──────────────────────┘
                                             │
                             ┌───────────────┴────────────────┐
                             │   unmbt/http-server-mbt/full   │
                             │   - TlsServerAcceptor          │
                             │   - with_server_at (HTTPS)     │
                             │   - Preflight file validation  │
                             └───────────────▲────────────────┘
                                             │
                             ┌───────────────┴────────────────┐
                             │ cmd/http-server-full / CABI    │
                             └────────────────────────────────┘
```

---

## 4. Detailed Design & Interface Contracts

### 4.1 `server` Package Changes

#### 4.1.1 `server/moon.pkg`
Remove `"unmbt/http-server-mbt/tls"`.
The new `server/moon.pkg` imports only:
```json
{
  "import": [
    "unmbt/http-server-mbt" as root,
    "unmbt/http-server-mbt/core",
    "moonbitlang/async",
    "moonbitlang/async/http",
    "moonbitlang/async/socket",
    "moonbitlang/async/io",
    "moonbitlang/async/types",
    "moonbitlang/async/websocket",
    "moonbitlang/async/fs",
    "moonbitlang/core/encoding/utf8"
  ],
  "native-stub": [
    "transmit_file_windows.c",
    "transmit_file_linux.c",
    "transmit_file_darwin.c"
  ],
  "targets": { "*.mbt": [ "native" ] }
}
```

#### 4.1.2 Transport Abstraction (`server/transport.mbt`)
Create `server/transport.mbt`:
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
  close_fn : () -> Unit,
) -> Transport {
  {
    reader,
    writer,
    raw_fd: None,
    raw_tcp: None,
    close_fn,
  }
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

#### 4.1.3 Acceptor Abstraction (`server/acceptor.mbt`)
Create `server/acceptor.mbt`:
```moonbit
///|
/// An acceptor upgrades an accepted TCP socket into an active Transport.
/// Plain TCP passes through directly; TLS performs handshake; Proxy intercepts.
pub(open) trait Acceptor {
  async fn accept(Self, @socket.Tcp) -> Transport
  fn close(Self) -> Unit
}

///|
/// Default plaintext acceptor: passes raw TCP sockets directly into Transport.
pub struct PlainAcceptor {}

///|
pub impl Acceptor for PlainAcceptor with accept(_self, tcp) {
  Transport::plain(tcp)
}

///|
pub impl Acceptor for PlainAcceptor with close(_self) {
  ()
}
```

#### 4.1.4 Updates in `server/server.mbt`
1. **`Server` Struct**:
   ```moonbit
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
2. **`with_server_at` and Preflight Validation**:
   ```moonbit
   ///|
   /// Start a server on an explicit TCP port with optional acceptor injection.
   ///
   /// Preflight validation contract:
   /// - If acceptor is omitted (None):
   ///   - If config.has_tls() is true, immediately raises
   ///     ConfigError::InvalidTls("TLS is not supported in min build; use full build")
   ///     BEFORE binding or listening.
   ///   - Otherwise uses PlainAcceptor with kernel zero-copy.
   /// - If acceptor is provided (Some(acc)), uses the injected acceptor.
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
             "TLS is not supported in min build; use full build",
           )
         }
         &PlainAcceptor {}
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
   ```
3. **`handle_connection`**:
   Handles connection using `server.acceptor`:
   ```moonbit
   async fn handle_connection(server : Server, tcp_conn : @socket.Tcp) -> Unit {
     let transport_res = Ok(server.acceptor.accept(tcp_conn)) catch {
       _ => {
         tcp_conn.close()
         return
       }
     }
     let transport = match transport_res {
       Ok(t) => t
       Err(_) => {
         tcp_conn.close()
         return
       }
     }
     defer (transport.close_fn)()

     match transport.raw_tcp {
       Some(tcp) => {
         // Plain TCP path: uses @http.ServerConnection (supports WebSocket C040)
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
         // Encrypted / Virtual path: uses HttpReader over transport.reader
         let reader = HttpReader::new(transport.reader)
         for ;; {
           if server.stopped {
             break
           }
           let keep_going = handle_tls_single_request(server, transport, reader) catch {
             _ => false
           }
           if !keep_going {
             break
           }
         }
       }
     }
   }
   ```
4. **`send_file_region`**:
   Checks `transport.raw_fd`:
   ```moonbit
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
     let ret = match transport.raw_fd {
       Some(fd) => transmit_file(fd, path, offset, length)
       None => -1
     }
     if ret == 0 {
       return true
     }
     if ret == -2 {
       return false
     }
     if ret == -3 {
       return false
     }
     send_file_region_bounded_buffer(transport, response, length)
   }
   ```

---

### 4.2 `full` Package Design

#### 4.2.1 `full/moon.pkg`
Create `full/moon.pkg`:
```json
{
  "import": [
    "unmbt/http-server-mbt" as root,
    "unmbt/http-server-mbt/core",
    "unmbt/http-server-mbt/server",
    "unmbt/http-server-mbt/tls",
    "moonbitlang/async",
    "moonbitlang/async/io",
    "moonbitlang/async/socket",
    "moonbitlang/async/fs",
    "moonbitlang/core/encoding/utf8"
  ],
  "targets": { "*.mbt": [ "native" ] }
}
```

#### 4.2.2 `full/tls_acceptor.mbt`
Create `full/tls_acceptor.mbt`:
```moonbit
///|
/// A TLS acceptor implementing @server.Acceptor by wrapping @tls.TlsAcceptor.
pub struct TlsServerAcceptor {
  tls_acceptor : @tls.TlsAcceptor
}

///|
pub impl @server.Acceptor for TlsServerAcceptor with accept(self, tcp) {
  let tls_conn = self.tls_acceptor.accept(reader=tcp, writer=tcp)
  @server.Transport::custom(
    tls_conn,
    tls_conn,
    fn() {
      tls_conn.close()
      tcp.close()
    },
  )
}

///|
pub impl @server.Acceptor for TlsServerAcceptor with close(self) {
  self.tls_acceptor.close()
}

///|
/// Build a TlsAcceptor from configured certificate/key files.
/// Translates file I/O and MbedTLS errors into @core.ConfigError::InvalidTls.
async fn build_tls_engine(config : @core.Config) -> @tls.TlsAcceptor {
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
/// Translate TLS preflight failures into actionable configuration errors (D-01).
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
/// Construct a new TLS acceptor implementing @server.Acceptor.
pub async fn new_tls_acceptor(
  config : @core.Config,
) -> &@server.Acceptor raise @core.ConfigError {
  let tls_acceptor = build_tls_engine(config)
  &TlsServerAcceptor { tls_acceptor }
}
```

#### 4.2.3 `full/server.mbt`
Create `full/server.mbt`:
```moonbit
///|
/// Start a full HTTP/HTTPS server on an explicit TCP port.
/// If config.has_tls() is true, builds and injects a TlsServerAcceptor.
/// Otherwise runs plain HTTP.
pub async fn with_server_at(
  config : @core.Config,
  port : Int,
  action : async (@server.Server) -> Unit,
) -> Unit {
  let acceptor : (&@server.Acceptor)? = if config.has_tls() {
    Some(new_tls_acceptor(config))
  } else {
    None
  }
  @server.with_server_at(config, port, acceptor?, action)
}

///|
/// Start a full server with default port 8080.
pub async fn with_server(
  config : @core.Config,
  action : async (@server.Server) -> Unit,
) -> Unit {
  with_server_at(config, 8080, action)
}
```

---

## 5. Preflight Configuration Validation Sequence

### 5.1 Case Matrix: Startup Paths

| Case | Build / Mode | `config.has_tls()` | `acceptor` Supplied? | Resulting Behavior |
| :---: | :---: | :---: | :---: | :--- |
| **1** | `min` (Plain HTTP) | `false` | `None` | Starts plain server with `PlainAcceptor`. Full `TransmitFile` zero-copy. |
| **2** | `min` (Misconfigured TLS) | `true` | `None` | **Immediately raises `@core.ConfigError::InvalidTls("TLS is not supported in min build; use full build")`**. No socket bound, exits with code 1. |
| **3** | `full` (Plain HTTP) | `false` | `None` | `full.with_server_at` supplies `acceptor=None`. Starts plain server. |
| **4** | `full` (Valid HTTPS) | `true` | `Some(TlsServerAcceptor)` | `full.with_server_at` builds `TlsServerAcceptor`, injects into `@server.with_server_at`. Starts HTTPS server. |
| **5** | `full` (Invalid Cert/Key) | `true` | N/A | `build_tls_engine` fails during preflight: raises `ConfigError::InvalidTls(...)`. Listener is never created (D-01). |
| **6** | Custom / Mock Acceptor | Any | `Some(custom)` | Server delegates to injected acceptor. Enables in-memory mock testing. |

### 5.2 Flowchart

```
with_server_at(config, port, acceptor?)
  │
  ├─► validate_tls(config)  (Checks cert_file + key_file pairing)
  │
  ├─► match acceptor:
  │     ├── Some(acc) => effective_acceptor = acc
  │     └── None =>
  │           ├── if config.has_tls():
  │           │     RAISE ConfigError::InvalidTls("TLS is not supported in min build; use full build")
  │           │     [Listener never created, TCP socket never bound, exits code 1]
  │           └── else:
  │                 effective_acceptor = &PlainAcceptor {}
  │
  ├─► bind TcpServer(port)
  ├─► run accept loop with effective_acceptor
  └─► defer effective_acceptor.close()
```

---

## 6. Zero-Regression & Testing Strategy

### 6.1 Audit of Existing 183 Tests
Our survey confirmed:
- Root (`unmbt/http-server-mbt`): 38 tests, 0 TLS.
- Core (`unmbt/http-server-mbt/core`): 28 tests, 0 TLS.
- Cmd (`cmd/http-server-mbt`): 37 tests, 0 TLS.
- Server (`unmbt/http-server-mbt/server`): 75 tests, 0 TLS. All use plain HTTP over TCP.
- Tls (`unmbt/http-server-mbt/tls`): 5 tests in `loopback_test.mbt`. Independent of `server`.

When `server/moon.pkg` removes `tls`:
- All 75 tests in `server/` continue to compile and pass.
- All 38 root tests, 28 core tests, 37 cmd tests, and 5 tls tests continue to pass.
- Total: 183 / 183 pass (100%).

### 6.2 New Tests to Add in Milestone 1
1. **`server/min_rejection_test.mbt`**:
   - Verify that calling `with_server_at` with `config.cert_file = Some(...)` and `config.key_file = Some(...)` without `acceptor` immediately raises `@core.ConfigError::InvalidTls("TLS is not supported in min build; use full build")`.
   - Verify that calling `with_server_at` with a custom `&Acceptor` successfully runs and dispatches requests.
2. **`full/https_loopback_test.mbt`**:
   - Real HTTPS loopback test:
     - Configures self-signed certificates from `testdata/fixtures/` or generates temporary test certificates.
     - Starts server using `@full.with_server_at(config, 0, ...)`.
     - Connects using `@tls.TlsAcceptor::new_client(ca=cert_pem)` over `@socket.Tcp::connect`.
     - Sends `GET / HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n`.
     - Reads response, verifies `HTTP/1.1 200 OK`.
     - Verifies clean shutdown and 0 resource leaks.

---

## 7. Concrete Step-by-Step Implementation Sequence for Worker

```
[Step 1] server/transport.mbt
         - Define Transport struct with reader, writer, raw_fd, raw_tcp, close_fn
         - Implement Transport::plain and Transport::custom
         - Implement Transport::send

[Step 2] server/acceptor.mbt
         - Define pub(open) trait Acceptor
         - Implement PlainAcceptor

[Step 3] server/server.mbt refactoring
         - Remove `priv enum Transport`
         - Replace `tls_acceptor : @tls.TlsAcceptor?` with `acceptor : &Acceptor` in Server struct
         - Remove `build_tls_acceptor` and `tls_preflight_error` from server.mbt
         - Update `with_server_at` signature to accept optional `acceptor? : &Acceptor`
         - Implement preflight rejection: if config.has_tls() and acceptor is None, raise InvalidTls
         - Update `handle_connection` to dispatch via `server.acceptor.accept(tcp_conn)`
         - Update `send_file_region` to check `transport.raw_fd`

[Step 4] server/moon.pkg
         - Remove `"unmbt/http-server-mbt/tls"` from imports

[Step 5] Verify server package
         - Run `moon check --target native`
         - Run `moon test --target native` (confirm all 183 tests pass)

[Step 6] Create full/ package
         - Create full/moon.pkg
         - Create full/tls_acceptor.mbt (TlsServerAcceptor, build_tls_engine, tls_preflight_error, new_tls_acceptor)
         - Create full/server.mbt (full.with_server_at, full.with_server)

[Step 7] Add Milestone 1 test cases
         - Add server/min_rejection_test.mbt (verify preflight rejection)
         - Add full/https_loopback_test.mbt (verify real HTTPS loopback)

[Step 8] Interface generation & formatting
         - Run `moon info --target native`
         - Run `moon fmt`
         - Verify 0 warnings, 0 errors, 100% tests pass.
```
