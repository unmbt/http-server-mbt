# E2E Testing Infrastructure & 4-Tier Test Specification

**Project**: `http-server-mbt` (Layered `thin` & `full` Packaging, TLS Decoupling, and Reverse Proxy Architecture Readiness)  
**Document**: `TEST_INFRA.md`  
**Baseline Version**: 2026-09-18  
**Author**: E2E Test Writer (`test_writer_e2e_1`)  
**Status**: Authoritative Reference  

---

## 1. Overview & Testing Philosophy

This document defines the End-to-End (E2E) testing track infrastructure, methodology, feature inventory mapping, and comprehensive test catalogs for the `thin` & `full` packaging, TLS decoupling, C ABI export pipeline, and reverse proxy readiness project.

### 1.1 Core Principles

1. **Opaque-Box & Requirement-Driven**:
   Tests treat components as black boxes through their public interfaces, CLI invocations, wire-level network interactions, or C ABI boundaries. Assertions are derived strictly from specifications (`ORIGINAL_REQUEST.md`, `docs/design.md`, `docs/tasks.md`, RFC 9110/9112) and the reference implementation (`http-party/http-server` @ `0d3b7bb5`), never from internal implementation quirks.

2. **Explicit Authoritative Sources**:
   Every test case across all tiers specifies its authoritative source of expected output. When comparing observable behavior, outputs must match reference program captures or normative RFC requirements.

3. **Strict Test Integrity & Anti-Facade**:
   No facade tests that unconditionally pass without exercising real logic. No tests designed to pass against mock stubs when real execution paths exist. Tests must fail if any requirement contract is violated.

4. **Progressive Testability & Isolation**:
   Tests for Milestone 1 must be runnable using only M1 features and completed dependencies. Tests are self-contained and isolated: each test sets up its own state, allocates dynamic ports (port 0 or ephemeral allocation), leaves no persistent artifacts, and cleans up sockets and file handles cleanly.

5. **Non-Deterministic Variance Handling**:
   Non-deterministic values (e.g. ephemeral TCP port numbers, process IDs, wall-clock timestamps, temporary folder paths) are isolated and matched using regular expressions or semantic structural validators rather than brittle literal matching.

6. **0-Handle-Leak & Resource Safety**:
   On Windows Native, long-running and repetitive network tests verify zero resource leaks via Win32 `GetProcessHandleCount` assertions.

---

## 2. Feature Inventory Mapping

All 16 features from `PROJECT.md` are cataloged below with their milestone, component ownership, test suite assignment, and authoritative specification source.

| # | Feature ID | Feature Name | Target Component | Milestone | Target Test File / Harness | Authoritative Source |
|---|---|---|---|---|---|---|
| 1 | `F01` | Server TLS Decoupling | `server` | M1 | `server/server_transport_test.mbt` | ORIGINAL_REQUEST §R1, D-02, D-08 |
| 2 | `F02` | TLS Dependency Injection | `full` | M1 | `full/tls_acceptor_test.mbt` | ORIGINAL_REQUEST §R1, D-02, D-08 |
| 3 | `F03` | Zero Test Regression | Whole Repo | M1 | `moon test --target native` (183 suites) | ORIGINAL_REQUEST §R1, survey |
| 4 | `F04` | CLI Shared Helpers | `cmd/common` | M2 | `cmd/common/cli_helpers_test.mbt` | ORIGINAL_REQUEST §R2, survey |
| 5 | `F05` | Thin CLI Executable | `cmd/http-server-mbt-thin` | M2 | `cmd/http-server-mbt-thin/min_cli_test.mbt` | ORIGINAL_REQUEST §R2, D-08, D-15 |
| 6 | `F06` | Thin CLI Preflight Rejection | `cmd/http-server-mbt-thin` | M2 | `cmd/http-server-mbt-thin/preflight_reject_test.mbt` | ORIGINAL_REQUEST §R2, D-08, D-15 |
| 7 | `F07` | Full CLI Executable | `cmd/http-server-full` | M2 | `cmd/http-server-full/full_cli_test.mbt` | ORIGINAL_REQUEST §R2, D-08, D-15 |
| 8 | `F08` | C ABI Interface Definition | `c_abi` | M3 | `c_abi/c_abi_test.mbt` | ORIGINAL_REQUEST §R3, D-07, D-11 |
| 9 | `F09` | C ABI `.mbtx` Build Pipeline | `scripts/build_cabi.mbtx` | M3 | `scripts/run_cabi_pipeline_test.mbtx` | ORIGINAL_REQUEST §R3, D-07, D-11 |
| 10 | `F10` | Clean Symbol Isolation | C ABI DLL/LIB | M3 | `scripts/verify_symbols.mbtx` | ORIGINAL_REQUEST §R3, D-07, D-11 |
| 11 | `F11` | Thin C Library Zero Crypto | C ABI Thin Artifacts | M3 | `scripts/verify_zero_crypto.mbtx` | ORIGINAL_REQUEST §R3, D-07, D-11 |
| 12 | `F12` | C ABI Test Program Verification | Native C Test Programs | M3 | `tests/cabi/test_cabi_dynamic.c`, `test_cabi_static.c` | ORIGINAL_REQUEST §R3, D-07, D-11 |
| 13 | `F13` | Reverse Proxy Configuration Model | `core` | M4 | `core/proxy_config_test.mbt` | ORIGINAL_REQUEST §R4, D-04, D-21 |
| 14 | `F14` | Reverse Proxy State Machine & Forwarding | `server` / `core` | M4 | `server/proxy_state_machine_test.mbt` | ORIGINAL_REQUEST §R4, D-05, D-21 |
| 15 | `F15` | SDD Documentation & ADR Update | `docs/` | M4 | `scripts/verify_docs_links.mbtx` | ORIGINAL_REQUEST §R4, D-20, D-21 |
| 16 | `F16` | Comprehensive E2E Verification & Multi-Role Gates | Full Workspace | M5 | `scripts/run_e2e.mbtx`, Challenger/Auditor gates | ORIGINAL_REQUEST §AC, M5 Gate |

---

## 3. 4-Tier Test Methodology

The testing architecture organizes all test cases into 4 rigorous tiers:
- **Tier 1: Feature Coverage (>=5 tests per feature)**: Validates primary behavior and positive contract (happy path) for every feature.
- **Tier 2: Boundary & Corner Cases (>=5 tests per feature)**: Stresses limits, invalid inputs, edge conditions, timeouts, resource reclamation, and error paths.
- **Tier 3: Cross-Feature Combinations (Pairwise & Multi-Feature)**: Tests complex interaction points between features (e.g. Thin CLI flag rejection combined with complex static routing; Full CLI TLS combined with SPA fallback; C ABI asynchronous cancellation under proxy load).
- **Tier 4: Real-World Application Scenarios**: Comprehensive end-to-end integration workflows representing production deployments.

---

## 4. Tier 1: Feature Coverage (80 Test Cases)

### Feature 1: Server TLS Decoupling (`F01`)
*Target: `server` | Source: `ORIGINAL_REQUEST.md` §R1, `docs/design.md` D-02, D-08*

- **`T1-F01-01`**: **Plaintext HTTP GET Dispatch via PlainAcceptor**  
  *Input*: Spin up server with `PlainAcceptor`, send `GET /hello.txt HTTP/1.1\r\nHost: localhost\r\n\r\n`.  
  *Expected Output*: Status 200 OK, Content-Length matching file size, body `Hello MoonBit!`.  
  *Authoritative Source*: RFC 9112 §2, `docs/design.md` D-02.
- **`T1-F01-02`**: **Plaintext HTTP HEAD Request via PlainAcceptor**  
  *Input*: Send `HEAD /hello.txt HTTP/1.1\r\nHost: localhost\r\n\r\n` to `PlainAcceptor`.  
  *Expected Output*: Status 200 OK, identical headers to GET, exactly 0 bytes body.  
  *Authoritative Source*: RFC 9110 §9.3.2.
- **`T1-F01-03`**: **Transport Interface Reader and Writer Pass-Through**  
  *Input*: Instantiate `Transport` wrapping mock reader/writer; read 64 bytes and write 32 bytes.  
  *Expected Output*: Bytes transferred verbatim with 0 distortion and exact length match.  
  *Authoritative Source*: `PROJECT.md` §Interface Contracts.
- **`T1-F01-04`**: **Transport Cleanup on Connection Teardown**  
  *Input*: Establish TCP connection, send full request, receive response, and close socket.  
  *Expected Output*: `Transport.close_fn` is invoked exactly once; underlying socket handle closed.  
  *Authoritative Source*: `docs/design.md` D-05, D-16.
- **`T1-F01-05`**: **Default Acceptor Fallback in Server Lifecycle**  
  *Input*: Invoke `with_server_at(config, port, action)` without specifying `acceptor` parameter.  
  *Expected Output*: Server boots successfully with `PlainAcceptor` by default; serves plaintext HTTP.  
  *Authoritative Source*: `PROJECT.md` §Interface Contracts.

### Feature 2: TLS Dependency Injection (`F02`)
*Target: `full` | Source: `ORIGINAL_REQUEST.md` §R1, `docs/design.md` D-02, D-08*

- **`T1-F02-01`**: **TlsAcceptor Instantiation with Valid Certificate & Key**  
  *Input*: Load `testdata/tls/server_cert.pem` and `testdata/tls/server_key.pem` into `TlsAcceptor::new`.  
  *Expected Output*: Returns `Ok(TlsAcceptor)`; internal MbedTLS SSL config initialized.  
  *Authoritative Source*: `tls/loopback_test.mbt`, `docs/design.md` D-08.
- **`T1-F02-02`**: **TLS 1.3 Handshake Negotiation via Injected Acceptor**  
  *Input*: Connect TLS client configured for TLS 1.3 to server initialized with `TlsAcceptor`.  
  *Expected Output*: Handshake succeeds; negotiated cipher suite is TLS 1.3 compliant (e.g. `TLS_AES_128_GCM_SHA256`).  
  *Authoritative Source*: RFC 8446, `docs/design.md` D-08.
- **`T1-F02-03`**: **Encrypted HTTPS GET Static File Delivery**  
  *Input*: Send encrypted `GET /index.html HTTP/1.1` over TLS session.  
  *Expected Output*: 200 OK, decrypted payload matches `testdata/public/index.html`.  
  *Authoritative Source*: `tls/loopback_test.mbt`, RFC 9110.
