# Forensic Audit Report — Milestone 5 (CLI 完整性、生命周期与架构规范)

- **Auditor**: Teamwork Forensic Integrity & Open Source License Auditor (gen2 replacement)
- **Target**: Milestone 5 Implementation (commit `178bb577a0e8e1c1f57e5c70044c54ce8ec412f0`)
- **Working Directory**: `E:\project\moonbit\unmbt\http-server-mbt\.agents\auditor_m5_1_gen2`
- **Integrity Mode**: Benchmark Mode (Maximum Strictness)
- **Final Verdict**: **`CLEAN`** (Full Integrity & License Compliance)

---

## 1. Observation

### 1.1 Source Code Forensic Analysis

1. **CLI Argument Parsing (`cmd/http-server-mbt/cli.mbt`)**:
   - Lines 26–115: Declaratively defines `@argparse.Command("http-server-mbt")` with all required options and flags:
     - Flags: `help` (`-h`), `version` (`-v`), `spa`, negatable `autoIndex` (`-i`, `--no-autoIndex`), negatable `showDir` (`-d`, `--no-showDir`), `cors`, `log-ip` (`-l`), `silent` (`-s`).
     - Options: `port` (`-p`, env `"PORT"`), `base-url`, `base-dir`, `try-files`, `cache` (`-c`, `allow_hyphen_values=true`), `auth` (`-a`).
     - Positional: `root` (0..1 arguments).
   - Lines 159–183: `parse_port` genuinely parses integers, truncates floating-point strings (e.g. `"9090.86"` -> `9090`) per C033 / AD-04, and enforces strict boundary validation:
     ```moonbit
     if n < 1 || n > 65535 {
       None
     } else {
       Some(n)
     }
     ```
   - Lines 187–210: `parse_cache` genuinely parses `"max-age=N"`, integer durations, `-1` (no-cache), and rejects values `< -1` or non-numeric strings.
   - Lines 214–229: `parse_auth` splits `"username:password"`, rejecting empty usernames, missing colons, or embedded null bytes (`\0`).
   - Lines 233–332: `parse_cli` binds parsed matches into `@core.Config`, resolves base URL via `@core.resolve_base_url`, verifies mutual exclusion (`spa && try_files is Some(_)`), and executes `config.validate()`. Zero parameters are hardcoded or bypassed.

2. **Pre-flight Validation & Failure Interception (`cmd/http-server-mbt/main.mbt`)**:
   - Lines 22–37: On parse error, `main.mbt` calls `eprint_err("error: \{err}\n")` and immediately calls C runtime `exit(1)` via `runtime_native_exit(1)`.
   - Lines 41–52: Resolves default root: if `root == "."` and `./public` exists as a directory, updates `root = "public"` per D-01.
   - Lines 55–67: Verifies root directory existence and directory type directly against the filesystem using `@fs`:
     ```moonbit
     let exists = @fs.exists(final_config.root)
     let is_dir = if exists {
       @fs.kind(final_config.root) == Directory
     } else {
       false
     }
     if !is_dir {
       eprint_err(
         "error: root directory '\{final_config.root}' does not exist or is not a directory\n",
       )
       runtime_native_exit(1)
       return
     }
     ```
   - This check runs **before** `@server.with_server_at` is invoked, preventing socket binding or listener startup when root is invalid.

3. **Core Model & Validation (`core/config.mbt`)**:
   - Lines 42–95: `Config` defines `log_ip: Bool` (default `false`) and `silent: Bool` (default `false`).
   - Lines 264–334: `validate_config(config)` validates `root` (non-empty, no null bytes), `base_url`, `port` (0..65535), `idle_timeout_ms >= 0`, `try_files` (path relativity, no dot segments, no consecutive slashes, no Nginx multi-candidate syntax), mutual exclusion between `spa` and `try_files`, mutual exclusion between page fallback (`spa`/`try_files`) and proxy (`proxy`/`proxy_all`/`proxy_options`), `basic_auth`, `cache_seconds >= -1`, and CRLF injection checks on custom headers.
   - Lines 338–340: `Config::validate(self)` exposes instance validation method.

