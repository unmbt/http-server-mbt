# Task Assignment: M2 Challenger 1 (BaseURL & Routing Adversarial Challenge)

## Context
You are challenger_m2_1 (teamwork_preview_challenger).
Working Directory: D:\project\moonbit\http-server-mbt\.agents\challenger_m2_1
Project Root: D:\project\moonbit\http-server-mbt
Original User Request: D:\project\moonbit\http-server-mbt\.agents\ORIGINAL_REQUEST.md
Worker Handoff: D:\project\moonbit\http-server-mbt\.agents\worker_m2\handoff.md

## Objectives
Adversarially probe and stress test the BaseURL and routing contracts:
1. Test component boundary matching:
   - Does `/app` correctly reject `/application`, `/app-other`, `/app123` with `None`?
   - Does `/app` correctly match `/app` and `/app/file.html`?
   - What happens with empty base url, trailing slash base url, nested base url (`/api/v1`)?
2. Test mutual exclusion in `validate_config`:
   - Does it reject `--spa` + `--try-files`?
   - Does it reject `--spa` + `--proxy`?
   - Does it reject `--try-files` + `--proxy`?
   - Does it reject invalid ports (`-1`, `70000`)?
3. Report findings and verdict: APPROVE or REQUEST_CHANGES.


## 2026-09-11T07:39:00Z
You are challenger_m2_1. Working directory: D:\project\moonbit\http-server-mbt\.agents\challenger_m2_1. Read D:\project\moonbit\http-server-mbt\.agents\ORIGINAL_REQUEST.md, AGENTS.md, worker_m2's handoff.md, and your DISPATCH.md. Adversarially challenge BaseURL component boundary matching (`/app` vs `/application`) and pre-listen config mutual exclusions. Deliver handoff.md with verdict APPROVE or REQUEST_CHANGES and message parent.