- **`T1-F02-04`**: **Encrypted HTTPS HEAD Response Verification**  
  *Input*: Send encrypted `HEAD /index.html HTTP/1.1` over TLS session.  
  *Expected Output*: 200 OK, Content-Type `text/html; charset=utf-8`, 0 body bytes delivered.  
  *Authoritative Source*: RFC 9110 §9.3.2.
- **`T1-F02-05`**: **TlsAcceptor Clean Teardown**  
  *Input*: Invoke `TlsAcceptor.close()` after completing HTTPS transactions.  
  *Expected Output*: MbedTLS context freed, SSL session structures deallocated, 0 handle leaks.  
  *Authoritative Source*: `docs/design.md` D-08, D-16.

### Feature 3: Zero Test Regression (`F03`)
*Target: Whole Repo | Source: `ORIGINAL_REQUEST.md` §R1, Survey*

- **`T1-F03-01`**: **Core Protocol & MIME Package Regression**  
  *Input*: Run all unit tests in `core` (`cache`, `config`, `mime`, `range`, `routing`, `security`).  
  *Expected Output*: All 12 test blocks pass (100% PASS, 0 FAIL).  
  *Authoritative Source*: Existing test baseline (`core/core_test.mbt`).
- **`T1-F03-02`**: **Server C-Suite Regression (C001-C042)**  
  *Input*: Run all test suites in `server` (`c_suite_*.mbt`, `server_test.mbt`).  
  *Expected Output*: All test cases pass with 0 assertions failed.  
  *Authoritative Source*: `docs/tasks.md` C-suite migration matrix.
- **`T1-F03-03`**: **Standalone TLS Loopback Regression**  
  *Input*: Run `tls` package loopback test suite.  
  *Expected Output*: All handshake, transmission, and teardown tests pass 100%.  
  *Authoritative Source*: `tls/loopback_test.mbt`.
- **`T1-F03-04`**: **CLI Whitebox Parser Regression**  
  *Input*: Run `cmd/http-server-mbt` whitebox tests (`cli_wbtest.mbt`, `cli_challenger_wbtest.mbt`).  
  *Expected Output*: All CLI argument parsing tests pass 100%.  
  *Authoritative Source*: `cmd/http-server-mbt/cli_wbtest.mbt`.
- **`T1-F03-05`**: **Root Engine & Security Adversarial Regression**  
  *Input*: Run root package tests (`engine_test.mbt`, adversarial directory tests).  
  *Expected Output*: All 183 tests across the entire repository pass with exit code 0.  
  *Authoritative Source*: `ORIGINAL_REQUEST.md` §Acceptance Criteria (183/183 pass).

### Feature 4: CLI Shared Helpers (`F04`)
*Target: `cmd/common` | Source: `ORIGINAL_REQUEST.md` §R2, Survey*

- **`T1-F04-01`**: **Standard Network & Root Arguments Parsing**  
  *Input*: Parse args `["--port", "9090", "-a", "admin:123456", "testdata/public"]`.  
  *Expected Output*: `Config.port == 9090`, `Config.auth == Some("admin:123456")`, `Config.root == "testdata/public"`.  
  *Authoritative Source*: `bin/http-server`, `docs/design.md` D-08.
- **`T1-F04-02`**: **Boolean Switch Arguments Parsing**  
  *Input*: Parse args `["--spa", "--cors", "--no-autoIndex", "--no-showDir", "--silent", "--log-ip"]`.  
  *Expected Output*: `Config.spa == true`, `Config.cors == true`, `autoIndex == false`, `showDir == false`, `silent == true`, `log_ip == true`.  
  *Authoritative Source*: `test/cli.test.js`.
- **`T1-F04-03`**: **Cache & Base-URL Arguments Parsing**  
  *Input*: Parse args `["--cache", "86400", "--base-url", "/dashboard/"]`.  
  *Expected Output*: `Config.cache == 86400`, `Config.base_url == "/dashboard"`.  
  *Authoritative Source*: `docs/design.md` D-04.
- **`T1-F04-04`**: **Banner Formatting Output**  
  *Input*: Call `render_banner(config, actual_port=8080, local_ips=["127.0.0.1", "192.168.1.5"])`.  
  *Expected Output*: Output string contains `http://127.0.0.1:8080`, `http://192.168.1.5:8080`, and configuration flags.  
  *Authoritative Source*: `cmd/http-server-mbt/banner.mbt`.
- **`T1-F04-05`**: **Usage & Help Text Generation**  
  *Input*: Call `print_help(BuildVariant::Thin)` vs `print_help(BuildVariant::Full)`.  
  *Expected Output*: Thin help omits TLS/Proxy flags; Full help lists `--cert`, `--key`, `--proxy`, `--proxy-all`.  
  *Authoritative Source*: `docs/design.md` D-08, D-15.

### Feature 5: Thin CLI Executable (`F05`)
*Target: `cmd/http-server-mbt-thin` | Source: `ORIGINAL_REQUEST.md` §R2, `docs/design.md` D-08, D-15*

- **`T1-F05-01`**: **Thin CLI Compilation & Binary Generation**  
  *Input*: Execute `moon build --target native` on `cmd/http-server-mbt-thin`.  
  *Expected Output*: Builds successfully producing `http-server-mbt-thin.exe` with exit code 0.  
  *Authoritative Source*: `ORIGINAL_REQUEST.md` §R2.
- **`T1-F05-02`**: **Thin CLI Static File Server Startup**  
  *Input*: Launch `http-server-mbt-thin -p 0 testdata/public`, capture bound port from stdout banner.  
  *Expected Output*: Process stays alive; stdout outputs banner; bound port is accessible via HTTP.  
  *Authoritative Source*: `docs/design.md` D-08.
- **`T1-F05-03`**: **Thin CLI HTTP Static Serving Functionality**  
  *Input*: Send HTTP GET request to running `http-server-mbt-thin` for `/hello.txt`.  
  *Expected Output*: Receives 200 OK with exact contents of `hello.txt`.  
  *Authoritative Source*: `ORIGINAL_REQUEST.md` §R2.
- **`T1-F05-04`**: **Thin CLI `--help` Flag Execution**  
  *Input*: Execute `http-server-mbt-thin --help`.  
  *Expected Output*: Exits with code 0; stdout displays standard options; stderr is empty.  
  *Authoritative Source*: `test/cli.test.js`.
- **`T1-F05-05`**: **Thin CLI `--version` Flag Execution**  
  *Input*: Execute `http-server-mbt-thin --version`.  
  *Expected Output*: Exits with code 0; stdout outputs semantic version string (e.g. `0.1.0-thin`).  
  *Authoritative Source*: `test/cli.test.js`.

### Feature 6: Thin CLI Preflight Rejection (`F06`)
*Target: `cmd/http-server-mbt-thin` | Source: `ORIGINAL_REQUEST.md` §R2, `docs/design.md` D-08, D-15*

- **`T1-F06-01`**: **Rejection of `--cert` in Thin CLI**  
  *Input*: Run `http-server-mbt-thin --cert testdata/tls/server_cert.pem`.  
  *Expected Output*: Immediate process termination with exit code 1; stderr contains `--cert is not supported in this build`.  
  *Authoritative Source*: `ORIGINAL_REQUEST.md` §R2, `docs/design.md` D-08, D-15.
- **`T1-F06-02`**: **Rejection of `--key` in Thin CLI**  
  *Input*: Run `http-server-mbt-thin --key testdata/tls/server_key.pem`.  
  *Expected Output*: Exit code 1; stderr contains `--key is not supported in this build`.  
  *Authoritative Source*: `ORIGINAL_REQUEST.md` §R2, `docs/design.md` D-08, D-15.
- **`T1-F06-03`**: **Rejection of `--proxy` in Thin CLI**  
  *Input*: Run `http-server-mbt-thin --proxy http://127.0.0.1:3000`.  
  *Expected Output*: Exit code 1; stderr contains `--proxy is not supported in this build`.  
  *Authoritative Source*: `ORIGINAL_REQUEST.md` §R2, `docs/design.md` D-08, D-15.
- **`T1-F06-04`**: **Rejection of `--proxy-all` in Thin CLI**  
  *Input*: Run `http-server-mbt-thin --proxy-all`.  
  *Expected Output*: Exit code 1; stderr contains `--proxy-all is not supported in this build`.  
  *Authoritative Source*: `ORIGINAL_REQUEST.md` §R2, `docs/design.md` D-08, D-15.
- **`T1-F06-05`**: **Rejection of `--proxy-config` in Thin CLI**  
  *Input*: Run `http-server-mbt-thin --proxy-config proxy.json`.  
  *Expected Output*: Exit code 1; stderr contains `--proxy-config is not supported in this build`.  
  *Authoritative Source*: `ORIGINAL_REQUEST.md` §R2, `docs/design.md` D-08, D-15.

### Feature 7: Full CLI Executable (`F07`)
*Target: `cmd/http-server-full` | Source: `ORIGINAL_REQUEST.md` §R2, `docs/design.md` D-08, D-15*

- **`T1-F07-01`**: **Full CLI Compilation & Binary Generation**  
  *Input*: Execute `moon build --target native` on `cmd/http-server-full`.  
  *Expected Output*: Builds successfully producing `http-server-full.exe` with exit code 0.  
  *Authoritative Source*: `ORIGINAL_REQUEST.md` §R2.
- **`T1-F07-02`**: **Full CLI Plaintext HTTP Serving**  
  *Input*: Run `http-server-full -p 0 testdata/public` without TLS flags.  
  *Expected Output*: Starts listening; successfully responds to HTTP GET with 200 OK.  
  *Authoritative Source*: `bin/http-server`.
- **`T1-F07-03`**: **Full CLI HTTPS Startup with TLS Arguments**  
  *Input*: Run `http-server-full -p 0 --cert testdata/tls/server_cert.pem --key testdata/tls/server_key.pem testdata/public`.  
  *Expected Output*: Starts listening; stdout banner indicates `https://` protocol.  
  *Authoritative Source*: `docs/design.md` D-08.
- **`T1-F07-04`**: **Full CLI HTTPS Request Delivery**  
  *Input*: Send HTTPS GET request via TLS client to running `http-server-full`.  
  *Expected Output*: Status 200 OK, Content-Type matches file type, body matches `index.html`.  
  *Authoritative Source*: `docs/design.md` D-08.
