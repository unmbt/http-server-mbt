# BRIEFING — 2026-09-12T02:41:00Z

## Mission
Investigate Win32 GetProcessHandleCount assertion failures across the test suite and formulate a clean, concrete fix strategy.

## 🔒 My Identity
- Archetype: explorer
- Roles: read-only investigator, synthesizer
- Working directory: E:\project\moonbit\unmbt\http-server-mbt\.agents\explorer_m6_fix_1
- Original parent: dcf6fc8a-69f5-4537-8275-a1f2ab70f9af
- Milestone: m6

## 🔒 Key Constraints
- Read-only investigation — do NOT implement
- Analyze why Win32 GetProcessHandleCount fails in server_fault_injection_test.mbt:369, server_e2e_client_test.mbt:333, server_challenger_test.mbt:158, server_challenger_test.mbt:222
- Formulate concrete fix strategy for the worker

## Current Parent
- Conversation ID: dcf6fc8a-69f5-4537-8275-a1f2ab70f9af
- Updated: not yet

## Investigation State
- **Explored paths**:
  - `server/server_fault_injection_test.mbt:369`
  - `server/server_e2e_client_test.mbt:333`
  - `server/server_challenger_test.mbt:158, 222`
  - `server/server_challenger_m5_lifecycle_test.mbt:306`
  - `server/server_challenger_m4_2_test.mbt:74`
  - `server/server_challenger_m6_test.mbt` (the passing golden reference)
  - `server/transmit_file_windows.c`
  - `server/server.mbt`
  - `E:\project\moonbit\unmbt\http-server-mbt\.mooncakes\moonbitlang\async\src\socket\tcp.mbt`
- **Key findings**:
  - In isolation, all 4 tests pass 100% cleanly (0 leaks).
  - In full suite run, failures are caused by:
    1. Lack of / inadequate warmup (conflating one-time Windows thread pool & IOCP runtime scaling of ~12-15 handles with leaks).
    2. Insufficient drain time (0ms or 50ms is too short for asynchronous AFD socket teardown across 30-60 connections).
    3. Flawed baseline sampling (taking `before_handles` BEFORE server starts or without warmup).
    4. Client tight loops without `@async.pause()`, starving server connection fibers from running `defer conn.close()`.
    5. In-flight cancellation hang in `server_fault_injection_test.mbt:265` caused by client tasks racing with `stop_and_drain`.
- **Unexplored areas**: None within the scope of the requested 4 tests and handle leak assertions.

## Key Decisions Made
- Formulate 4-pillar fix strategy: Warmup Requests, Drain Time, Delta Calculation, Socket Explicit Closing & Yielding.
- Provide verbatim before-and-after code snippets for each failing test.
- Include fix for the cancellation hang race in `server_fault_injection_test.mbt:265`.

## Artifact Index
- DISPATCH.md — incoming instructions log
- BRIEFING.md — working memory
- progress.md — liveness heartbeat
- handoff.md — final analysis and fix strategy
