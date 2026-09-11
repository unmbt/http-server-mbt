# Task Assignment: M2 Reviewer 2 (Code Quality, Security & Standards Review)

## Context
You are reviewer_m2_2 (teamwork_preview_reviewer).
Working Directory: D:\project\moonbit\http-server-mbt\.agents\reviewer_m2_2
Project Root: D:\project\moonbit\http-server-mbt
Original User Request: D:\project\moonbit\http-server-mbt\.agents\ORIGINAL_REQUEST.md
Worker Handoff: D:\project\moonbit\http-server-mbt\.agents\worker_m2\handoff.md

## Objectives
1. Read ORIGINAL_REQUEST.md, AGENTS.md, and worker_m2's handoff.md.
2. Review the code quality and security implementation in `core/`:
   - `core/security.mbt`: Verify timing attack safety of `crypto_equals` (constant-time, no early return on length mismatch), path traversal sanitization, root anchoring.
   - `core/config.mbt` & `core/routing.mbt`: Verify component boundary matching (`/app` vs `/application`), pre-listen mutual exclusions.
   - `core/mime.mbt`, `core/cache.mbt`, `core/range.mbt`: Check standards compliance (RFC 7231, 7232, 7233).
3. Run `moon fmt` and verify clean code formatting.
4. Provide your verdict: APPROVE or REQUEST_CHANGES in your handoff.md and message parent.

## 2026-09-11T07:39:00Z
You are reviewer_m2_2. Working directory: D:\project\moonbit\http-server-mbt\.agents\reviewer_m2_2. Read D:\project\moonbit\http-server-mbt\.agents\ORIGINAL_REQUEST.md, AGENTS.md, worker_m2's handoff.md, and your DISPATCH.md. Review code quality, security implementation (timing-safe Basic Auth, path traversal defense), and code formatting (`moon fmt`). Deliver handoff.md with verdict APPROVE or REQUEST_CHANGES and message parent.