- **`T1-F07-05`**: **Full CLI Comprehensive Help Output**  
  *Input*: Run `http-server-full --help`.  
  *Expected Output*: Output includes `--cert`, `--key`, `--key-passphrase`, `--proxy`, `--proxy-all`, `--proxy-config`, `--websocket`.  
  *Authoritative Source*: `test/cli.test.js`.

### Feature 8: C ABI Interface Definition (`F08`)
*Target: `c_abi` | Source: `ORIGINAL_REQUEST.md` §R3, `docs/design.md` D-07, D-11*

- **`T1-F08-01`**: **Query C ABI Version (`hs_abi_version`)**  
  *Input*: Pass valid `uint32_t *major, *minor` pointers to `hs_abi_version`.  
  *Expected Output*: Returns `HS_OK` (0); `*major == 1`, `*minor == 0`.  
  *Authoritative Source*: `docs/design.md` D-07 §3.1.
- **`T1-F08-02`**: **C ABI Subsystem Initialization (`hs_init`)**  
  *Input*: Call `hs_init()`.  
  *Expected Output*: Returns `HS_OK` (0); runtime thread pools and async engines ready.  
  *Authoritative Source*: `docs/design.md` D-07 §3.1.
- **`T1-F08-03`**: **Server Instance Creation (`hs_server_create`)**  
  *Input*: Pass JSON config `'{"port": 0, "root": "testdata/public"}'` to `hs_server_create`.  
  *Expected Output*: Returns non-null `hs_server_t*` handle; `*err_out == HS_OK`.  
  *Authoritative Source*: `docs/design.md` D-07 §3.2.
- **`T1-F08-04`**: **Asynchronous Server Start (`hs_server_start_async`)**  
  *Input*: Start server handle with completion callback and user context.  
  *Expected Output*: Returns `HS_OK` / `HS_ACCEPTED`; callback invoked with `status == HS_OK` and `actual_port > 0`.  
  *Authoritative Source*: `docs/design.md` D-07 §3.2.
- **`T1-F08-05`**: **Asynchronous Server Stop & Release (`hs_server_stop_async`)**  
  *Input*: Stop running server handle via `hs_server_stop_async`, then call `hs_server_release`.  
  *Expected Output*: Callback receives `HS_OK`; release frees all internal memory without crash.  
  *Authoritative Source*: `docs/design.md` D-07 §3.2.

### Feature 9: C ABI `.mbtx` Build Pipeline (`F09`)
*Target: `scripts/build_cabi.mbtx` | Source: `ORIGINAL_REQUEST.md` §R3, `docs/design.md` D-07, D-11*

- **`T1-F09-01`**: **Build Thin Dynamic Library Artifacts**  
  *Input*: Run `moon run scripts/build_cabi.mbtx -- --variant thin --kind dynamic`.  
  *Expected Output*: Generates `target/cabi/http_server_mbt_min.dll` and `http_server_mbt_min.lib`.  
  *Authoritative Source*: `ORIGINAL_REQUEST.md` §R3.
- **`T1-F09-02`**: **Build Thin Static Library Artifacts**  
  *Input*: Run `moon run scripts/build_cabi.mbtx -- --variant thin --kind static`.  
  *Expected Output*: Generates `target/cabi/http_server_mbt_min_static.lib`.  
  *Authoritative Source*: `ORIGINAL_REQUEST.md` §R3.
- **`T1-F09-03`**: **Build Full Dynamic Library Artifacts**  
  *Input*: Run `moon run scripts/build_cabi.mbtx -- --variant full --kind dynamic`.  
  *Expected Output*: Generates `target/cabi/http_server_mbt_full.dll` and `http_server_mbt_full.lib`.  
  *Authoritative Source*: `ORIGINAL_REQUEST.md` §R3.
- **`T1-F09-04`**: **Build Full Static Library Artifacts**  
  *Input*: Run `moon run scripts/build_cabi.mbtx -- --variant full --kind static`.  
  *Expected Output*: Generates `target/cabi/http_server_mbt_full_static.lib`.  
  *Authoritative Source*: `ORIGINAL_REQUEST.md` §R3.
- **`T1-F09-05`**: **Header Generation and Integrity Verification**  
  *Input*: Inspect generated header `include/http_server_mbt.h`.  
  *Expected Output*: Header defines all `hs_*` APIs, `HS_*` error macros, and `HS_API` export directives.  
  *Authoritative Source*: `docs/design.md` D-07.

### Feature 10: Clean Symbol Isolation (`F10`)
*Target: C ABI DLL/LIB | Source: `ORIGINAL_REQUEST.md` §R3, `docs/design.md` D-07, D-11*

- **`T1-F10-01`**: **Export Table Inspection for `hs_abi_version`**  
  *Input*: Run `dumpbin /EXPORTS target/cabi/http_server_mbt_min.dll`.  
  *Expected Output*: Symbol `hs_abi_version` is listed in exported functions table.  
  *Authoritative Source*: `docs/design.md` D-07, D-11.
- **`T1-F10-02`**: **Export Table Inspection for Lifecycle APIs**  
  *Input*: Run `dumpbin /EXPORTS target/cabi/http_server_mbt_min.dll`.  
  *Expected Output*: Symbols `hs_server_create`, `hs_server_start_async`, `hs_server_stop_async`, `hs_server_release` are exported.  
  *Authoritative Source*: `docs/design.md` D-07.
- **`T1-F10-03`**: **Export Table Inspection for Error Diagnostic API**  
  *Input*: Run `dumpbin /EXPORTS target/cabi/http_server_mbt_min.dll`.  
  *Expected Output*: Symbol `hs_error_copy` is exported.  
  *Authoritative Source*: `docs/design.md` D-07.
- **`T1-F10-04`**: **Strict Absence of `main` Symbol in DLL Exports**  
  *Input*: Check exports of `http_server_mbt_min.dll` and `http_server_mbt_full.dll` for symbol `main`.  
  *Expected Output*: Zero occurrences of symbol `main` (regex `\bmain\b` returns 0 matches).  
  *Authoritative Source*: `ORIGINAL_REQUEST.md` §R3, `docs/design.md` D-07.
- **`T1-F10-05`**: **Strict Absence of Internal Runtime Symbols**  
  *Input*: Check exports for un-prefixed or internal symbols (e.g. `moonbit_*`, `mbedtls_*`).  
  *Expected Output*: Only symbols starting with `hs_` appear in the DLL export list.  
  *Authoritative Source*: `ORIGINAL_REQUEST.md` §R3.

### Feature 11: Thin C Library Zero Crypto (`F11`)
*Target: C ABI Thin Artifacts | Source: `ORIGINAL_REQUEST.md` §R3, Survey*

- **`T1-F11-01`**: **Zero `mbedtls_*` Symbols in Thin DLL**  
  *Input*: Scan symbol table of `target/cabi/http_server_mbt_min.dll`.  
  *Expected Output*: 0 matches for `mbedtls_*`.  
  *Authoritative Source*: `ORIGINAL_REQUEST.md` §R3.
- **`T1-F11-02`**: **Zero `psa_*` Symbols in Thin DLL**  
  *Input*: Scan symbol table of `target/cabi/http_server_mbt_min.dll`.  
  *Expected Output*: 0 matches for `psa_*`.  
  *Authoritative Source*: `ORIGINAL_REQUEST.md` §R3.
- **`T1-F11-03`**: **Zero `mbedtls_*` Symbols in Thin Static Archive**  
  *Input*: Scan object symbol table of `target/cabi/http_server_mbt_min_static.lib`.  
  *Expected Output*: 0 matches for `mbedtls_*`.  
  *Authoritative Source*: `ORIGINAL_REQUEST.md` §R3.
- **`T1-F11-04`**: **Zero `psa_*` Symbols in Thin Static Archive**  
  *Input*: Scan object symbol table of `target/cabi/http_server_mbt_min_static.lib`.  
  *Expected Output*: 0 matches for `psa_*`.  
  *Authoritative Source*: `ORIGINAL_REQUEST.md` §R3.
- **`T1-F11-05`**: **Positive Control: Full DLL Contains Crypto Symbols**  
  *Input*: Scan symbol table of `target/cabi/http_server_mbt_full.dll`.  
  *Expected Output*: Contains multiple `mbedtls_*` / `psa_*` symbols, proving detection validity.  
  *Authoritative Source*: `spec_report.md` §7.

### Feature 12: C ABI Test Program Verification (`F12`)
*Target: Native C Test Programs | Source: `ORIGINAL_REQUEST.md` §R3, `docs/design.md` D-07, D-11*

- **`T1-F12-01`**: **C Harness Compilation & Dynamic Linking**  
  *Input*: Compile `test_cabi_dynamic.c` with MSVC `cl.exe` linking `http_server_mbt_min.lib` + DLL.  
  *Expected Output*: Compiles with 0 warnings; execution prints ABI version `1.0` and exits 0.  
  *Authoritative Source*: `ORIGINAL_REQUEST.md` §R3.
- **`T1-F12-02`**: **C Harness Embedded Server HTTP Handling**  
  *Input*: C program starts server via `hs_server_start_async`, issues HTTP GET request via socket.  
  *Expected Output*: Receives 200 OK with expected static file content.  
  *Authoritative Source*: `docs/design.md` D-07.
- **`T1-F12-03`**: **C Harness Clean Server Shutdown**  
  *Input*: C program invokes `hs_server_stop_async` and awaits callback.  
  *Expected Output*: Callback called with `HS_OK`; subsequent socket connect fails with connection refused.  
  *Authoritative Source*: `docs/design.md` D-07.
- **`T1-F12-04`**: **C Harness Win32 `LoadLibrary` Runtime Dynamic Loading**  
  *Input*: C program loads `http_server_mbt_min.dll` dynamically via `LoadLibraryA` and `GetProcAddress`.  
  *Expected Output*: Function pointer to `hs_abi_version` is resolved; call returns `HS_OK`.  
  *Authoritative Source*: `docs/design.md` D-07.
- **`T1-F12-05`**: **C Harness Static Linking Compilation**  
  *Input*: Compile `test_cabi_static.c` linking `http_server_mbt_min_static.lib`.  
  *Expected Output*: Compiles cleanly with MSVC; executes and exits code 0.  
  *Authoritative Source*: `ORIGINAL_REQUEST.md` §R3.

### Feature 13: Reverse Proxy Configuration Model (`F13`)
*Target: `core` | Source: `ORIGINAL_REQUEST.md` §R4, `docs/design.md` D-04, D-21*

