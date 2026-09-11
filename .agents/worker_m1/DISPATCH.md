# Task Assignment: M1 Warning Elimination & Clean Baseline Implementation

## Context
You are worker_m1 (teamwork_preview_worker).
Working Directory: D:\project\moonbit\http-server-mbt\.agents\worker_m1
Project Root: D:\project\moonbit\http-server-mbt
Original User Request: D:\project\moonbit\http-server-mbt\.agents\ORIGINAL_REQUEST.md
Scope Document: D:\project\moonbit\http-server-mbt\.agents\orchestrator_1\PROJECT.md

MANDATORY INTEGRITY WARNING:
> DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A teamwork_preview_auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

## Strategy Inputs
Read the strategies formulated by the 3 M1 explorers:
1. D:\project\moonbit\http-server-mbt\.agents\explorer_m1_core\strategy.md
2. D:\project\moonbit\http-server-mbt\.agents\explorer_m1_engine\strategy.md
3. D:\project\moonbit\http-server-mbt\.agents\explorer_m1_server_cmd\strategy.md

## Write Ownership
You exclusively own and may edit the following files:
- `core/core.mbt`
- `core/core_test.mbt`
- `engine.mbt`
- `engine_test.mbt`
- `moon.pkg`
- `server/server.mbt`
- `server/moon.pkg`
- `cmd/http-server-mbt/main.mbt`

## Objectives & Verification
1. Apply the changes from the 3 strategy documents:
   - In `core/core.mbt`: remove redundant `pub` modifiers from struct fields, rename `method` -> `meth`, replace `\x00` with `\u0000`, add `validate_root` using `InvalidRoot`. In `core/core_test.mbt`: update test cases and add `validate_root` test.
   - In `engine.mbt`: remove redundant `pub` modifiers from `Response`, rename `use` -> `handler` (or `register_handler`), use `@utf8.encode()` and `BytesView::to_owned()` instead of deprecated `.to_bytes()`, handle `request.meth`, handle unused constructors `NotFound` and `Closed`.
   - In `engine_test.mbt`: update request fields `method` -> `meth`.
   - In `moon.pkg`: remove unused imports (`moonbitlang/async`, `moonbitlang/async/http`).
   - In `server/server.mbt`: rename parameter `use` -> `action`, rename `method` -> `meth`, use `@debug.to_string()`, replace `Map::new()` with `Map([])`.
   - In `server/moon.pkg`: remove unused import `"moonbitlang/async"`.
   - In `cmd/http-server-mbt/main.mbt`: replace `async fn(_server)` with `fn(_server)`.
2. Run `moon check --target native` and verify that output has **0 warnings, 0 errors**!
3. Run `moon test --target native` and verify that all tests pass.
4. Run `moon info --target native`, then run `moon fmt`.
5. Document all commands, execution outputs, and file diffs in `D:\project\moonbit\http-server-mbt\.agents\worker_m1\handoff.md`.
6. Send a completion message to the parent orchestrator.

## 2026-09-11T06:56:19Z
You are worker_m1. Working directory: D:\project\moonbit\http-server-mbt\.agents\worker_m1. Read D:\project\moonbit\http-server-mbt\.agents\ORIGINAL_REQUEST.md, AGENTS.md, PROJECT.md, and your DISPATCH.md. Implement all warning elimination changes from the 3 strategy documents, run `moon check --target native` (verify 0 warnings, 0 errors), `moon test --target native`, `moon info --target native`, and `moon fmt`. Complete your handoff.md and send a message to parent.

MANDATORY INTEGRITY WARNING:
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A teamwork_preview_auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.