4. **Server Lifecycle & In-Flight Request Draining (`server/server.mbt`)**:
   - Line 8: `Server` includes `active_requests : Ref[Int]`.
   - Lines 73–91: `Server::stop_and_drain` implementation:
     ```moonbit
     pub async fn Server::stop_and_drain(
       self : Server,
       timeout_ms? : Int = 5000,
     ) -> Unit {
       if !self.stopped {
         self.stopped = true
         @async.protect_from_cancel(() => {
           let mut waited = 0
           let step = 10
           while self.active_requests.val > 0 && waited < timeout_ms {
             @async.sleep(step)
             waited += step
           }
         })
         if self.task is Some(t) {
           t.cancel()
         }
       }
     }
     ```
   - Lines 120, 138: In `handle_connection`, `active_requests.val += 1` is incremented after reading the request and decremented `active_requests.val -= 1` after sending the response.
   - Lines 38–58: In `with_server_at`, `defer listener.close()` and `server.stop_and_drain()` ensure all in-flight requests drain cleanly before socket closure and task cancellation.

### 1.2 Open Source License Compliance Scan

1. **Repository License**:
   - `moon.mod`: `license = "MIT"`
   - `LICENSE`: Full standard MIT License text present.
   - `README.md`: Declares MIT License.
2. **External Package Dependencies**:
   - `moon.mod`:
     ```json
     import {
       "moonbitlang/async@0.21.3",
     }
     ```
   - Only 1 dependency imported: `moonbitlang/async@0.21.3`.
   - `.mooncakes/moonbitlang/async/LICENSE`: Full **Apache-2.0** license text (permissive, commercial-friendly).
3. **C Code**:
   - `server/transmit_file_windows.c`: Custom Win32 IOCP/TransmitFile wrapper written natively for this project, licensed under project's MIT.
4. **Copyleft Search**:
   - Ripgrep searches for `GPL`, `AGPL`, `LGPL`, and `copyleft` across the entire codebase returned **0 results**. Zero copyleft licenses or unlicensed proprietary code detected.

### 1.3 Tool Execution & Empirical Verification Results

1. **Compiler Diagnostics Check**:
   - Command: `moon check --target native`
   - Output: `Finished. moon: no work to do` (Exit code: 0, 0 errors, 0 warnings).

2. **Full Test Suite Execution**:
   - Command: `moon test --target native`
   - Result: `Total tests: 116, passed: 116, failed: 0.` (Exit code: 0).
   - Package breakdown:
     - `cmd/http-server-mbt`: 28 passed (16 whitebox unit tests + 12 adversarial boundary tests in `cli_challenger_wbtest.mbt`).
     - `server`: 22 passed (including zero handle leak tests, client cancellation tests, multi-chunk TransmitFile tests, and lifecycle/drain tests).
     - `core` & root engine: 66 passed (all CC-01..CC-28 fixtures, Range, conditional requests, directory listing, BaseURL, SPA fallback).

3. **Release Build**:
   - Command: `moon build cmd/http-server-mbt --target native --release`
   - Result: Produced `_build\native\release\build\cmd\http-server-mbt\http-server-mbt.exe` (Exit code: 0).

4. **Empirical Release CLI Smoke Tests**:
   - `-h`: Exited with code 0, rendered full usage text to stdout.
   - `-v`: Exited with code 0, rendered `"http-server-mbt 0.1.5"` to stdout.
   - `--invalid-option`: Exited with code 1, rendered `"error: unexpected argument '--invalid-option' found"` to stderr.
   - `-p 99999`: Exited with code 1, rendered `"error: invalid port '99999': port must be an integer between 1 and 65535"` to stderr.
   - `-p 0`: Exited with code 1, rendered `"error: invalid port '0': port must be an integer between 1 and 65535"` to stderr.
   - `.\non_existent_folder_xyz_123`: Exited with code 1, rendered `"error: root directory '.\non_existent_folder_xyz_123' does not exist or is not a directory"` to stderr.
   - `--spa --try-files index.html`: Exited with code 1, rendered `"error: cannot specify both --spa and --try-files (mutual exclusion violation)"` to stderr.
   - Live HTTP request on port 18090: Started process, sent HTTP GET `/hello.txt`, received HTTP 200 OK with `"hello moonbit\n"`, followed by clean process shutdown without error.

---

## 2. Logic Chain

1. **Strict Benchmark Mode Adherence**:
   - The user specified `Integrity mode: benchmark` in `ORIGINAL_REQUEST.md`. Under Benchmark mode, using pre-built libraries for core functionality, hardcoded test results, facade implementations, or code copying from external projects is strictly prohibited.
   - Observation 1.1 and 1.2 demonstrate that all CLI parsing, configuration validation, lifecycle draining, and static file serving were implemented from scratch in MoonBit, with zero third-party framework delegation for core functionality.
