# BRIEFING — 2026-09-11T15:32:00Z

## Mission
Investigate pre-flight validation rules, error handling, exit mechanism, and Config::validate() for Milestone 5 (T-011).

## 🔒 My Identity
- Archetype: teamwork_preview_explorer
- Roles: Pre-flight Validation & Error Handling Investigator
- Working directory: E:\project\moonbit\unmbt\http-server-mbt\.agents\explorer_m5_2
- Original parent: 1d1f0f44-178d-4d9d-aec3-2a13ccae568f
- Milestone: Milestone 5 (CLI 完整性、生命周期与架构规范)

## 🔒 Key Constraints
- Read-only investigation — do NOT implement
- Follow SDD workflow: check proposal.md, design.md, tasks.md (T-011)
- Write handoff report to handoff.md
- Output path discipline: write only to your folder

## Current Parent
- Conversation ID: 1d1f0f44-178d-4d9d-aec3-2a13ccae568f
- Updated: 2026-09-11T15:32:00Z

## Investigation State
- **Explored paths**:
  - `ORIGINAL_REQUEST.md` (Milestone 5 Follow-up)
  - `docs/proposal.md`, `docs/design.md` (D-01, D-02, D-04, D-08, D-16, D-18), `docs/tasks.md` (T-011, C033, C041)
  - `cmd/http-server-mbt/main.mbt`, `cmd/http-server-mbt/moon.pkg`
  - `core/config.mbt`, `core/routing.mbt`, `core/routing_config_adversarial_test.mbt`
  - MoonBit toolchain core packages (`argparse`, `builtin`, `env`, `io`)
  - `moonbitlang/async` mooncake (`stdio`, `fs`, `process`, `signal`)
  - `http-server/bin/http-server`, `http-server/test/process-env-port.test.js`
- **Key findings**:
  1. `cmd/http-server-mbt/main.mbt` currently prints errors to stdout with `println` and returns 0 instead of printing to stderr and exiting with 1.
  2. Exit mechanism: standard library `argparse` uses `extern "c" fn runtime_native_exit(code : Int) = "exit"`, which cleanly terminates without leaking stack traces or unhandled aborts.
  3. Stderr output: `@stdio.stderr` in `moonbitlang/async/stdio` connects to Windows `STD_ERROR_HANDLE` (`-12`) and implements `@io.Writer`.
  4. Physical filesystem validation: `root` must exist and be a directory (`@fs.exists(root) && @fs.kind(root) is @fs.FileKind::Directory`). `core` must remain pure without `@fs` per D-02, so physical checks belong to the Native execution layer (`cmd` and `server`/`engine`).
  5. Port validation: Must reject `<= 0` or `> 65535` or non-numeric. Must support float truncation (`9090.86` -> `9090`) per AD-04/C033.02.
  6. Routing & Auth validation: `core.resolve_base_url` detects conflicting `--base-url` and `--base-dir`. Auth `--auth` requires `:` separator.
  7. Config validation: `core.validate_config` already validates mutual exclusions (`--spa` + `--try-files`, fallback + proxy, proxy-all without proxy, try-files syntax, custom headers CRLF), but needs `cache_seconds < -1` check and instance method `Config::validate()`.
- **Unexplored areas**: None for this investigation phase.

## Key Decisions Made
- Documented full pre-flight validation rules and error flow in `handoff.md`.
- Recommended exact code architectures for `core/config.mbt` and `cmd/http-server-mbt/main.mbt`.

## Artifact Index
- `handoff.md` — Complete investigation report with findings, logic chain, caveats, and recommendations
- `progress.md` — Step-by-step progress tracking
- `DISPATCH.md` — Incoming instruction log
