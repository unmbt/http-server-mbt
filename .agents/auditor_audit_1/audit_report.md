# Forensic Audit Report — Milestone 1~3 C ABI & Min/Full Packaging

- **Auditor**: `auditor_audit_1` (Independent SDD & Forensic Auditor)
- **Target**: `http-server-mbt` (Milestone 1~3: Core Decoupling, Min/Full CLI Packaging, C ABI Dynamic & Static Export Pipeline)
- **Working Directory**: `E:/project/moonbit/unmbt/http-server-mbt/.agents/auditor_audit_1`
- **Execution Date**: 2026-09-19
- **Integrity Mode**: development (with strict anti-cheating, symbol isolation, and license compliance audits per ORIGINAL_REQUEST.md line 538)
- **Overall Forensic Verdict**: **CLEAN (100% PASS — ZERO DEFECTS / ZERO VIOLATIONS)**

---

## 1. Executive Summary

As an independent forensic auditor, an exhaustive verification of the work products from Milestones 1 through 3 was conducted. This includes:
1. **SDD Consistency Audit**: Verified `docs/proposal.md`, `docs/design.md` (D-07, D-08, D-11, AD-01~AD-10), `docs/tasks.md` (T-020, T-027), and `docs/cli-min-full-and-cabi-handover.md`. Confirmed that task states, delivery evidence, and interface specifications are strictly truthful.
2. **Full Verification Gate Execution**:
   - `moon run scripts/build_cabi.mbtx`: Generated all 6 C ABI target artifacts (Windows `.dll`, `.lib`, and static `.lib`) and compiled/executed 4 standalone C consumer programs with 100% PASS.
   - `moon check --target native --deny-warn`: 0 errors, 0 warnings across all 47 tasks.
   - `moon test --target native`: All 230 tests passed (0 failures, 0 regressions).
3. **Forensic Integrity & Anti-Cheating**:
   - Analyzed C ABI bridges and MoonBit wrappers for genuine implementations (no facade returns, no hardcoded mocks).
   - Audited symbol isolation using MSVC `dumpbin`: confirmed dynamic libraries export strictly the 5 specified `hs_*` symbols with zero runtime or `main` symbol leaks; confirmed `hs_min_static.lib` contains zero `mbedtls` or `psa` symbols.
   - Verified open-source license compliance (MIT, Apache-2.0).
   - Audited Git repository status: confirmed strictly NO `git push` has been executed (branch is ahead of remote by 2 local commits).

---

## 2. SDD Consistency Audit

### 2.1 Specification Alignment (`proposal.md` & `design.md`)
- **`docs/proposal.md`**:
  - Section 2 defines the delivery matrix including Windows `.dll`, MSVC `.lib` static libraries, and Min/Full CLI packaging.
  - Section 3 maps R-N06 (C ABI dynamic library), R-N08 (C ABI static library), R-N02 (standalone CLI min/full), and R-N14 (library-managed lifecycle).
- **`docs/design.md`**:
  - **D-07 (MoonBit API & C ABI v1)**: Specifies the `hs_*` C calling convention, versioning (`hs_abi_version`), opaque handles, declarative JSON configuration, error copying (`hs_error_copy`), and library-managed lifecycle (`hs_server_start`, `hs_server_stop`, `hs_server_destroy`).
  - **D-08 (Build, TLS & Distribution)**: Defines the dual-tier product architecture:
    - Min: zero crypto dependencies, static HTTP/Range/caching/SPA/directory listing.
    - Full: MbedTLS 4.2.0 (Apache-2.0) integrated for TLS and proxy forwarding.
  - **D-11 (Static Libraries & Native Export Preconditions)**:
    - Specifies the `.mbtx` driver pipeline (`scripts/build_cabi.mbtx`).
    - Details the object file symbol stripping mechanism using `llvm-objcopy` (`--remove-section=.drectve`) and MSVC `.def` module definition files to ensure export isolation.
    - Defines the distinction between import library `hs_*.lib` and static library `hs_*_static.lib`.
    - Mandates standalone C consumer smoke tests in `testdata/c_consumer/`.
  - **AD-01 ~ AD-10**: All Architectural Difference decisions remain intact and respected.

