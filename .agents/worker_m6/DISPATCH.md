## 2026-09-11T18:16:21Z

# Task Assignment: Worker M6 (Milestone 6 Implementation)

## Working Directory
E:\project\moonbit\unmbt\http-server-mbt\.agents\worker_m6

## Authoritative Inputs
- `ORIGINAL_REQUEST.md` (E:\project\moonbit\unmbt\http-server-mbt\.agents\ORIGINAL_REQUEST.md)
- `AGENTS.md` (E:\project\moonbit\unmbt\http-server-mbt\AGENTS.md)
- `docs/tasks.md`, `docs/design.md`, `docs/proposal.md`, `docs/progress.md`
- Explorer Reports:
  - `E:\project\moonbit\unmbt\http-server-mbt\.agents\explorer_m6_1\handoff.md` (Original Test Suite Migration Matrix & Fixtures)
  - `E:\project\moonbit\unmbt\http-server-mbt\.agents\explorer_m6_2\handoff.md` (Real HTTP Client E2E Architecture & Code)
  - `E:\project\moonbit\unmbt\http-server-mbt\.agents\explorer_m6_3\handoff.md` (Fault Injection & 0 Handle Leaks Harness & Code)

## MANDATORY INTEGRITY WARNING
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A teamwork_preview_auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

## Tasks & Responsibilities
1. **Synchronize Test Fixtures**:
   - Copy required test files from `http-server/test/public/` to `testdata/public/` and `http-server/test/fixtures/root/` to `testdata/fixtures/root/`.
   - Ensure you do NOT modify anything inside `http-server/`!
2. **Implement Real HTTP Client E2E Suite**:
   - Create `server/server_e2e_client_test.mbt` using the wire-level parsing client (`TcpClient`, `HttpResponse`) and test cases designed by `explorer_m6_2`.
   - Apply the minimal 4-line patch in `server/server.mbt` for 405 Method Not Allowed handling if appropriate.
3. **Implement Fault Injection & Concurrency Suite (T-034 / D-18)**:
   - Create `server/server_fault_injection_test.mbt` using the 7 scenarios designed by `explorer_m6_3` (slowloris trickle header, incomplete header truncation, slow client read with Overlapped backpressure, abrupt mid-stream disconnect with CancelIoEx, in-flight stop_and_drain cancel, high-concurrency chaotic traffic, multi-round empirical zero handle leak verification).
4. **Implement Original Test Suite Migration Files (C001~C042, CC-01~CC-28, CE-01~CE-02)**:
   - Create modular test files in `server/`:
     - `server/c_suite_common_cases_test.mbt` (CC-01~CC-28, CE-01~CE-02, C008, C009, C035, C036)
     - `server/c_suite_protocol_test.mbt` (C001~C007, C010~C015)
     - `server/c_suite_directory_security_test.mbt` (C016~C030)
     - `server/c_suite_network_lifecycle_test.mbt` (C031~C034, C037, C040)
     - `server/c_suite_main_test.mbt` (C042)
   - Adhere to AD-01~AD-10 platform constraints (e.g. AD-05 Windows path skip for `<dir>` while testing NUL byte and HTML escaping).
5. **Quality & Verification Checks**:
   - Run `moon check --target native`: MUST produce 0 errors, 0 warnings.
   - Run `moon test --target native`: ALL tests (116 existing + all new suites) MUST pass 100%. Zero hangs, zero panics, zero handle leaks.
   - Run `moon info --target native` and `moon fmt`.
6. **Intermediate Git Commit Gate (Phase 3)**:
   - After code implementation and tests pass, run:
     `git add -A`
     `git commit -m "feat: 实现 Milestone 6 原版全量测试套件迁移与状态机故障注入测试"`
   - STRICTLY DO NOT PUSH!
7. **Delivery**:
   - Write your handoff report to `E:\project\moonbit\unmbt\http-server-mbt\.agents\worker_m6\handoff.md`.
   - Notify orchestrator upon completion.
