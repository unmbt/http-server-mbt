# Project: min & full layered packaging, TLS decoupling, and Proxy architecture readiness

## Architecture
- `core`: Pure HTTP data structures, MIME types, configuration, routing policies, proxy configurations. 100% TLS-free and I/O-free.
- `server`: Core HTTP/1.1 static file server, Range, conditional requests, compression negotiation, directory listing, and TransmitFile zero-copy. Decoupled from TLS via abstract `Transport` and `Acceptor` interfaces. 100% TLS-free in `min` mode.
- `tls`: Standalone MbedTLS 4.2.0 engine providing `TlsAcceptor` and `TlsConn`.
- `full`: Integration layer combining `server` with `tls` acceptor injection for HTTPS support.
- `cmd/common`: Shared CLI argument parsing, banner, options mapping, and runtime error handling.
- `cmd/http-server-min`: Minimal CLI executable. Does not compile MbedTLS. Fails with exit code 1 if `--cert`, `--key`, or `--proxy` options are specified.
- `cmd/http-server-full`: Full CLI executable with TLS and proxy configuration support.
- `cmd/http-server-mbt`: Backward-compatible CLI entry point (full).
- `c_abi`: Exported C-compatible APIs (`hs_*`) with ABI versioning, handle lifecycle, error inspection, and clean symbol isolation.
- `scripts`: Build automation scripts written in `.mbtx` (`scripts/build_cabi.mbtx`) driving MSVC/MinGW C library generation.

## Feature Inventory
| # | Feature | Description | Milestone | Source |
|---|---------|-------------|-----------|--------|
| 1 | Server TLS Decoupling | Abstract `Transport` & `Acceptor` in `server`, removing hard dependency on `tls` | M1 | ORIGINAL_REQUEST §R1, survey |
| 2 | TLS Dependency Injection | `full` integration package injecting `TlsAcceptor` into server lifecycle | M1 | ORIGINAL_REQUEST §R1, survey |
| 3 | Zero Test Regression | Maintain 100% pass on all 183 existing test cases across all packages | M1 | ORIGINAL_REQUEST §R1, survey |
| 4 | CLI Shared Helpers | Extract common CLI parsing, banner, and validation to `cmd/common` | M2 | ORIGINAL_REQUEST §R2, survey |
| 5 | Min CLI Executable | `cmd/http-server-min` building pure static server with 0 MbedTLS C compilation | M2 | ORIGINAL_REQUEST §R2, survey |
| 6 | Min CLI Preflight Rejection | In `min` CLI, `--cert`, `--key`, `--proxy`, etc. exit code 1 with diagnostic stderr | M2 | ORIGINAL_REQUEST §R2, survey |
| 7 | Full CLI Executable | `cmd/http-server-full` supporting all static, TLS, and proxy arguments | M2 | ORIGINAL_REQUEST §R2, survey |
| 8 | C ABI Interface Definition | `c_abi` package defining `hs_abi_version`, `hs_init`, `hs_server_*`, `hs_error_*` | M3 | ORIGINAL_REQUEST §R3, survey |
| 9 | C ABI `.mbtx` Build Pipeline | `scripts/build_cabi.mbtx` driving compilation of dynamic & static libraries | M3 | ORIGINAL_REQUEST §R3, survey |
| 10 | Clean Symbol Isolation | Pass `/Dmain` & `/FIclean_exports.h` + `.def` ensuring strictly `hs_*` exports (no `main`, no internal leaks) | M3 | ORIGINAL_REQUEST §R3, survey |
| 11 | Min C Library Zero Crypto | Verify `min` C library (`.lib`/`.dll`) contains 0 MbedTLS / PSA-Crypto symbols | M3 | ORIGINAL_REQUEST §R3, survey |
| 12 | C ABI Test Program Verification | Standalone C test programs verifying dynamic and static linking of `hs_*` | M3 | ORIGINAL_REQUEST §R3, survey |
| 13 | Reverse Proxy Configuration Model | In `core/config.mbt`, model `proxy`, `proxy_all`, `proxy_config`, `proxy_options`, `websocket` | M4 | ORIGINAL_REQUEST §R4, survey |
| 14 | Reverse Proxy State Machine & Forward Interface | Define `Resolving -> Proxying -> Tunnel / Idle / Closing` and streaming forward interface | M4 | ORIGINAL_REQUEST §R4, survey |
| 15 | SDD Documentation & ADR Update | Update `docs/design.md` (D-20, D-21), `docs/tasks.md` with complete architecture contracts | M4 | ORIGINAL_REQUEST §R4, survey |
| 16 | Comprehensive E2E Verification & Multi-Role Gates | Multi-tier tests, reviewer/challenger/auditor independent verification, local git commit | M5 | ORIGINAL_REQUEST §Quality gates |

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| 1 | Server & Core Decoupling from TLS | Abstract `Transport` & `Acceptor`, decouple `server` from `tls`, ensure 183 tests pass | none | IN_PROGRESS |
| 2 | Min & Full CLI Packaging & Distribution | `cmd/common`, `cmd/http-server-min`, `cmd/http-server-full`, preflight exit code 1 validation | M1 | PLANNED |
| 3 | C ABI Dynamic & Static Library Export Pipeline | `c_abi` package, `scripts/build_cabi.mbtx`, symbol hygiene (`hs_*`, no `main`, no MbedTLS in min), C test verification | M1 | PLANNED |
| 4 | Reverse Proxy Architecture & Interface Readiness | `core` proxy data structures, state machine & streaming interface, SDD doc updates (D-20, D-21) | M1 | PLANNED |
| 5 | E2E Testing, Gate Verification & Final Handoff | Full E2E tests across all tiers, review/challenge/forensic audit gates, local git commit, victory report | M1, M2, M3, M4 | PLANNED |