- **`T1-F13-01`**: **Fallback Proxy Model Field Verification**  
  *Input*: Construct `Config` with `proxy = Some("http://127.0.0.1:8080")`.  
  *Expected Output*: `config.proxy.unwrap() == "http://127.0.0.1:8080"`.  
  *Authoritative Source*: `docs/design.md` D-04, D-21.
- **`T1-F13-02`**: **Unconditional Proxy (`proxy_all`) Model Verification**  
  *Input*: Construct `Config` with `proxy_all = true` and valid `proxy` target.  
  *Expected Output*: `config.proxy_all == true`.  
  *Authoritative Source*: `bin/http-server`, `docs/design.md` D-04.
- **`T1-F13-03`**: **Rule-Based Proxy Configuration Model (`proxy_rules`)**  
  *Input*: Construct `ProxyRule` with `pattern = "/api/**"`, `target = "http://api.local"`, `path_rewrite = [("^/api", "")]`.  
  *Expected Output*: Fields parsed and preserved correctly in `Config`.  
  *Authoritative Source*: `test/proxy-config.test.js`.
- **`T1-F13-04`**: **Proxy Options Model (`ProxyOptions`)**  
  *Input*: Construct `ProxyOptions` with `secure = false`, `change_origin = true`, `timeout_ms = 5000`.  
  *Expected Output*: Properties match configured values.  
  *Authoritative Source*: `test/proxy-options.test.js`.
- **`T1-F13-05`**: **WebSocket Proxy Flag Model**  
  *Input*: Construct `Config` with `websocket = true` and `proxy = Some("http://127.0.0.1:8080")`.  
  *Expected Output*: `config.websocket == true`.  
  *Authoritative Source*: `test/websocket-proxy.test.js`.

### Feature 14: Reverse Proxy State Machine & Forwarding (`F14`)
*Target: `server` / `core` | Source: `ORIGINAL_REQUEST.md` §R4, `docs/design.md` D-05, D-21*

- **`T1-F14-01`**: **Static 404 Transition to Proxying State**  
  *Input*: Request URL `/missing-file.html` on server configured with `--proxy http://upstream:3000`.  
  *Expected Output*: Engine detects file missing on disk; connection state transitions to `Proxying`; forwards to upstream.  
  *Authoritative Source*: `docs/design.md` D-05, C039.01.
- **`T1-F14-02`**: **Direct Proxying Transition via `proxy_all`**  
  *Input*: Request URL `/index.html` on server configured with `--proxy-all --proxy http://upstream:3000`.  
  *Expected Output*: Skips local file search entirely; transitions immediately from `Resolving` to `Proxying`.  
  *Authoritative Source*: `test/proxy-all.test.js`, C037.02.
- **`T1-F14-03`**: **WebSocket Tunnel Transition**  
  *Input*: Send HTTP `GET /chat` with `Upgrade: websocket` and `Connection: Upgrade` when `--websocket` is active.  
  *Expected Output*: Receives 101 Switching Protocols; state machine transitions from `Proxying` to `Tunnel`.  
  *Authoritative Source*: `test/websocket-proxy.test.js`, C040.01.
- **`T1-F14-04`**: **Hop-by-Hop Header Stripping**  
  *Input*: Client sends `Keep-Alive: timeout=5` and `Proxy-Authorization: ...`.  
  *Expected Output*: Forwarder strips hop-by-hop headers per RFC 9110 before transmitting upstream.  
  *Authoritative Source*: RFC 9110 §7.6.1, `docs/design.md` D-21.
- **`T1-F14-05`**: **Forwarded Header Injection**  
  *Input*: Client at `192.168.1.50` connects and forwards request.  
  *Expected Output*: Upstream receives `X-Forwarded-For: 192.168.1.50` and `X-Forwarded-Proto: http`.  
  *Authoritative Source*: RFC 7239 / RFC 9110, `docs/design.md` D-21.

### Feature 15: SDD Documentation & ADR Update (`F15`)
*Target: `docs/` | Source: `ORIGINAL_REQUEST.md` §R4, `docs/design.md` D-20, D-21*

- **`T1-F15-01`**: **Design Section D-20 (Layered Thin/Full Architecture)**  
  *Input*: Verify presence of section `D-20` in `docs/design.md`.  
  *Expected Output*: Contains packaging rationale, dependency boundary, and Transport/Acceptor specification.  
  *Authoritative Source*: `ORIGINAL_REQUEST.md` §R4.
- **`T1-F15-02`**: **Design Section D-21 (Reverse Proxy Specification)**  
  *Input*: Verify presence of section `D-21` in `docs/design.md`.  
  *Expected Output*: Contains routing priority tree, state machine diagram, and streaming backpressure rules.  
  *Authoritative Source*: `ORIGINAL_REQUEST.md` §R4.
- **`T1-F15-03`**: **Tasks Sync in `docs/tasks.md`**  
  *Input*: Check tasks T-011 through T-015 in `docs/tasks.md`.  
  *Expected Output*: Dependencies, deliverables, and acceptance criteria updated to reflect thin/full & proxy readiness.  
  *Authoritative Source*: `docs/tasks.md`.
- **`T1-F15-04`**: **C ABI Documentation Parity**  
  *Input*: Check D-07 & D-11 in `docs/design.md`.  
  *Expected Output*: Documents all 14 `hs_*` APIs and error code definitions matching code.  
  *Authoritative Source*: `docs/design.md` D-07, D-11.
- **`T1-F15-05`**: **Reference Commit Cross-Reference Alignment**  
  *Input*: Check references to `http-party/http-server` @ `0d3b7bb5`.  
  *Expected Output*: Test cases C037-C041 accurately mapped to upstream files.  
  *Authoritative Source*: `docs/proposal.md`, `spec_report.md`.

### Feature 16: Comprehensive E2E Verification & Multi-Role Gates (`F16`)
*Target: Full Workspace | Source: `ORIGINAL_REQUEST.md` §Acceptance Criteria*

- **`T1-F16-01`**: **Full Test Suite Execution (100% Pass)**  
  *Input*: Execute `moon test --target native`.  
  *Expected Output*: All test cases pass with 0 failures and 0 panics.  
  *Authoritative Source*: `ORIGINAL_REQUEST.md` §Acceptance Criteria.
- **`T1-F16-02`**: **Independent Reviewer Contract Audit**  
  *Input*: Reviewer audits code diff against `docs/design.md` D-20 and D-21.  
  *Expected Output*: Reviewer issues `APPROVE` with line-level evidence.  
  *Authoritative Source*: `AGENTS.md` SDD workflow.
- **`T1-F16-03`**: **Independent Challenger Stress Verification**  
  *Input*: Challenger executes adversarial suite (`server_challenger_*.mbt`).  
  *Expected Output*: Pass with 0 hangs, 0 deadlocks, 0 crashes.  
  *Authoritative Source*: `AGENTS.md` SDD workflow.
- **`T1-F16-04`**: **Forensic Auditor License & Resource Audit**  
  *Input*: Auditor scans workspace licenses and Win32 handle counters.  
  *Expected Output*: 100% MIT/Apache-2.0 licenses, 0 GPL, 0 handle leaks.  
  *Authoritative Source*: `AGENTS.md` SDD workflow.
- **`T1-F16-05`**: **Local Git Commit Gate (No Push)**  
  *Input*: Run `git status` and create local commit.  
  *Expected Output*: Working directory clean; commit created locally; strictly zero remote push executed.  
  *Authoritative Source*: `ORIGINAL_REQUEST.md` §Git Workflow.

---

## 5. Tier 2: Boundary & Corner Cases (80 Test Cases)

### Feature 1: Server TLS Decoupling (`F01`)
- **`T2-F01-01`**: **Immediate Client Disconnect Post-TCP Handshake**  
  *Boundary*: Client opens TCP connection and immediately calls `close()` without transmitting bytes.  
  *Expected Behavior*: `Transport` detects EOF, releases resources immediately, 0 unhandled exceptions.  
  *Authoritative Source*: `docs/design.md` D-05.
- **`T2-F01-02`**: **Acceptor Error During Connection Ingestion**  
  *Boundary*: Custom `Acceptor` returns `Err` on `accept()`.  
  *Expected Behavior*: Server logs debug/error, closes the faulted socket, and continues listening for new connections.  
  *Authoritative Source*: `docs/design.md` D-02.
- **`T2-F01-03`**: **High-Frequency Connect-Close Loop (Handle Leak Check)**  
  *Boundary*: 100 consecutive connections opened and closed without sending HTTP payload.  
  *Expected Behavior*: Win32 `GetProcessHandleCount` before and after differs by 0.  
  *Authoritative Source*: `server/server_test.mbt` handle leak invariant.
- **`T2-F01-04`**: **Slow Byte Trickle (Slowloris) Read Timeout**  
  *Boundary*: Client sends 1 byte every 500ms; exceeds configured server read timeout.  
  *Expected Behavior*: Server times out connection cleanly, closes socket, no hang.  
  *Authoritative Source*: RFC 9112 §2.2, `docs/design.md` AD-03.
- **`T2-F01-05`**: **Concurrent Connection Saturation**  
  *Boundary*: 50 concurrent connections open simultaneously through `PlainAcceptor`.  
  *Expected Behavior*: All requests served correctly without cross-talk or socket descriptor collision.  
  *Authoritative Source*: `server/server_fault_injection_test.mbt`.

### Feature 2: TLS Dependency Injection (`F02`)
- **`T2-F02-01`**: **Plaintext HTTP Request on HTTPS Port**  
  *Boundary*: Plaintext `GET / HTTP/1.1` sent to `TlsAcceptor` port.  
  *Expected Behavior*: MbedTLS TLS handshake parser fails cleanly; connection reset or closed; server does not crash.  
  *Authoritative Source*: `docs/design.md` D-08.
- **`T2-F02-02`**: **Corrupted TLS ClientHello Record**  
  *Boundary*: Client sends random garbage bytes with TLS record header `0x16 0x03 0x01`.  
  *Expected Behavior*: Handshake terminates with TLS alert; server remains healthy.  
  *Authoritative Source*: RFC 8446 §6.
- **`T2-F02-03`**: **Client Abrupt Termination Mid-Handshake**  
  *Boundary*: Client closes socket after receiving `ServerHello` before completing key exchange.  
  *Expected Behavior*: Server frees partially initialized SSL session; 0 handle leaks.  
  *Authoritative Source*: `tls/loopback_test.mbt`.
