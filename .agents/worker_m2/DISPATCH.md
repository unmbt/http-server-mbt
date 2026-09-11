# Task Assignment: M2 Core Protocols, MIME, Security & Config Implementation

## Context
You are worker_m2 (teamwork_preview_worker).
Working Directory: D:\project\moonbit\http-server-mbt\.agents\worker_m2
Project Root: D:\project\moonbit\http-server-mbt
Original User Request: D:\project\moonbit\http-server-mbt\.agents\ORIGINAL_REQUEST.md
Scope Document: D:\project\moonbit\http-server-mbt\.agents\orchestrator_1\PROJECT.md

MANDATORY INTEGRITY WARNING:
> DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A teamwork_preview_auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

## Strategy Inputs
Read the strategies formulated by the 3 M2 explorers:
1. `D:\project\moonbit\http-server-mbt\.agents\explorer_m2_security_path\strategy.md`
2. `D:\project\moonbit\http-server-mbt\.agents\explorer_m2_mime_ranges_cache\strategy.md`
3. `D:\project\moonbit\http-server-mbt\.agents\explorer_m2_config_routing\strategy.md`

## Write Ownership
You exclusively own and may edit the following files:
- `core/core.mbt`
- `core/config.mbt`
- `core/routing.mbt`
- `core/security.mbt`
- `core/mime.mbt`
- `core/cache.mbt`
- `core/range.mbt`
- `core/core_test.mbt`
- `engine.mbt` (only to update `path_for` / integrate with new core functions)
- `engine_test.mbt`

## Objectives & Implementation Details
1. **Config & Routing**:
   - Expand `core.Config` to support all necessary fields (port, address, spa, try_files, cache_seconds, cors, coop, pna, basic_auth, host_whitelist, etc.) with dual defaults (`Config::default` and `Config::middleware_default`).
   - Implement BaseURL normalization (`normalize_base_url`), alias resolution (`resolve_base_url`), and strict component boundary matching (`match_and_strip_base_url`).
   - Implement pre-listen mutual exclusion and path validation (`validate_config`, `validate_try_files_path`).
2. **Security & Path Traversal**:
   - Implement strict path traversal defense (`resolve_path`, `validate_relative_path`), fixing empty string / root handling so `GET /` resolves cleanly to root.
   - Implement constant-time HTTP Basic Auth comparison (`verify_basic_auth` / `crypto_equals`).
   - Implement security headers generation (`apply_security_headers`) for CORS, COOP, and PNA.
   - Implement Host whitelist checking (`verify_host`).
3. **MIME, Ranges & Cache**:
   - Implement comprehensive MIME registry (60+ types), `.types` file parser, and charset detection (<=1024 bytes).
   - Implement default extension completion (`apply_default_ext`).
   - Implement ETag generation (`EntityTag`), strong/weak comparison, If-None-Match, If-Modified-Since HTTP date parsing & comparison, and Cache-Control header formatting.
   - Implement RFC 7233 byte range parsing, 206 Content-Range formatting, and 416 Range Not Satisfiable detection.
4. **Unit Tests in `core/core_test.mbt`**:
   - Write comprehensive unit tests covering all new functions (BaseURL matching, mutual exclusions, path defense, Basic Auth, CORS/COOP/PNA, MIME resolution, ETag 304 decision, Range parsing & 416).
5. **Verification**:
   - Run `moon check --target native` and ensure **0 warnings, 0 errors**.
   - Run `moon test --target native` and ensure **100% tests pass**.
   - Run `moon info --target native`, then `moon fmt`.
   - Write self-contained `handoff.md` and report to parent.

## 2026-09-11T07:25:52Z
You are worker_m2. Working directory: D:\project\moonbit\http-server-mbt\.agents\worker_m2. Read D:\project\moonbit\http-server-mbt\.agents\ORIGINAL_REQUEST.md, AGENTS.md, PROJECT.md, and your DISPATCH.md. Implement all M2 core protocols, MIME, security, and config modules using the 3 explorer strategies. Run `moon check --target native` (verify 0 warnings, 0 errors), `moon test --target native` (verify 100% pass), `moon info --target native`, and `moon fmt`. Complete handoff.md and send a message to parent.

MANDATORY INTEGRITY WARNING:
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A teamwork_preview_auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.