2. **Authenticity of CLI & Validation Logic**:
   - In `cmd/http-server-mbt/cli.mbt`, argument parsing is dynamic and comprehensive, utilizing `@argparse` with complete option coverage.
   - Float truncation and integer bounds for ports are actively calculated in `parse_port` and validated before execution.
   - Pre-flight validation checks both the port bounds and root directory existence via `@fs` before any listener is opened. When validation fails, the process exits with code 1 via `exit(1)` and writes errors to stderr, preventing invalid servers from binding ports or leaking unhandled errors.
3. **Authenticity of Graceful Shutdown & In-Flight Request Draining**:
   - In `server/server.mbt`, `active_requests` is genuinely maintained across request lifecycles.
   - `Server::stop_and_drain` sets `self.stopped = true` (preventing new keep-alive requests from starting), and executes a polling drain loop protected from external task cancellation by `@async.protect_from_cancel`.
   - The adversarial lifecycle suite (`server/server_challenger_m5_lifecycle_test.mbt`) verified that 512KB transfers and concurrent requests drain cleanly to completion during shutdown.
4. **Absence of Test Mocking or Result Fabrication**:
   - All 116 tests are compiled directly from MoonBit test files and executed via native test binaries against the actual socket, engine, and filesystem.
   - No pre-populated result files, mock caches, or hardcoded pass/fail assertions exist in the workspace.
5. **License Compliance**:
   - The repository is licensed under MIT.
   - The single dependency (`moonbitlang/async@0.21.3`) is licensed under Apache-2.0.
   - Native C code is original project code under MIT.
   - No copyleft licenses (GPL, AGPL, LGPL) or proprietary unlicensed materials exist.

---

## 3. Caveats

- **No caveats.** All 5 audit areas (CLI parsing authenticity, pre-flight validation authenticity, lifecycle draining authenticity, open-source license compliance, compiler/test suite execution) were directly and empirically verified.

---

## 4. Conclusion

### Forensic Audit Summary

| Check Area | Standard / Requirement | Observed Result | Status |
|---|---|---|---|
| **Argument Parsing** | Dynamic parsing of all CLI options, no hardcoded parameters | Full `@argparse` implementation with type conversions & aliases | **PASS** |
| **Port Handling** | Valid range 1..65535, float truncation support | Handled per C033 / AD-04, invalid ports rejected | **PASS** |
| **Pre-flight Validation** | Port bounds, root existence via `@fs`, mutual exclusions | Checked on disk prior to listener creation; exit code 1 to stderr | **PASS** |
| **Lifecycle & Draining** | In-flight tracking, stop_and_drain under protect_from_cancel | `active_requests` tracked, drained cleanly before task cancel | **PASS** |
| **Test Authenticity** | Real assertions, zero facade/mocking | 116 empirical tests pass natively without mocks or hardcoding | **PASS** |
| **License Compliance** | Permissive only (MIT, Apache-2.0, BSD-3-Clause), 0 copyleft | MIT project + Apache-2.0 dependency; 0 GPL/AGPL/LGPL | **PASS** |
| **Compiler Status** | `moon check --target native` | 0 errors, 0 warnings | **PASS** |
| **Test Suite Status** | `moon test --target native` | 116 passed, 0 failed (100% pass) | **PASS** |

### Final Audit Verdict

# **`CLEAN`**

The Milestone 5 work product (`178bb57`) fully satisfies all integrity, architectural, behavioral, and licensing requirements without any integrity violations.

---

## 5. Verification Method

To independently re-verify the auditor's findings:

```powershell
# 1. Verify 0 compiler errors and 0 compiler warnings
moon check --target native

# 2. Run the complete native test suite (116 tests)
moon test --target native

# 3. Build release executable
moon build cmd/http-server-mbt --target native --release

# 4. Empirically verify CLI exit codes and pre-flight validation
$exe = ".\_build\native\release\build\cmd\http-server-mbt\http-server-mbt.exe"
& $exe -h
& $exe -v
& $exe --invalid-flag 2>&1
& $exe -p 99999 2>&1
& $exe -p 0 2>&1
& $exe .\non_existent_folder_xyz 2>&1
& $exe --spa --try-files index.html 2>&1

# 5. Search for copyleft licenses
rg -i "GPL|AGPL|LGPL|copyleft" --glob "!_build/**"
```