- **`T2-F02-04`**: **Passphrase-Protected Key with Invalid Passphrase**  
  *Boundary*: Load encrypted key `server_key_enc.pem` with incorrect password `"wrongpass"`.  
  *Expected Behavior*: `TlsAcceptor::new` fails before listening with configuration error.  
  *Authoritative Source*: `docs/design.md` D-08.
- **`T2-F02-05`**: **Mismatched Certificate and Key Pair**  
  *Boundary*: Load `other_cert.pem` paired with `server_key.pem`.  
  *Expected Behavior*: Acceptor initialization or first handshake detects public/private key mismatch and errors cleanly.  
  *Authoritative Source*: `docs/design.md` D-08.

### Feature 3: Zero Test Regression (`F03`)
- **`T2-F03-01`**: **100-Request Sequential TransmitFile Handle Leak Test**  
  *Boundary*: 100 sequential requests for 1MB file served via `TransmitFile` zero-copy.  
  *Expected Behavior*: `GetProcessHandleCount` before and after is identical (delta == 0).  
  *Authoritative Source*: `server/server_test.mbt`.
- **`T2-F03-02`**: **C016 Empty Directory vs Custom 404 Precedence**  
  *Boundary*: Directory `empty_dir` accessed with `autoIndex=false` and custom `404.html` present.  
  *Expected Behavior*: Serves 403 Forbidden or custom 404 per exact C016 contract without regression.  
  *Authoritative Source*: C016 migration contract.
- **`T2-F03-03`**: **SPA Terminal 404 When Fallback File Missing on Disk**  
  *Boundary*: `--spa` enabled but `index.html` does not exist on disk.  
  *Expected Behavior*: Returns raw terminal 404 (`"File not found. :("`) instead of recursive fallback loop.  
  *Authoritative Source*: `docs/design.md` D-04 §5.
- **`T2-F03-04`**: **Out-of-Range HTTP Range 416 Header Validation**  
  *Boundary*: Request with `Range: bytes=5000-6000` on 100-byte file.  
  *Expected Behavior*: Status 416 Range Not Satisfiable, `Content-Range: bytes */100`.  
  *Authoritative Source*: RFC 9110 §14.4.
- **`T2-F03-05`**: **Pre-compressed `.br` and `.gz` Suffix Escaping**  
  *Boundary*: Request for `bundle.js` with `Accept-Encoding: gzip, br` when both `.br` and `.gz` exist.  
  *Expected Behavior*: Brotli chosen by priority; `Content-Encoding: br` returned with correct uncompressed Content-Type.  
  *Authoritative Source*: `docs/design.md` D-03.

### Feature 4: CLI Shared Helpers (`F04`)
- **`T2-F04-01`**: **Port Out of Range (0, 65536, -1)**  
  *Boundary*: Pass `--port 70000` or `--port -5`.  
  *Expected Behavior*: Returns `Err("invalid port number: must be between 1 and 65535")`.  
  *Authoritative Source*: `cmd/http-server-mbt/cli_wbtest.mbt`.
- **`T2-F04-02`**: **Non-Existent Root Path**  
  *Boundary*: Pass positional root `non_existent_folder_xyz_123`.  
  *Expected Behavior*: Returns `Err("root directory does not exist")`.  
  *Authoritative Source*: `cmd/http-server-mbt/cli_wbtest.mbt`.
- **`T2-F04-03`**: **Conflicting Routing Flags (`--spa` + `--try-files`)**  
  *Boundary*: Pass both `--spa` and `--try-files fallback.html`.  
  *Expected Behavior*: Returns `Err("conflicting routing options: cannot specify both --spa and --try-files")`.  
  *Authoritative Source*: `docs/design.md` D-04.
- **`T2-F04-04`**: **Malformed `--auth` String Without Colon**  
  *Boundary*: Pass `--auth username_without_password`.  
  *Expected Behavior*: Returns `Err("invalid auth format: expected username:password")`.  
  *Authoritative Source*: `cmd/http-server-mbt/cli_wbtest.mbt`.
- **`T2-F04-05`**: **Duplicate Flag Specification**  
  *Boundary*: Pass `--port 8080 -p 9090`.  
  *Expected Behavior*: Last specified value wins or error returned cleanly without panic.  
  *Authoritative Source*: `bin/http-server`.

### Feature 5: Thin CLI Executable (`F05`)
- **`T2-F05-01`**: **Binary Size Measurement vs Full**  
  *Boundary*: Measure `http-server-mbt-thin.exe` size vs `http-server-full.exe`.  
  *Expected Behavior*: `http-server-mbt-thin.exe` is measurably smaller by at least 500 KB due to 0 MbedTLS C stubs.  
  *Authoritative Source*: `ORIGINAL_REQUEST.md` §Acceptance Criteria.
- **`T2-F05-02`**: **Zero MbedTLS C File Compilation Log Audit**  
  *Boundary*: Inspect build log for `cmd/http-server-mbt-thin`.  
  *Expected Behavior*: Zero occurrences of `ssl_*.c`, `psa_*.c`, `aes.c`, or `tls_bridge.c`.  
  *Authoritative Source*: `ORIGINAL_REQUEST.md` §Acceptance Criteria.
- **`T2-F05-03`**: **Port Collision on Startup**  
  *Boundary*: Start `http-server-mbt-thin` on a port already bound by another process.  
  *Expected Behavior*: Exits with code 1; stderr informs user that port is already in use.  
  *Authoritative Source*: `docs/design.md` D-08.
- **`T2-F05-04`**: **Path Traversal Defense in Thin CLI**  
  *Boundary*: Send `GET /../../windows/win.ini HTTP/1.1`.  
  *Expected Behavior*: Intercepted before disk access; returns 403 Forbidden or 404 Not Found.  
  *Authoritative Source*: `docs/design.md` D-01, D-16.
- **`T2-F05-05`**: **Graceful Exit on SIGINT (Ctrl+C)**  
  *Boundary*: Send SIGINT / `GenerateConsoleCtrlEvent` to running process.  
  *Expected Behavior*: Process catches signal, stops listener, drains in-flight requests, and exits 0 with 0 leaks.  
  *Authoritative Source*: `ORIGINAL_REQUEST.md` §R1 (Milestone 5).

### Feature 6: Thin CLI Preflight Rejection (`F06`)
- **`T2-F06-01`**: **Rejection of Short Flags `-S` (SSL) in Thin CLI**  
  *Boundary*: Run `http-server-mbt-thin -S`.  
  *Expected Behavior*: Exit code 1; stderr identifies `-S` as unsupported in thin build.  
  *Authoritative Source*: `docs/design.md` D-08.
- **`T2-F06-02`**: **Rejection of `--key-passphrase` in Thin CLI**  
  *Boundary*: Run `http-server-mbt-thin --key-passphrase secret`.  
  *Expected Behavior*: Exit code 1; stderr states `--key-passphrase is not supported in this build`.  
  *Authoritative Source*: `docs/design.md` D-08.
- **`T2-F06-03`**: **Rejection of `--websocket` in Thin CLI**  
  *Boundary*: Run `http-server-mbt-thin --websocket`.  
  *Expected Behavior*: Exit code 1; stderr states `--websocket is not supported in this build`.  
  *Authoritative Source*: `docs/design.md` D-08.
- **`T2-F06-04`**: **Preflight Port Integrity: No Port Bound on Rejected Flag**  
  *Boundary*: Run `http-server-mbt-thin --port 9999 --proxy http://target.local`.  
  *Expected Behavior*: Process exits 1 immediately; port 9999 is NEVER opened.  
  *Authoritative Source*: `ORIGINAL_REQUEST.md` §R2, `spec_report.md` E-17.
- **`T2-F06-05`**: **Stderr Diagnostic Quality & Hinting**  
  *Boundary*: Run `http-server-mbt-thin --cert foo.crt`.  
  *Expected Behavior*: Stderr explicitly mentions `Use http-server-full for TLS/HTTPS and Proxy features`.  
  *Authoritative Source*: `spec_report.md` §5.2.

### Feature 7: Full CLI Executable (`F07`)
- **`T2-F07-01`**: **`--cert` Provided Without `--key`**  
  *Boundary*: Run `http-server-full --cert server.crt`.  
  *Expected Behavior*: Exits with code 1 before listening; stderr states `--cert requires --key`.  
  *Authoritative Source*: `bin/http-server`, `docs/design.md` D-08.
- **`T2-F07-02`**: **`--key` Provided Without `--cert`**  
  *Boundary*: Run `http-server-full --key server.key`.  
  *Expected Behavior*: Exits with code 1 before listening; stderr states `--key requires --cert`.  
  *Authoritative Source*: `bin/http-server`, `docs/design.md` D-08.
- **`T2-F07-03`**: **Missing / Unreadable Certificate File**  
  *Boundary*: Run `http-server-full --cert non_existent_cert.crt --key valid_key.key`.  
  *Expected Behavior*: Exits with code 1 before listening; stderr specifies file not found.  
  *Authoritative Source*: `docs/design.md` D-08.
- **`T2-F07-04`**: **Corrupted PEM Certificate Data**  
  *Boundary*: Pass a corrupted text file as `--cert`.  
  *Expected Behavior*: MbedTLS certificate parsing returns error; process exits 1 before listening.  
  *Authoritative Source*: `docs/design.md` D-08.
- **`T2-F07-05`**: **`--proxy-all` Without `--proxy` in Full CLI**  
  *Boundary*: Run `http-server-full --proxy-all`.  
  *Expected Behavior*: Exits with code 1 before listening; stderr: `Error: --proxy-all requires --proxy to be set`.  
  *Authoritative Source*: `bin/http-server`:303-317, `test/proxy-all.test.js`.

### Feature 8: C ABI Interface Definition (`F08`)
- **`T2-F08-01`**: **Null Pointer Handling in `hs_abi_version`**  
  *Boundary*: Call `hs_abi_version(NULL, NULL)`.  
  *Expected Behavior*: Returns `HS_ERR_INVALID_ARGUMENT` (-2) safely without crash.  
  *Authoritative Source*: `docs/design.md` D-07.
- **`T2-F08-02`**: **Malformed JSON in `hs_server_create`**  
  *Boundary*: Pass invalid JSON string `"{invalid json..."` with explicit length.  
  *Expected Behavior*: Returns NULL; sets `*err_out = HS_ERR_CONFIG` (-1).  
  *Authoritative Source*: `docs/design.md` D-07.
