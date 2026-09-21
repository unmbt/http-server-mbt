# E2E Test Suite Design Report & Implementation Plan

**Author**: E2E Test Writer (`test_writer_e2e_1`)  
**Target Project**: `http-server-mbt`  
**Working Directory**: `.agents/test_writer_e2e_1/`  
**Date**: 2026-09-18  

---

## 1. Executive Summary

This report establishes the implementation blueprint for the end-to-end (E2E) testing track supporting the `thin` & `full` layered packaging, TLS decoupling, C ABI export pipeline, and reverse proxy architecture readiness project.

The architecture decouples the HTTP/1.1 static server from MbedTLS C code, provides two distinct CLI distributions (`thin` and `full`), exports clean C ABI libraries (`.dll` and `.lib` without symbol pollution), and establishes reverse proxy configuration and state machines.

To provide impenetrable quality gates, the test track spans **4 tiers**:
1. **Tier 1 (Feature Coverage)**: 80 test cases (>=5 tests across all 16 features).
2. **Tier 2 (Boundary & Corner Cases)**: 80 test cases (>=5 tests across all 16 features).
3. **Tier 3 (Cross-Feature Combinations)**: 10 pairwise and multi-feature interaction test suites.
4. **Tier 4 (Real-World Application Scenarios)**: 5 end-to-end production scenarios.

---

## 2. Test Suite Architecture & Runners

### 2.1 Dual-Runner Strategy
To balance developer test velocity with true end-to-end blackbox fidelity, the test suite utilizes two complementary runner mechanisms:

1. **MoonBit Native Test Framework (`moon test --target native`)**:
   - Executes all in-memory, whitebox, and package-level blackbox tests.
   - Covers unit logic, protocol parsing, state machine transitions, and local loopback integration.
   - Run frequently during development cycles; targets 100% pass across all workspace packages.

2. **`.mbtx` Process-Level Orchestration Runner (`scripts/run_e2e.mbtx`)**:
   - Manages external multi-process lifecycles: starts server binaries (`http-server-mbt-thin.exe`, `http-server-full.exe`) as child processes.
   - Dynamically parses stdout banners for bound ephemeral ports.
   - Dispatches socket/HTTP client requests against running binaries.
   - Tests preflight exit codes (e.g. exit code 1 on `--cert` in thin CLI).
   - Audits symbol tables with Windows `dumpbin` and verifies zero crypto symbols.
   - Executes native C test programs (`test_cabi_dynamic.exe`, `test_cabi_static.exe`).

### 2.2 Directory Layout & File Allocation

```
http-server-mbt/
├── TEST_INFRA.md                          # [Authoritative Root Specification]
├── core/
│   ├── proxy_config_test.mbt              # Tier 1/2: F13 (Reverse Proxy Config Model)
│   └── ...                                # Existing core tests (F03 regression baseline)
├── server/
│   ├── server_transport_test.mbt          # Tier 1/2: F01 (Transport & PlainAcceptor)
│   ├── proxy_state_machine_test.mbt       # Tier 1/2: F14 (Proxy State Machine & Forwarder)
│   └── ...                                # Existing C-suite migration tests (C001-C042)
├── full/
│   ├── full_test.mbt                      # Tier 1/2: F02 (Injected TlsAcceptor HTTPS)
│   └── ...
├── cmd/
│   ├── common/
│   │   └── cli_common_test.mbt            # Tier 1/2: F04 (Shared CLI Parser Helpers)
│   ├── http-server-mbt-thin/
│   │   ├── min_cli_test.mbt               # Tier 1/2: F05 (Min CLI Static Server)
│   │   └── preflight_reject_test.mbt      # Tier 1/2: F06 (Min CLI Exit 1 Preflight)
│   └── http-server-full/
│       └── full_cli_test.mbt              # Tier 1/2: F07 (Full CLI Feature Parity)
├── c_abi/
│   └── c_abi_test.mbt                     # Tier 1/2: F08 (C ABI MoonBit Bridge)
├── tests/
│   ├── cabi/
│   │   ├── test_cabi_dynamic.c            # Tier 1/2: F12 (C Harness Dynamic Link)
│   │   └── test_cabi_static.c             # Tier 1/2: F12 (C Harness Static Link)
│   └── e2e/
│       └── test_scenarios_test.mbt        # Tier 4: Real-World Application Scenarios
└── scripts/
    ├── build_cabi.mbtx                    # Tier 1/2: F09 (C ABI Build Pipeline)
    ├── verify_symbols.mbtx                # Tier 1/2: F10 (Clean Symbol Isolation)
    ├── verify_zero_crypto.mbtx            # Tier 1/2: F11 (Min Zero Crypto Audit)
    └── run_e2e.mbtx                       # Tier 3 & Tier 4 E2E Orchestrator
```

---

## 3. Phased Implementation Sequence

The implementation follows progressive testability: tests are created and verified in tandem with the milestone dependency tree.

### Milestone 1: Server & Core Decoupling from TLS
- **Deliverables**:
  - `server/server_transport_test.mbt` (Tests `T1-F01-01` ~ `T1-F01-05`, `T2-F01-01` ~ `T2-F01-05`)
  - `full/full_test.mbt` (Tests `T1-F02-01` ~ `T1-F02-05`, `T2-F02-01` ~ `T2-F02-05`)
  - Regression verification suite (Tests `T1-F03-01` ~ `T1-F03-05`, `T2-F03-01` ~ `T2-F03-05`)
- **Verification**: `moon test --target native` confirms 183 existing tests pass + new decoupling tests pass.

