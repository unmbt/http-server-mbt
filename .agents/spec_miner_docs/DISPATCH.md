# Task Assignment: Specifications & Design Docs Mining

## Context
You are spec_miner_docs (teamwork_preview_spec_miner).
Working Directory: D:\project\moonbit\http-server-mbt\.agents\spec_miner_docs
Project Root: D:\project\moonbit\http-server-mbt
Original User Request: D:\project\moonbit\http-server-mbt\.agents\ORIGINAL_REQUEST.md

## Objective
Thoroughly examine all specification and design documents in `docs/`:
1. Read D:\project\moonbit\http-server-mbt\.agents\ORIGINAL_REQUEST.md and AGENTS.md.
2. Read `docs/proposal.md`, `docs/design.md`, `docs/tasks.md`, `docs/windows-baseline.md`.
3. Extract and catalog:
   - All requirement IDs (R1-R4, sub-requirements, acceptance criteria).
   - Design contracts (D-01 to D-18): exact behavior for Windows TransmitFile / IOCP zero-copy, fallback buffering, handle leak prevention, BaseURL mount (--base-url, --base-dir), SPA & try-files fallback, conditional requests (ETag strong/weak, If-None-Match, If-Modified-Since, 304), Range requests (206, Content-Range, 416), pre-compression negotiation (br, gzip, Accept-Encoding), MIME resolution, directory listing & indexing, security & basic auth (constant-time compare, auth before file probe), CLI options & lifecycle.
   - Tasks list (T-001 to T-032) and their current status/dependencies.
4. Synthesize these into an actionable requirement & design inventory in `D:\project\moonbit\http-server-mbt\.agents\spec_miner_docs\spec_miner_report.md` and complete your handoff.md.

## Communication
When finished, send a message to orchestrator parent with the path to your report.

## 2026-09-11T06:44:38Z
You are spec_miner_docs. Working directory: D:\project\moonbit\http-server-mbt\.agents\spec_miner_docs. Read D:\project\moonbit\http-server-mbt\.agents\ORIGINAL_REQUEST.md, AGENTS.md, docs/proposal.md, docs/design.md, docs/tasks.md, docs/windows-baseline.md, and your DISPATCH.md. Extract requirements, design contracts D-01..D-18, task statuses T-001..T-032, and write spec_miner_report.md and handoff.md in your working directory. Then send a message to parent with your findings.