- **`T2-F08-03`**: **Idempotent / Redundant Server Release**  
  *Boundary*: Call `hs_server_release(server)` twice on the same pointer.  
  *Expected Behavior*: First call frees; second call safely ignores or logs without crash.  
  *Authoritative Source*: `docs/design.md` D-07, D-11.
- **`T2-F08-04`**: **Buffer Truncation in `hs_error_copy`**  
  *Boundary*: Pass 5-byte buffer to `hs_error_copy(HS_ERR_CONFIG, buf, 5)`.  
  *Expected Behavior*: Copies first 4 chars + null terminator; returns full length needed.  
  *Authoritative Source*: `docs/design.md` D-07.
- **`T2-F08-05`**: **Double Start Error (`HS_ERR_BUSY`)**  
  *Boundary*: Call `hs_server_start_async` on a server instance that is already active.  
  *Expected Behavior*: Returns `HS_ERR_BUSY` (-10); existing server continues running normally.  
  *Authoritative Source*: `docs/design.md` D-07.

### Feature 9: C ABI `.mbtx` Build Pipeline (`F09`)
- **`T2-F09-01`**: **Invalid Pipeline CLI Arguments**  
  *Boundary*: Run `moon run scripts/build_cabi.mbtx -- --variant invalid_mode`.  
  *Expected Behavior*: Script exits with code 1 and prints valid variant options (`thin`, `full`).  
  *Authoritative Source*: `scripts/build_cabi.mbtx`.
- **`T2-F09-02`**: **Clean Directory Creation If Missing**  
  *Boundary*: Target directory `target/cabi` does not exist prior to build.  
  *Expected Behavior*: Script creates directory structure automatically and succeeds.  
  *Authoritative Source*: `scripts/build_cabi.mbtx`.
- **`T2-F09-03`**: **Compiler Toolchain Auto-Detection Failure Graceful Exit**  
  *Boundary*: Neither MSVC (`cl.exe`) nor GCC/Clang is available in PATH.  
  *Expected Behavior*: Script terminates with clear diagnostic: `No compatible C compiler found in PATH`.  
  *Authoritative Source*: `scripts/build_cabi.mbtx`.
- **`T2-F09-04`**: **Deterministic Rebuilds (Idempotence)**  
  *Boundary*: Run build pipeline twice consecutively without modifying source.  
  *Expected Behavior*: Second run succeeds; artifacts remain intact and valid.  
  *Authoritative Source*: `PROJECT.md` §Automation.
- **`T2-F09-05`**: **Custom Output Path Parameter (`--out-dir`)**  
  *Boundary*: Pass `--out-dir custom_build/cabi`.  
  *Expected Behavior*: Libraries and header are generated inside specified custom folder.  
  *Authoritative Source*: `scripts/build_cabi.mbtx`.

### Feature 10: Clean Symbol Isolation (`F10`)
- **`T2-F10-01`**: **Static Library Link with Host Defining `int main()`**  
  *Boundary*: C application with `int main(int argc, char** argv)` links `http_server_mbt_min_static.lib`.  
  *Expected Behavior*: Links without linker error `LNK2005: main already defined`.  
  *Authoritative Source*: `ORIGINAL_REQUEST.md` §R3.
- **`T2-F10-02`**: **Absence of `WinMain` and `wmain` in Static Archives**  
  *Boundary*: Inspect object files inside `http_server_mbt_min_static.lib` for GUI/Unicode entrypoints.  
  *Expected Behavior*: Neither `WinMain` nor `wmain` is defined.  
  *Authoritative Source*: `docs/design.md` D-07, D-11.
- **`T2-F10-03`**: **Global Variable Name Collision Immunity**  
  *Boundary*: Host defines global variables `int port; int server; int client;`.  
  *Expected Behavior*: No collision with library internals due to static isolation or namespacing.  
  *Authoritative Source*: `docs/design.md` D-07.
- **`T2-F10-04`**: **Exact Case Matching in Module Definition (`.def`)**  
  *Boundary*: Check case sensitivity of exported symbols in `.def` file.  
  *Expected Behavior*: Exactly matches C declaration `hs_abi_version`, `hs_server_create`, etc.  
  *Authoritative Source*: `docs/design.md` D-07.
- **`T2-F10-05`**: **Absence of C++ Mangling in Exports**  
  *Boundary*: Inspect exports for mangling patterns (e.g. `?hs_` or `_Z`).  
  *Expected Behavior*: All exports are undecorated C names wrapped in `extern "C"`.  
  *Authoritative Source*: `docs/design.md` D-07.

### Feature 11: Thin C Library Zero Crypto (`F11`)
- **`T2-F11-01`**: **Absence of TLS Cipher Suite Strings in Binary**  
  *Boundary*: Scan raw strings of `http_server_mbt_min.dll` for `TLS_AES_` or `Mbed TLS`.  
  *Expected Behavior*: Zero occurrences found in binary image.  
  *Authoritative Source*: `ORIGINAL_REQUEST.md` §R3.
- **`T2-F11-02`**: **Minimal OS Dynamic Library Dependencies**  
  *Boundary*: Run `dumpbin /DEPENDENTS http_server_mbt_min.dll`.  
  *Expected Behavior*: Depends only on Windows core libraries (`KERNEL32.dll`, `WS2_32.dll`, `MSVCRT.dll`), 0 crypto DLLs.  
  *Authoritative Source*: `docs/design.md` D-07.
- **`T2-F11-03`**: **Binary Footprint Strict Threshold Check**  
  *Boundary*: Measure uncompressed size of `http_server_mbt_min.dll`.  
  *Expected Behavior*: Binary size is under 2.5 MB.  
  *Authoritative Source*: `ORIGINAL_REQUEST.md` §R3.
- **`T2-F11-04`**: **Static Archive Size Threshold Check**  
  *Boundary*: Measure size of `http_server_mbt_min_static.lib`.  
  *Expected Behavior*: Static library archive size is under 5.0 MB.  
  *Authoritative Source*: `ORIGINAL_REQUEST.md` §R3.
- **`T2-F11-05`**: **Attempt to Invoke Crypto FFI in Thin Build**  
  *Boundary*: Test invoking an internal crypto symbol if referenced.  
  *Expected Behavior*: Linker error at build time; impossible to build crypto into thin build.  
  *Authoritative Source*: `ORIGINAL_REQUEST.md` §R3.

### Feature 12: C ABI Test Program Verification (`F12`)
- **`T2-F12-01`**: **Rapid 20-Cycle Server Create/Start/Stop/Release Cycle**  
  *Boundary*: Loop 20 times creating, starting on port 0, stopping, and releasing server instance.  
  *Expected Behavior*: All 20 cycles succeed; memory and Win32 handle counters remain flat.  
  *Authoritative Source*: `docs/design.md` D-07, D-16.
- **`T2-F12-02`**: **Comprehensive Error Code Copy Coverage**  
  *Boundary*: Iterate through all error codes `-1` to `-11` calling `hs_error_copy`.  
  *Expected Behavior*: Each returns a meaningful, descriptive English error message.  
  *Authoritative Source*: `docs/design.md` D-07.
- **`T2-F12-03`**: **Asynchronous Operation Cancellation (`hs_operation_cancel`)**  
  *Boundary*: Submit an engine operation and immediately cancel it before completion.  
  *Expected Behavior*: Callback receives status `HS_ERR_CANCELLED` (-6); resources freed.  
  *Authoritative Source*: `docs/design.md` D-07.
- **`T2-F12-04`**: **Server Bind to Ephemeral Port 0**  
  *Boundary*: Pass `"port": 0` in config JSON to `hs_server_create`.  
  *Expected Behavior*: Server binds to OS-assigned ephemeral port; start callback reports `actual_port > 1024`.  
  *Authoritative Source*: `docs/design.md` D-07.
- **`T2-F12-05`**: **Release Server While Running (Forced Teardown)**  
  *Boundary*: Call `hs_server_release` without explicitly calling `hs_server_stop_async`.  
  *Expected Behavior*: Library closes listening socket and drains gracefully before freeing; no crash.  
  *Authoritative Source*: `docs/design.md` D-07.

### Feature 13: Reverse Proxy Configuration Model (`F13`)
- **`T2-F13-01`**: **Missing Protocol Scheme in `--proxy` URL**  
  *Boundary*: Configure proxy with `google.com` or `localhost:8080` (missing `http://`).  
  *Expected Behavior*: Validation fails with `ConfigError::InvalidProxy("missing protocol scheme")`.  
  *Authoritative Source*: `cli.test.js:107-118`, `spec_report.md` E-01.
- **`T2-F13-02`**: **Proxy Port Out of Range (99999)**  
  *Boundary*: Configure proxy with `http://127.0.0.1:99999`.  
  *Expected Behavior*: Validation fails with `ConfigError::InvalidProxy("port out of range")`.  
  *Authoritative Source*: `docs/design.md` AD-07, `spec_report.md` E-02.
- **`T2-F13-03`**: **Mutual Exclusion: `--proxy-all` and `--proxy-config`**  
  *Boundary*: Set both `proxy_all = true` and `proxy_rules` non-empty.  
  *Expected Behavior*: Validation fails with `ConfigError::ConflictingRouting`.  
  *Authoritative Source*: `bin/http-server`:303-312, `spec_report.md` E-05.
- **`T2-F13-04`**: **Mutual Exclusion: Proxy Mode Combined with `--spa`**  
  *Boundary*: Set `proxy = Some(...)` and `spa = true`.  
  *Expected Behavior*: Validation fails with `ConfigError::ConflictingRouting("cannot combine proxy with spa")`.  
  *Authoritative Source*: `docs/design.md` D-04 lines 123-128, `spec_report.md` E-08.
- **`T2-F13-05`**: **Non-Existent or Invalid JSON in `proxy-config`**  
  *Boundary*: Pass file path pointing to malformed JSON or empty object `{}`.  
  *Expected Behavior*: Validation fails with `ConfigError::InvalidProxyConfig`.  
  *Authoritative Source*: `bin/http-server`:282-297, `spec_report.md` E-06.

### Feature 14: Reverse Proxy State Machine & Forwarding (`F14`)
- **`T2-F14-01`**: **Upstream Target Unreachable (502 Bad Gateway)**  
  *Boundary*: Upstream target is down (connection refused on upstream port).  
  *Expected Behavior*: Proxy returns 502 Bad Gateway to client; main server process remains alive and healthy.  
  *Authoritative Source*: `server.mbt:345-352`, `spec_report.md` E-11.
