# Task Assignment: M2 Challenger 2 (Security, Auth & Range RFC Challenge)

## Context
You are challenger_m2_2 (teamwork_preview_challenger).
Working Directory: D:\project\moonbit\http-server-mbt\.agents\challenger_m2_2
Project Root: D:\project\moonbit\http-server-mbt
Original User Request: D:\project\moonbit\http-server-mbt\.agents\ORIGINAL_REQUEST.md
Worker Handoff: D:\project\moonbit\http-server-mbt\.agents\worker_m2\handoff.md

## Objectives
Adversarially probe security, auth, and range RFC conformance:
1. Path traversal attacks:
   - Does `validate_relative_path` block `..`, `../`, `..\\`, `\`, NUL `\u0000`, ADS (`file.txt::$DATA`), Windows devices (`CON`, `PRN`, `AUX`, `NUL`, `COM1`, `LPT1`)?
   - Does `resolve_path` prevent root prefix collisions (e.g. `root: "public"`, target: `"public-secret/passwords.txt"`)?
2. HTTP Basic Auth:
   - Constant-time verification: does `verify_basic_auth` fail gracefully on malformed headers, wrong scheme, invalid base64, missing colon?
3. Range parsing:
   - Does `parse_range_spec` return 416 on inverted ranges (`333-222`), non-numeric (`abc-def`), out-of-bounds start?
4. Report findings and verdict: APPROVE or REQUEST_CHANGES.

## 2026-09-11T07:39:00Z
You are challenger_m2_2. Working directory: D:\project\moonbit\http-server-mbt\.agents\challenger_m2_2. Read D:\project\moonbit\http-server-mbt\.agents\ORIGINAL_REQUEST.md, AGENTS.md, worker_m2's handoff.md, and your DISPATCH.md. Adversarially challenge security (path traversal, NUL bytes, ADS, devices), constant-time Basic Auth, and RFC 7233 range 416 errors. Deliver handoff.md with verdict APPROVE or REQUEST_CHANGES and message parent.