## Interface Contracts
### `server` ↔ `tls` / Transport Abstraction
```moonbit
// In server:
pub struct Transport {
  reader : &@io.Reader
  writer : &@io.Writer
  raw_fd : @types.Fd?
  raw_tcp : @socket.Tcp?
  close_fn : () -> Unit
}

pub trait Acceptor {
  accept(Self, @socket.Tcp) -> Transport!Error
  close(Self) -> Unit
}

pub struct PlainAcceptor {}
// PlainAcceptor wraps Tcp into Transport directly.

// Server startup:
pub async fn with_server_at(
  config : @core.Config,
  port : Int,
  acceptor? : &Acceptor,
  action : async () -> Unit
) -> Unit
```

### `cmd/common` ↔ `cmd/http-server-min` / `cmd/http-server-full`
```moonbit
// In cmd/common:
pub enum BuildVariant {
  Min
  Full
}

pub fn parse_cli_args(args : Array[String], variant : BuildVariant) -> Result[@core.Config, String]
// When variant is Min and --cert/--key/--proxy options are provided, returns Err("... not supported in min build")
```

### `c_abi` Public C Signatures
```c
HS_EXPORT uint32_t hs_abi_version(void);
HS_EXPORT int32_t hs_init(void);
HS_EXPORT hs_server_t* hs_server_create(const hs_config_t* config);
HS_EXPORT int32_t hs_server_start(hs_server_t* server);
HS_EXPORT int32_t hs_server_stop(hs_server_t* server);
HS_EXPORT void hs_server_destroy(hs_server_t* server);
HS_EXPORT size_t hs_error_copy(int32_t code, char* buf, size_t cap);
```

### `core` Reverse Proxy Data Structures
```moonbit
pub struct ProxyRule {
  pattern : String
  target : String
  path_rewrite : Map[String, String]
}

pub struct ProxyConfig {
  rules : Array[ProxyRule]
}
```

## Code Layout
- `core/`: Config, HTTP types, Proxy types, routing policies
- `server/`: Plain static HTTP server, TransmitFile, Transport & Acceptor abstractions
- `tls/`: Standalone MbedTLS binding
- `full/`: TLS Acceptor implementation and server wiring
- `cmd/common/`: Shared CLI logic
- `cmd/http-server-min/`: Minimal CLI executable
- `cmd/http-server-full/`: Full CLI executable
- `cmd/http-server-mbt/`: Default CLI executable
- `c_abi/`: C-compatible interface
- `scripts/`: `.mbtx` build automation
