# Forensic Audit Report — Milestone 6

**Work Product**: `E:\project\moonbit\unmbt\http-server-mbt`  
**Profile**: General Project (Benchmark Mode)  
**Auditor**: `auditor_m6_1`  
**Working Directory**: `E:\project\moonbit\unmbt\http-server-mbt\.agents\auditor_m6_1`  
**Parent**: `orchestrator_m6_gen2` (conv ID: `dcf6fc8a-69f5-4537-8275-a1f2ab70f9af`)  
**Verdict**: **INTEGRITY VIOLATION**

---

## 1. Observation

### 1.1 Objective 1 — Compiler Verification (`moon check --target native`)
Command executed:
```powershell
moon check --target native
```
Output:
```
Finished. moon: no work to do
```
Exit code: `0`.
0 compiler errors, 0 compiler warnings.

### 1.2 Objective 2 — Open Source License Compliance
- Project root license (`LICENSE`): **MIT License** (Copyright 2026 UnMoonBit).
- Module configuration (`moon.mod`):
  ```
  name = "unmbt/http-server-mbt"
  version = "0.1.5"
  import {
    "moonbitlang/async@0.21.3",
  }
  readme = "README.md"
  license = "MIT"
  ```
- Dependency license (`.mooncakes/moonbitlang/async/LICENSE`): **Apache License Version 2.0**.
- Reference codebase (`http-server/LICENSE`): **MIT License**.
- Forensic repository search for copyleft / restricted licenses:
  - `GPL`: 0 matches in code or dependencies (only mentioned in `ORIGINAL_REQUEST.md` requirement text).
  - `AGPL`: 0 matches in code or dependencies.
  - `LGPL`: 0 matches.
  - `General Public License`: 0 matches.
- All test fixtures and sample assets under `testdata/` are permissively licensed.

### 1.3 Objective 3 — Anti-Cheating & Implementation Authenticity (Benchmark Mode)
- **Facade Detection**: Inspected all implementation files (`core/*.mbt`, `server/server.mbt`, `server/transmit_file.mbt`, `cmd/http-server-mbt/*.mbt`, `engine.mbt`). All modules implement genuine parsing algorithms, state transitions, security boundary checks, and Win32 FFI bridges. No stub methods returning constants, no unimplemented dummy functions, and no delegating proxies to external tools.
- **Hardcoded Test Results**: No hardcoded test responses or bypasses found.
- **Pre-populated Artifacts**: Checked for pre-existing `*.log`, `*result*`, and `*output*` files. None existed before the audit run.
- **Dependency Scope**: Only the language standard library and `moonbitlang/async` are utilized. No third-party HTTP engine or pre-built server framework is used.

### 1.4 Objective 4 & Test Suite Execution — Full Test Run (`moon test --target native`)
Command executed:
```powershell
moon test --target native --no-parallelize
```
Output:
```
[unmbt/http-server-mbt] test server/server_fault_injection_test.mbt:369 ("fault_injection: Multi-round empirical zero handle leak verification (Pass 1 vs Pass 2)") failed: server/server_fault_injection_test.mbt:438:3-438:29@unmbt/http-server-mbt FAILED: `false` is not true
[unmbt/http-server-mbt] test server/server_e2e_client_test.mbt:333 ("e2e client: Zero handle leaks across diverse socket lifecycle operations") failed: server/server_e2e_client_test.mbt:374:5-374:55@unmbt/http-server-mbt FAILED: `false` is not true
[unmbt/http-server-mbt] test server/server_challenger_test.mbt:158 ("challenger1: Abrupt client disconnection during large file transfer") failed: server/server_challenger_test.mbt:218:3-218:53@unmbt/http-server-mbt FAILED: `false` is not true
[unmbt/http-server-mbt] test server/server_challenger_test.mbt:222 ("challenger1: 60 consecutive requests stress test with handle leak verification") failed: server/server_challenger_test.mbt:261:3-261:52@unmbt/http-server-mbt FAILED: `false` is not true
Total tests: 168, passed: 164, failed: 4.
```
Exit code: `1`.

When executed with standard parallel execution:
```
Total tests: 167, passed: 161, failed: 6.
```
Additional failures included:
- `server/server_test.mbt:234 ("server zero handle leaks across repeated requests")` line 264: `assert_true(after_handles <= before_handles + 10U)` FAILED.
- `server/server_challenger_m6_edge_test.mbt:94 ("challenger_m6_edge: in-flight request cancellation and drain under streaming load")` line 171: `assert_eq(finished_count.val, num_readers)` FAILED with `0 != 3`.

### 1.5 Deadlock / Infinite Hang During Test Execution
During independent verification, the test process hung indefinitely multiple times on:
- Test: `server/server_fault_injection_test.mbt:265` (`"fault_injection: In-flight cancellation via stop_and_drain during active streaming"`)
- Process `server.blackbox_test.exe` (PIDs: 9960, 27512, 24872) remained stuck in user wait state with CPU consumption frozen at ~0.59s–1.39s, locking the compiler workspace lock `_build\.moon-lock` for over 13 minutes until forcibly terminated with `Stop-Process`.