### 2.2 Task Registry & Windows Delivery Evidence (`tasks.md`)
- **T-020 (C ABI v1 托管异步动态库)**:
  - **Status**: `- [ ] 进行中（Windows 分项交付，2026-09-18）`.
  - **Evidence Recorded**: Windows x86_64, MSVC 14.42, Moon 0.1.20260904; `c_abi/include/http_server.h` 5 C APIs; `target/cabi/hs_min.dll` and `target/cabi/hs_full.dll`; `.def` export whitelisting; C consumers `test_dynamic_min.c` and `test_dynamic_full.c` 100% PASS.
  - **Audit Note**: The task remains unchecked `- [ ]` because Linux/macOS variants are awaiting CI integration. This strictly conforms to `AGENTS.md` guidelines that tasks spanning multiple platforms must not be falsely marked as completed (`- [x]`) before all platforms are satisfied.
- **T-027 (静态库打包与 C/Rust 消费)**:
  - **Status**: `- [ ] 进行中（Windows 分项交付，2026-09-18）`.
  - **Evidence Recorded**: Generation of `target/cabi/hs_min_static.lib` and `target/cabi/hs_full_static.lib`; dumpbin verification of zero MbedTLS symbols in min static archive; standalone C static consumers `test_static_min.c` and `test_static_full.c` 100% PASS.
  - **Audit Note**: Accurately marked as in-progress with Windows delivery evidence.

### 2.3 Handover Documentation (`cli-min-full-and-cabi-handover.md`)
- Verified that `docs/cli-min-full-and-cabi-handover.md` faithfully documented the state after Milestone 1 & 2 (core decoupling, min/full CLI) and established the blueprint executed in Milestone 3.

---

## 3. Full Verification Gate Execution Evidence

### 3.1 C ABI Build Pipeline (`moon run scripts/build_cabi.mbtx`)
The build driver was executed directly from the workspace.

**Command**:
```powershell
moon run scripts/build_cabi.mbtx
```

**Raw Output**:
```text
==================================================================
http-server-mbt C ABI Build Pipeline (D-07, D-11, T-020, T-027)
==================================================================
1. Discovering toolchain...
  MSVC Linker: E:/Program Files/msvc/VC/Tools/MSVC/14.42.34433/bin/HostX64/x64/link.exe
  MSVC Archiver: E:/Program Files/msvc/VC/Tools/MSVC/14.42.34433/bin/HostX64/x64/lib.exe
  LLVM Objcopy: E:/Program Files/llvm-mingw-20220906-msvcrt-x86_64/bin/llvm-objcopy.exe
2. Building MoonBit packages...
3. Preparing target/cabi/ directories...
4. Building min variant (zero crypto, static HTTP server)...
Staging 35 objects into target/cabi/_staging_min...
Linking hs_min.dll...
Creating static archive hs_min_static.lib...
5. Building full variant (integrated TLS & proxy)...
Staging 144 objects into target/cabi/_staging_full...
Linking hs_full.dll...
Creating static archive hs_full_static.lib...
6. Verifying symbols and export isolation...
Verifying exports for target/cabi/hs_min.dll...
  -> Verified: strictly 5 hs_* exports, zero symbol leaks.
Verifying exports for target/cabi/hs_full.dll...
  -> Verified: strictly 5 hs_* exports, zero symbol leaks.
Verifying absence of MbedTLS symbols in target/cabi/hs_min_static.lib...
  -> Verified: zero mbedtls/psa symbols in min static archive.
7. Compiling and running standalone C consumer tests...
Compiling consumer test test_dynamic_min...
Running consumer test test_dynamic_min...
  -> PASS: test_dynamic_min
Compiling consumer test test_static_min...
Running consumer test test_static_min...
  -> PASS: test_static_min
Compiling consumer test test_dynamic_full...
Running consumer test test_dynamic_full...
  -> PASS: test_dynamic_full
Compiling consumer test test_static_full...
Running consumer test test_static_full...
  -> PASS: test_static_full
==================================================================
C ABI Build and Verification SUCCEEDED!
Artifacts in target/cabi/:
  - target/cabi/include/http_server.h (1151 bytes)
  - target/cabi/hs_min.dll (1344000 bytes)
  - target/cabi/hs_min.lib (2514 bytes)
  - target/cabi/hs_min_static.lib (4460708 bytes)
  - target/cabi/hs_full.dll (2678784 bytes)
  - target/cabi/hs_full.lib (2528 bytes)
  - target/cabi/hs_full_static.lib (6916216 bytes)
==================================================================
```

**Artifact Verification**:
| Artifact Path | Size (Bytes) | Verification Status |
|---|---|---|
| `target/cabi/include/http_server.h` | 1,151 | Present, C ABI header matching D-07 / D-11 |
| `target/cabi/hs_min.dll` | 1,344,000 | Present, PE x64 Dynamic Library |
| `target/cabi/hs_min.lib` | 2,514 | Present, PE x64 Import Library |
| `target/cabi/hs_min_static.lib` | 4,460,708 | Present, COFF Archive (Static Library) |
| `target/cabi/hs_full.dll` | 2,678,784 | Present, PE x64 Dynamic Library |
| `target/cabi/hs_full.lib` | 2,528 | Present, PE x64 Import Library |
| `target/cabi/hs_full_static.lib` | 6,916,216 | Present, COFF Archive (Static Library) |