### Milestone 2: Min & Full CLI Packaging
- **Deliverables**:
  - `cmd/common/cli_common_test.mbt` (Tests `T1-F04-01` ~ `T1-F04-05`, `T2-F04-01` ~ `T2-F04-05`)
  - `cmd/http-server-mbt-thin/min_cli_test.mbt` (Tests `T1-F05-01` ~ `T1-F05-05`, `T2-F05-01` ~ `T2-F05-05`)
  - `cmd/http-server-mbt-thin/preflight_reject_test.mbt` (Tests `T1-F06-01` ~ `T1-F06-05`, `T2-F06-01` ~ `T2-F06-05`)
  - `cmd/http-server-full/full_cli_test.mbt` (Tests `T1-F07-01` ~ `T1-F07-05`, `T2-F07-01` ~ `T2-F07-05`)
- **Verification**: Command-line execution of binaries; exit code 1 assertions for rejected flags.

### Milestone 3: C ABI Dynamic & Static Library Export Pipeline
- **Deliverables**:
  - `c_abi/c_abi_test.mbt` (Tests `T1-F08-01` ~ `T1-F08-05`, `T2-F08-01` ~ `T2-F08-05`)
  - `scripts/build_cabi.mbtx` (Tests `T1-F09-01` ~ `T1-F09-05`, `T2-F09-01` ~ `T2-F09-05`)
  - `scripts/verify_symbols.mbtx` (Tests `T1-F10-01` ~ `T1-F10-05`, `T2-F10-01` ~ `T2-F10-05`)
  - `scripts/verify_zero_crypto.mbtx` (Tests `T1-F11-01` ~ `T1-F11-05`, `T2-F11-01` ~ `T2-F11-05`)
  - `tests/cabi/test_cabi_dynamic.c` & `test_cabi_static.c` (Tests `T1-F12-01` ~ `T1-F12-05`, `T2-F12-01` ~ `T2-F12-05`)
- **Verification**: MSVC `cl.exe` / `link.exe` invocation; `dumpbin` symbol parsing.

### Milestone 4: Reverse Proxy Architecture & Interface Readiness
- **Deliverables**:
  - `core/proxy_config_test.mbt` (Tests `T1-F13-01` ~ `T1-F13-05`, `T2-F13-01` ~ `T2-F13-05`)
  - `server/proxy_state_machine_test.mbt` (Tests `T1-F14-01` ~ `T1-F14-05`, `T2-F14-01` ~ `T2-F14-05`)
  - `scripts/verify_docs_links.mbtx` (Tests `T1-F15-01` ~ `T1-F15-05`, `T2-F15-01` ~ `T2-F15-05`)
- **Verification**: Proxy config validation, routing precedence checks, state machine transition assertions.

### Milestone 5: E2E Integration & Gate Verification
- **Deliverables**:
  - `scripts/run_e2e.mbtx` (Tier 3 Pairwise Combinations `C3-01` ~ `C3-10` and Tier 4 Scenarios `S4-01` ~ `S4-05`)
  - Challenger stress suites and Forensic Auditor verification reports (Tests `T1-F16-01` ~ `T1-F16-05`, `T2-F16-01` ~ `T2-F16-05`)
- **Verification**: All gates pass; Win32 `GetProcessHandleCount` delta == 0; 0 compiler warnings; local git commit.

---

## 4. Fixture Strategy & Asset Invariants

The existing fixture directory at `testdata/` will be preserved and leveraged:
1. `testdata/public/`: Static files (`index.html`, `hello.txt`, `bundle.js`, `.br`/`.gz` pairs) used for static file serving, MIME detection, and caching tests.
2. `testdata/tls/`: Self-signed certificates (`server_cert.pem`, `server_key.pem`, `server_key_enc.pem`) used for TLS 1.3 handshake and password-protected key tests.
3. `testdata/fixtures/proxy/`: Synthetic upstream responses and proxy rewrite configs (`proxy-rules.json`) used for proxy pattern matching.

Temporary test files created during test execution (e.g. temporary socket ports, dynamic config JSON files) MUST be placed in memory or in isolated temporary directories and deleted upon test completion.

---

## 5. Defect Escalation Protocol

As QA / Test Writer, test files MUST NOT attempt to patch implementation defects. If an implementation defect is discovered during test execution:
1. Document the exact reproducing command and observable failure.
2. Cross-reference the relevant requirement ID (`ORIGINAL_REQUEST.md`) and design section (`docs/design.md`).
3. Escalate the bug to the implementing agent (or parent orchestrator) via `send_message`.
4. Ensure the test case remains an objective assertion of the specification rather than weakening the test to match broken behavior.

---

## 6. Traceability Matrix Summary

| Requirement | Description | Associated Features | Primary Test Tier | Primary Test Files |
|---|---|---|---|---|
| **R1** | Core decoupling & TLS injection | `F01`, `F02`, `F03` | Tier 1, 2, 3 | `server_transport_test.mbt`, `full_test.mbt` |
| **R2** | Min & Full CLI packaging & preflight | `F04`, `F05`, `F06`, `F07` | Tier 1, 2, 3, 4 | `min_cli_test.mbt`, `preflight_reject_test.mbt`, `full_cli_test.mbt` |
| **R3** | C ABI export pipeline & zero crypto | `F08`, `F09`, `F10`, `F11`, `F12` | Tier 1, 2, 3, 4 | `c_abi_test.mbt`, `build_cabi.mbtx`, `test_cabi_*.c` |
| **R4** | Reverse proxy architecture & interface | `F13`, `F14`, `F15` | Tier 1, 2, 3, 4 | `proxy_config_test.mbt`, `proxy_state_machine_test.mbt` |
| **Quality Gates** | E2E verification & multi-role audit | `F16` | All Tiers | `run_e2e.mbtx`, Challenger/Auditor suites |