---

## 2. Logic Chain

1. **Ground-Truth Acceptance Criteria from ORIGINAL_REQUEST.md**:
   - `moon check --target native` strictly 0 errors, 0 warnings. (Passed, per Observation 1.1)
   - License compliance: strictly 0 GPL/AGPL, only commercial permissive licenses. (Passed, per Observation 1.2)
   - Anti-cheating & authentic implementation under Benchmark Mode. (Passed, per Observation 1.3)
   - `moon test --target native` 全量测试套件通过率保持 100%（全 PASS、0 FAIL）.
   - 结合 Win32 `GetProcessHandleCount` 强断言验证多次往返与并发异常断连下 0 句柄泄漏（0 handle leaks）.

2. **Empirical Failure of Test Gate**:
   - As documented in Observation 1.4, executing `moon test --target native` resulted in 4 test failures (164 passed, 4 failed; or 6 failed when parallelized).
   - The failing tests directly target the mandatory acceptance criterion: Win32 `GetProcessHandleCount` zero handle leak assertions under stress, abrupt client disconnections, and repeated cycles.
   - Specific assertion failures:
     - `server/server_fault_injection_test.mbt:438`: `assert_true(h2 <= h1 + 5U)` evaluated to `false`.
     - `server/server_e2e_client_test.mbt:374`: `assert_true(after_handles <= before_handles + 10U)` evaluated to `false`.
     - `server/server_challenger_test.mbt:218`: `assert_true(after_handles <= before_handles + 10U)` evaluated to `false`.
     - `server/server_challenger_test.mbt:261`: `assert_true(after_handles <= before_handles + 5U)` evaluated to `false`.

3. **Vulnerability to Deadlocks and Hangs**:
   - As documented in Observation 1.5, `server.blackbox_test.exe` consistently deadlocks in `server_fault_injection_test.mbt` during `stop_and_drain` streaming cancellation.
   - The root cause is uncoordinated client/server draining: while `TransmitFile` in `transmit_file_windows.c` is in-flight and yielding via `@async.pause()`, cancellation from `stop_and_drain` does not promptly abort the active socket write before the listener task group attempts to join, causing the test runner to hang indefinitely.

4. **Forensic Integrity Rule**:
   - Per system prompt instructions: "If ANY check fails, your verdict is INTEGRITY VIOLATION and you MUST reject the work product."
   - The delivery fails the required 100% test pass rate and empirical zero handle leak gates.

---

## 3. Caveats

- Individual test suites run in isolation (e.g. `c_suite_*` 29 tests, `core` 28 tests, `cmd` 28 tests, root 38 tests) pass 100% when filtered independently.
- The handle leak failures occur when running the full test suite sequentially within a single test binary execution (`server.blackbox_test.exe`), where rapid creation of 40–60 TCP connections interacts with Windows kernel Winsock socket cleanup latency (`TIME_WAIT`, async thread pool handle allocations), exceeding the narrow +5U / +10U test assertion thresholds.
- Only the Windows Native platform was audited (as specified in the Windows Native Milestone 6 scope).

---

## 4. Conclusion

**Verdict: INTEGRITY VIOLATION**

The Milestone 6 work product is **REJECTED**.

### Blocking Issues Requiring Resolution:
1. **Test Suite Pass Rate Failure**: `moon test --target native` fails 4 tests out of 168 (164 passed, 4 failed).
2. **Handle Count Stability in Full Suite**: The Win32 `GetProcessHandleCount` assertions in `server_fault_injection_test.mbt:438`, `server_e2e_client_test.mbt:374`, and `server_challenger_test.mbt:218, 261` fail due to residual socket handles and threadpool variance across consecutive test executions.
3. **In-Flight Cancellation Deadlock**: `server_fault_injection_test.mbt:265` (`fault_injection: In-flight cancellation via stop_and_drain during active streaming`) intermittently causes `server.blackbox_test.exe` to hang indefinitely, blocking subsequent toolchain executions.

---

## 5. Verification Method

To reproduce the findings independently:

1. **Compilation Check**:
   ```powershell
   moon check --target native
   ```
   *Expected*: Exits with code 0 (0 errors, 0 warnings).

2. **License Compliance Scan**:
   ```powershell
   rg -i "GPL" --glob "!ORIGINAL_REQUEST.md"
   ```
   *Expected*: 0 matches.

3. **Full Suite Test Execution**:
   ```powershell
   moon test --target native --no-parallelize
   ```
   *Expected Failure*: Exits with code 1. Reports 4 failing tests in `server/server_fault_injection_test.mbt`, `server/server_e2e_client_test.mbt`, and `server/server_challenger_test.mbt`.

4. **Cancellation Hang Inspection**:
   ```powershell
   moon test --target native -p unmbt/http-server-mbt/server -f "*In-flight cancellation via stop_and_drain during active streaming*"
   ```
   *Invalidation Condition*: The work product can only be approved if `moon test --target native` achieves 100% pass rate (0 failures) and no test process deadlocks during cancellation.