**Standalone C Consumer Verification**:
| Test Executable | Linkage Mode | Tested Capabilities | Result |
|---|---|---|---|
| `test_dynamic_min.exe` | Dynamic (`hs_min.dll`) | `hs_abi_version`, `hs_error_copy` (buffer & query), preflight checks (NULL, bad JSON, port 99999, unsupported TLS), lifecycle (`start`/`stop`/`destroy`, idempotent stop, safe NULL destroy) | **PASS** |
| `test_static_min.exe` | Static (`hs_min_static.lib`) | `hs_abi_version`, `hs_error_copy`, server start on dynamic port 0, stop, destroy | **PASS** |
| `test_dynamic_full.exe` | Dynamic (`hs_full.dll`) | `hs_abi_version`, `hs_error_copy`, TLS preflight (cert without key), spa+proxy conflict check, server lifecycle | **PASS** |
| `test_static_full.exe` | Static (`hs_full_static.lib`) | `hs_abi_version`, `hs_error_copy`, TLS preflight, spa+proxy conflict, server lifecycle | **PASS** |

### 3.2 MoonBit Static Type & Linter Gate (`moon check --target native`)
**Command**:
```powershell
moon check --target native --deny-warn
```
**Raw Output**:
```text
Finished. moon: ran 47 tasks, now up to date
```
- **Errors**: 0
- **Warnings**: 0

### 3.3 Full Test Suite Execution (`moon test --target native`)
**Command**:
```powershell
moon test --target native
```
**Raw Output Summary**:
```text
core.internal_test.c
server.internal_test.c
http-server-mbt.internal_test.c
min.blackbox_test.c
http-server-min.internal_test.c
core.blackbox_test.c
http-server-full.internal_test.c
full.internal_test.c
http-server-min.whitebox_test.c
tls.internal_test.c
http-server-mbt.internal_test.c
full.blackbox_test.c
http-server-full.whitebox_test.c
http-server-mbt.whitebox_test.c
tls.blackbox_test.c
http-server-mbt.blackbox_test.c
min.internal_test.c
http-server-min.blackbox_test.c
full.internal_test.c
full.blackbox_test.c
http-server-full.blackbox_test.c
server.blackbox_test.c
Total tests: 230, passed: 230, failed: 0.
```
- **Total Tests Executed**: 230
- **Passed**: 230
- **Failed**: 0
- **Regressions**: 0

---

## 4. Forensic Integrity & Anti-Cheating Audit

### 4.1 Authentic Implementation Inspection
- **C ABI Bridge (`c_abi/min/bridge.c` & `c_abi/full/bridge.c`)**:
  - Implements a genuine JSON parser handling strings, numbers, booleans, escape characters, and structural validations.
  - Enforces port range limits `[0, 65535]`.
  - Enforces mutual exclusion rules (e.g., `spa` and `try_files`, or `spa` and `proxy`).
  - Manages Windows thread creation (`CreateThread`), synchronization events (`ready_event`, `stop_event`), and runtime initialization (`ensure_runtime_init`).
  - Correctly copies error descriptions with buffer length boundary checks in `hs_error_copy`.
- **MoonBit Bridge (`c_abi/min/abi.mbt` & `c_abi/full/abi.mbt`)**:
  - `hs_min_run_server` launches the MoonBit async event loop using `@server.with_server_at(config, port, ...)`.
  - `hs_full_run_server` launches `@full_server.with_server_at(config, port, ...)`.
  - Handles server readiness notification via `hs_bridge_notify_ready` and polls stop flag via `hs_bridge_is_stopped`.
  - **Verdict**: Real, operational implementation; zero facade functions, zero fake test mocks.

### 4.2 Symbol Isolation & Absence of Contamination
MSVC `dumpbin.exe` was used to perform independent symbol inspection on the generated binaries:

1. **`target/cabi/hs_min.dll` Export Audit**:
   ```text
       ordinal hint RVA      name
             1    0 000FCD40 hs_abi_version
             2    1 00005BE0 hs_error_copy
             3    2 00005CB0 hs_server_destroy
             4    3 00005D40 hs_server_start
             5    4 00005EF0 hs_server_stop
   ```
   - Verified: Exactly 5 exported functions matching `hs_*` ABI v1.
   - Zero `main` symbol. Zero MoonBit internal runtime symbols (`moonbit_*` or `_M0*`).