- **`T2-F14-02`**: **Upstream Connect Timeout (504 Gateway Timeout)**  
  *Boundary*: Upstream host drops SYN packets; connection attempt exceeds `timeout_ms`.  
  *Expected Behavior*: Proxy returns 504 Gateway Timeout to client, cleans up sockets.  
  *Authoritative Source*: RFC 9110 §15.6.5, `docs/design.md` D-21.
- **`T2-F14-03`**: **Client Disconnect During Upstream Body Stream**  
  *Boundary*: Client terminates TCP connection while proxy is streaming 5MB body from upstream.  
  *Expected Behavior*: Proxy aborts upstream connection immediately; releases all sockets with 0 leaks.  
  *Authoritative Source*: `docs/design.md` D-16, `spec_report.md` E-15.
- **`T2-F14-04`**: **Streaming Chunked Transfer Encoding with Backpressure**  
  *Boundary*: Upstream sends 10MB chunked response; client socket read buffer fills up (slow reader).  
  *Expected Behavior*: Backpressure pauses reads from upstream socket until client buffer drains; memory usage bounded <= 64KB.  
  *Authoritative Source*: `docs/design.md` D-16, D-21.
- **`T2-F14-05`**: **WebSocket Connection Drop Mid-Session**  
  *Boundary*: Upstream closes WebSocket connection abruptly during full-duplex session.  
  *Expected Behavior*: Proxy sends close frame to client or closes socket cleanly; all tunnel handles freed.  
  *Authoritative Source*: `test/websocket-proxy.test.js` C040.04.

### Feature 15: SDD Documentation & ADR Update (`F15`)
- **`T2-F15-01`**: **Zero Broken Relative Links in `docs/`**  
  *Boundary*: Run link validator script over all Markdown files in `docs/`.  
  *Expected Behavior*: 0 broken relative links, 0 dead file references.  
  *Authoritative Source*: `AGENTS.md` SDD workflow.
- **`T2-F15-02`**: **Routing Priority Precedence Unambiguity**  
  *Boundary*: Review table in D-21 for ambiguous priority overlaps.  
  *Expected Behavior*: Explicit ordering: `proxy_all` > `proxy_config` > static file > `proxy` fallback > 404.  
  *Authoritative Source*: `spec_report.md` §4.1.
- **`T2-F15-03`**: **C ABI Error Code Completeness Audit**  
  *Boundary*: Cross-reference `HS_ERR_*` in D-07 with C header `http_server_mbt.h`.  
  *Expected Behavior*: 1:1 match across all 11 error codes without omission.  
  *Authoritative Source*: `docs/design.md` D-07.
- **`T2-F15-04`**: **Strict Separation of Native and Wasm Commitments**  
  *Boundary*: Inspect D-20 for platform-specific claims.  
  *Expected Behavior*: Clear boundary: TransmitFile/IOCP is Native-only; wasm-gc core is separate.  
  *Authoritative Source*: `AGENTS.md` Native / FFI rules.
- **`T2-F15-05`**: **Tasks Sync Verification**  
  *Boundary*: Verify that completed tasks have attached evidence and open tasks have dependencies.  
  *Expected Behavior*: Tasks format conforms strictly to `AGENTS.md` SDD requirements.  
  *Authoritative Source*: `AGENTS.md`.

### Feature 16: Comprehensive E2E Verification & Multi-Role Gates (`F16`)
- **`T2-F16-01`**: **Challenger 200-Connection Concurrency Storm**  
  *Boundary*: 200 concurrent HTTP requests flooded to server over 5 seconds.  
  *Expected Behavior*: All requests handled or rejected with 503; 0 panics, 0 crashes, process remains responsive.  
  *Authoritative Source*: `server/server_challenger_m6_test.mbt`.
- **`T2-F16-02`**: **Win32 Handle Monotonicity Audit Under Load**  
  *Boundary*: Query `GetProcessHandleCount` before, during, and after 500 requests.  
  *Expected Behavior*: Handle count returns to baseline after idle period; no monotonic growth.  
  *Authoritative Source*: `server/handle_leak_assert_test.mbt`.
- **`T2-F16-03`**: **Peak Memory Consumption Boundedness Check**  
  *Boundary*: Measure process private working set during 50MB file transfer.  
  *Expected Behavior*: Process memory remains flat (< 30 MB) due to zero-copy or bounded 64KB buffering.  
  *Authoritative Source*: `docs/design.md` D-16.
- **`T2-F16-04`**: **Zero Compiler Warnings (`0 warnings, 0 errors`)**  
  *Boundary*: Run `moon check --target native` across all packages.  
  *Expected Behavior*: Exactly 0 errors and 0 warnings in compilation output.  
  *Authoritative Source*: `ORIGINAL_REQUEST.md` §Acceptance Criteria.
- **`T2-F16-05`**: **Verification of Git Commit Purity (No Push)**  
  *Boundary*: Run `git status` and inspect git reflog.  
  *Expected Behavior*: Working directory is 100% clean; last commit message matches mandated pattern; 0 pushes executed.  
  *Authoritative Source*: `ORIGINAL_REQUEST.md` §Git Workflow.

---

## 6. Tier 3: Cross-Feature Combinations (Pairwise Interactions)

Tier 3 tests focus on the boundary surfaces where multiple features intersect:

| Pairwise Combo | Interacting Features | Test Scenario & Verification Objective | Expected Behavior |
|---|---|---|---|
| **`C3-01`** | `F05` (Thin CLI) × `F06` (Preflight Rejection) | User passes `--proxy` and `--cert` simultaneously to `http-server-mbt-thin`. | Both flags detected; preflight halts before listening with clear diagnostic and exit code 1. |
| **`C3-02`** | `F05` (Thin CLI) × `F04` (CLI Helpers) | User passes complex valid static options (`--port 9090 -a user:pass --spa -c 3600`) to `http-server-mbt-thin`. | Parses completely; starts static SPA server with Basic Auth and caching without errors. |
| **`C3-03`** | `F07` (Full CLI) × `F02` (TLS Injection) × `F13` (Proxy Model) | User launches `http-server-full` with both TLS (`--cert`, `--key`) and proxy fallback (`--proxy http://upstream`). | Starts HTTPS server; serves local files over HTTPS; proxies cache misses to upstream over HTTP/HTTPS. |
| **`C3-04`** | `F01` (Acceptor Abstraction) × `F03` (Zero Regression) | Run existing 183 tests after decoupling `server` from `tls` via `Acceptor`. | 100% pass; no regressions in TransmitFile, Range requests, or directory listings. |
| **`C3-05`** | `F08` (C ABI Interface) × `F10` (Symbol Isolation) | Compile C program that declares its own `int main()` and links dynamic library `http_server_mbt_min.dll`. | Compiles and links cleanly with zero symbol collisions; calls `hs_abi_version` successfully. |
| **`C3-06`** | `F09` (C ABI Build Pipeline) × `F11` (Thin Zero Crypto) | Run `build_cabi.mbtx` for `thin` dynamic and static libraries, then immediately run `verify_zero_crypto.mbtx`. | Build succeeds and symbol scan verifies 0 `mbedtls_*` / 0 `psa_*` symbols in both artifacts. |
| **`C3-07`** | `F13` (Proxy Model) × `F14` (Proxy State Machine) | Run fallback proxy when local directory contains `index.html` but lacks `data.json`. | `GET /index.html` returns 200 from local disk; `GET /data.json` returns 200 from upstream proxy target. |
| **`C3-08`** | `F13` (Proxy Model) × `F14` (Proxy State Machine) × `F07` (Full CLI) | Run `http-server-full --proxy-all http://upstream` with local `index.html` present. | `GET /index.html` completely bypasses local disk and returns response from upstream. |
| **`C3-09`** | `F08` (C ABI Interface) × `F14` (Proxy State Machine) | Embedded host starts server via C ABI with JSON config configuring upstream proxy target. | Requests submitted to embedded server are proxied to upstream target with streaming responses. |
| **`C3-10`** | `F02` (TLS Injection) × `F16` (Handle Leak Assert) | HTTPS client performs 50 consecutive TLS transactions against server with `TlsAcceptor`. | `GetProcessHandleCount` before and after matches with 0 handle increase. |

---

## 7. Tier 4: Real-World Application Scenarios

Tier 4 exercises complete production workflows end-to-end:

### Scenario 1: Production Static SPA Deployment with Thin CLI (`S4-01`)
- **Use Case**: Embedded device or lightweight container deploying a Single-Page Application (React/Vue/Svelte) using the zero-crypto minimal binary.
- **Workflow**:
  1. Launch `http-server-mbt-thin -p 0 --spa --cache 86400 --cors testdata/public`.
  2. Client fetches `/index.html` → receives 200 OK with `Cache-Control: max-age=86400` and `Access-Control-Allow-Origin: *`.
  3. Client fetches deeply nested synthetic client-side route `/user/profile/settings`.
  4. Local file system does not have this file; `--spa` gracefully rewrites and serves `/index.html` with status 200 OK.
  5. Client fetches non-existent asset with file extension `/assets/missing.png` → returns 404 (file extensions bypass SPA fallback).
  6. Terminate process with SIGINT; verify clean shutdown and 0 socket leaks.

### Scenario 2: High-Security HTTPS Production Server with Full CLI (`S4-02`)
- **Use Case**: Production web server hosting confidential static documentation over TLS 1.3 with HTTP Basic Authentication.
- **Workflow**:
  1. Launch `http-server-full -p 0 --cert testdata/tls/server_cert.pem --key testdata/tls/server_key.pem -a "admin:s3cr3t" testdata/public`.
  2. Client connects via TLS 1.3 without `Authorization` header → receives 401 Unauthorized with `WWW-Authenticate: Basic realm="Restricted"`.
  3. Client resends with valid `Authorization: Basic YWRtaW46czNjcjN0` → receives 200 OK with static document over encrypted channel.
  4. Client requests byte range `Range: bytes=0-100` → receives 206 Partial Content with `Content-Range: bytes 0-100/...`.
  5. Client closes TLS session; server remains healthy.