2. **`target/cabi/hs_full.dll` Export Audit**:
   ```text
       ordinal hint RVA      name
             1    0 0010A5E0 hs_abi_version
             2    1 00005F20 hs_error_copy
             3    2 00005FF0 hs_server_destroy
             4    3 00006080 hs_server_start
             5    4 00006230 hs_server_stop
   ```
   - Verified: Exactly 5 exported functions. Zero leaks.

3. **`target/cabi/hs_min_static.lib` Archive Symbol Audit**:
   - Tested for `mbedtls` or `psa_` symbols:
     ```powershell
     dumpbin /SYMBOLS target/cabi/hs_min_static.lib | Select-String "mbedtls|psa_"
     ```
     Result: **0 matches**. Complete absence of crypto symbols.
   - Tested for `main` entry point:
     ```powershell
     dumpbin /SYMBOLS target/cabi/hs_min_static.lib | Select-String "\| main$"
     ```
     Result: **0 matches**. No entry point collision hazard.

4. **`target/cabi/hs_full_static.lib` Archive Symbol Audit**:
   - Tested for `main` entry point: **0 matches**.

### 4.3 Open Source License Compliance Audit
- Project root `LICENSE`: MIT License (Copyright 2026 UnMoonBit).
- `moon.mod`: `license = "MIT"`.
- Dependency `moonbitlang/async@0.21.3`: Apache-2.0 License.
- Vendor package `tls/mbedtls-4.2.0`: Dual Apache-2.0 / GPL-2.0-or-later, licensed under Apache-2.0.
- All code, third-party libraries, and test fixtures are licensed under commercial-friendly, permissive licenses (MIT / Apache-2.0). Zero GPL / AGPL contamination found.

### 4.4 Git Operation Safety Audit
- **Working Tree Status**:
  ```text
  On branch feat/tls-and-lib-export
  Your branch is ahead of 'origin/feat/tls-and-lib-export' by 2 commits.
    (use "git push" to publish your local commits)
  ```
- **Unpushed Local Commits**:
  1. `9cabfb9 feat: cli区分功能打包`
  2. `a5c3edf feat: 实现 min 与 full 双版本 C ABI 动静态库导出流水线 (T-020, T-027)`
- **Remote Origin URL**: `https://github.com/unmbt/http-server-mbt.git`
- **Audit Finding**: Both commits are strictly local. Zero `git push` command was executed. Repository safety constraints are 100% satisfied.

---

## 5. Forensic Audit Checklist

| # | Forensic Check Item | Profile Level | Result | Raw Proof |
|---|---|---|---|---|
| 1 | Hardcoded test results / fake mocks | All Modes | **PASS** | No trivial assertions (`assert_true(true)`) or mocked test values |
| 2 | Facade implementations | All Modes | **PASS** | `bridge.c` and `abi.mbt` implement real JSON parser, threading, and server loops |
| 3 | Pre-populated artifact detection | All Modes | **PASS** | Clean build and verification freshly executed during audit |
| 4 | SDD Document & Task status accuracy | SDD Rule | **PASS** | T-020 and T-027 accurately kept as `- [ ] 进行中` with Windows evidence |
| 5 | C ABI Build Pipeline execution | Quality Gate | **PASS** | `build_cabi.mbtx` generated 6 artifacts + 4 C tests passed 100% |
| 6 | Native compiler check (`moon check`) | Quality Gate | **PASS** | 47 tasks, 0 errors, 0 warnings with `--deny-warn` |
| 7 | Full test suite execution (`moon test`) | Quality Gate | **PASS** | 230/230 tests passed (0 failures, 0 regressions) |
| 8 | Symbol Isolation & Export purity | Security Gate | **PASS** | DLL exports strictly 5 `hs_*` APIs; min static archive has 0 crypto symbols |
| 9 | Open-source license compliance | Legal Gate | **PASS** | MIT / Apache-2.0 across all dependencies; 0 GPL contamination |
| 10 | Strictly NO git push | Safety Rule | **PASS** | Branch ahead by 2 local commits; 0 pushes to origin |

---

## 6. Final Verdict

**VERDICT: CLEAN**

The work products from Milestones 1 through 3 in `http-server-mbt` fully comply with SDD methodology, architectural specifications (D-07, D-08, D-11), and forensic anti-cheating standards. All code is authentic, type-safe, warning-free, test-passing, symbol-isolated, and license-compliant.