### Scenario 3: Microfrontend & API Gateway with Proxy Fallback (`S4-03`)
- **Use Case**: Developer running frontend development server serving local static assets while proxying dynamic REST API calls to a backend service.
- **Workflow**:
  1. Start mock upstream backend server on port $P_{backend}$ serving `/api/v1/users`.
  2. Launch `http-server-full -p 0 --proxy http://127.0.0.1:$P_{backend} testdata/public`.
  3. Client requests `GET /index.html` → served locally from `testdata/public` (200 OK).
  4. Client requests `GET /api/v1/users` → missing locally; forwarder routes request upstream; client receives upstream JSON payload (200 OK).
  5. Client requests `POST /api/v1/users` with JSON body → streamed upstream; client receives upstream 201 Created.
  6. Backend server is stopped; client requests `/api/v1/users` → receives 502 Bad Gateway without frontend server crashing.

### Scenario 4: Embedded Static Engine in Foreign Desktop Host via C ABI (`S4-04`)
- **Use Case**: A C/C++ or Rust desktop application (e.g. Electron/Tauri/Qt) hosting an embedded local documentation viewer using `http_server_mbt_min.dll`.
- **Workflow**:
  1. Foreign application calls `hs_init()`.
  2. Foreign application queries `hs_abi_version(&major, &minor)` and verifies version compatibility.
  3. Foreign application calls `hs_server_create` with JSON config `{"port": 0, "root": "testdata/public", "silent": true}`.
  4. Foreign application starts server via `hs_server_start_async` and retrieves dynamic listening port.
  5. Foreign application sends HTTP requests to local port and displays HTML content in GUI webview.
  6. On application exit, foreign application calls `hs_server_stop_async` and `hs_server_release`.
  7. Process memory and Win32 handle counters confirm 0 leaks.

### Scenario 5: Real-Time Full-Duplex WebSocket Tunneling Gateway (`S4-05`)
- **Use Case**: Real-time collaborative web application where the static server serves frontend JS/HTML and upgrades WebSocket connections to an upstream messaging cluster.
- **Workflow**:
  1. Start mock upstream WebSocket echo server on port $P_{ws}$.
  2. Launch `http-server-full -p 0 --proxy http://127.0.0.1:$P_{ws} --websocket testdata/public`.
  3. Client fetches `/index.html` via HTTP GET → receives static frontend.
  4. Client initiates WebSocket connection with `Upgrade: websocket` → receives 101 Switching Protocols.
  5. Client sends binary/text WebSocket ping frames → received and echoed by upstream server through full-duplex tunnel.
  6. Client sends WebSocket close frame → connection terminates gracefully, socket resources freed immediately.

---

## 8. Test Suite Directory Layout & Implementation Architecture

The repository test structure is organized as follows:

```
http-server-mbt/
├── core/
│   ├── cache_test.mbt
│   ├── config_test.mbt
│   ├── core_test.mbt
│   ├── mime_test.mbt
│   ├── proxy_config_test.mbt        <-- [NEW] Tier 1 & 2 Reverse Proxy Model tests
│   ├── range_test.mbt
│   ├── routing_test.mbt
│   └── security_test.mbt
├── server/
│   ├── c_suite_*.mbt                <-- Existing 42 migration test suites (C001-C042)
│   ├── handle_leak_assert_test.mbt  <-- Win32 GetProcessHandleCount assertions
│   ├── proxy_state_machine_test.mbt <-- [NEW] Tier 1 & 2 Proxy State Machine tests
│   ├── server_challenger_*.mbt      <-- Adversarial Challenger suites
│   ├── server_e2e_client_test.mbt   <-- Wire-level TCP client tests
│   ├── server_fault_injection_test.mbt <-- Short-write & slow-reader tests
│   ├── server_test.mbt              <-- TransmitFile & server tests
│   └── server_transport_test.mbt    <-- [NEW] Decoupled Transport & Acceptor tests
├── tls/
│   ├── loopback_test.mbt            <-- MbedTLS handshake & loopback tests
│   └── ...
├── full/                            <-- [NEW] Full integration package
│   ├── full.mbt                     <-- TLS Acceptor injection into server
│   ├── full_test.mbt                <-- [NEW] Injected HTTPS integration tests
│   └── moon.pkg
├── cmd/
│   ├── common/                      <-- [NEW] Extracted shared CLI module
│   │   ├── cli_common.mbt
│   │   ├── cli_common_test.mbt      <-- [NEW] Tier 1 & 2 Shared CLI parser tests
│   │   └── moon.pkg
│   ├── http-server-mbt-thin/             <-- [NEW] Minimal static CLI package
│   │   ├── main.mbt
│   │   ├── min_cli_test.mbt         <-- [NEW] Thin CLI positive static tests
│   │   ├── preflight_reject_test.mbt<-- [NEW] Thin CLI preflight rejection tests
│   │   └── moon.pkg
│   ├── http-server-full/            <-- [NEW] Full CLI package
│   │   ├── main.mbt
│   │   ├── full_cli_test.mbt        <-- [NEW] Full CLI feature parity tests
│   │   └── moon.pkg
│   └── http-server-mbt/             <-- Default CLI package (backward compatibility)
│       └── ...
├── c_abi/                           <-- [NEW] C ABI package
│   ├── c_abi.mbt                    <-- Exported MoonBit bridge functions
│   ├── c_abi_test.mbt               <-- [NEW] MoonBit-side C ABI tests
│   └── moon.pkg
├── include/
│   └── http_server_mbt.h            <-- Exported C header file
├── tests/                           <-- [NEW] Integration & Native C test suite
│   ├── cabi/
│   │   ├── test_cabi_dynamic.c      <-- Native C test program (dynamic link)
│   │   ├── test_cabi_static.c       <-- Native C test program (static link)
│   │   └── Makefile / build.ps1
│   └── e2e/
│       ├── test_scenarios_test.mbt  <-- Tier 4 Real-World scenarios in MoonBit
│       └── moon.pkg
└── scripts/
    ├── build_cabi.mbtx              <-- Automated C ABI build pipeline script
    ├── run_e2e.mbtx                 <-- Multi-process E2E test runner script
    ├── verify_symbols.mbtx          <-- Symbol hygiene auditor script
    └── verify_zero_crypto.mbtx      <-- Thin build zero-crypto auditor script
```

---

## 9. Test Execution Guide & Verification Commands

### 9.1 Fast Unit & Package Regression (Tiers 1 & 2)
To run all unit, protocol, and package-level tests across the entire repository:
```powershell
moon test --target native
```
*Expected Result*: `Total tests: 183+ (all passed, 0 failed)`.

### 9.2 Type Check & 0-Warning Verification
To verify compile cleanliness and ensure 0 warnings across all targets:
```powershell
moon check --target native
```
*Expected Result*: 0 errors, 0 warnings.

### 9.3 Thin CLI Preflight Rejection Verification
To independently verify that `http-server-mbt-thin` rejects unsupported flags with exit code 1:
```powershell
moon build --target native
# Run rejection tests
$p1 = Start-Process -FilePath "_build/native/debug/bin/http-server-mbt-thin.exe" -ArgumentList "--cert foo.crt" -Wait -PassThru -NoNewWindow
if ($p1.ExitCode -ne 1) { Write-Error "Preflight rejection failed for --cert" }

$p2 = Start-Process -FilePath "_build/native/debug/bin/http-server-mbt-thin.exe" -ArgumentList "--proxy http://127.0.0.1:3000" -Wait -PassThru -NoNewWindow
if ($p2.ExitCode -ne 1) { Write-Error "Preflight rejection failed for --proxy" }
```

### 9.4 C ABI Build Pipeline & Zero-Crypto Verification
To build C ABI libraries and audit export symbols:
```powershell
# 1. Build C ABI artifacts
moon run scripts/build_cabi.mbtx -- --variant thin --kind dynamic
moon run scripts/build_cabi.mbtx -- --variant thin --kind static
moon run scripts/build_cabi.mbtx -- --variant full --kind dynamic
moon run scripts/build_cabi.mbtx -- --variant full --kind static

# 2. Audit exported symbols (ensure no main, strictly hs_* APIs)
moon run scripts/verify_symbols.mbtx

# 3. Audit zero crypto symbols in thin build
moon run scripts/verify_zero_crypto.mbtx
```

### 9.5 Standalone C Harness Execution
To compile and execute the standalone native C verification programs:
```powershell
# Compile dynamic linking test with MSVC cl.exe
cl /nologo /Iinclude /MD tests/cabi/test_cabi_dynamic.c /Fetarget/cabi/test_cabi_dynamic.exe /link target/cabi/http_server_mbt_min.lib
.\target\cabi\test_cabi_dynamic.exe
```
*Expected Result*: Prints `ABI Version: 1.0`, executes HTTP GET request, outputs `All C ABI tests PASSED!`, exits 0.

### 9.6 Full E2E Scenario Runner (Tier 3 & Tier 4)
To execute all pairwise interactions and real-world application scenarios:
```powershell
moon run scripts/run_e2e.mbtx
```
*Expected Result*: All 10 Tier 3 combinations and 5 Tier 4 scenarios pass with green status.

---

## 10. Pass / Fail Criteria and Quality Gates

| Gate Stage | Evaluated Properties | Threshold / Required Criterion | Gatekeeper Role |
|---|---|---|---|
| **Compilation Gate** | `moon check --target native` | 0 errors, 0 warnings | Specialist / Developer |
| **Interface Gate** | `moon info --target native`, `moon fmt` | `.mbti` up to date, clean formatting diff | Specialist / Developer |
| **Regression Gate** | Existing 183 tests across repo | 100% pass (0 failures, 0 panics) | Test Writer / QA |
| **Feature Coverage (Tier 1)** | All 16 features (>=5 tests per feature) | 100% pass (80/80 tests pass) | Test Writer / QA |
| **Boundary & Corner (Tier 2)** | All 16 features (>=5 tests per feature) | 100% pass (80/80 tests pass) | Challenger / QA |
| **Integration (Tier 3 & 4)** | Pairwise interactions & Scenarios | 100% pass (15/15 scenarios pass) | Test Writer / Reviewer |
| **Resource Safety Gate** | Win32 `GetProcessHandleCount` | Delta == 0 across repeated runs (0 handle leaks) | Challenger / Forensic Auditor |
| **Symbol Hygiene Gate** | DLL/LIB symbol tables | 0 `main` symbol, 0 MbedTLS in thin, strictly `hs_*` | Forensic Auditor |
| **License Compliance Gate** | Workspace dependencies & sources | 100% MIT / Apache-2.0 / BSD-3-Clause (0 GPL/AGPL) | Forensic Auditor |
| **Git Workflow Gate** | Local git commit | `git status` clean, local commit created, 0 pushes | Orchestrator / Auditor |

---

*Document finalized and authoritative for the `http-server-mbt` E2E testing track.*
