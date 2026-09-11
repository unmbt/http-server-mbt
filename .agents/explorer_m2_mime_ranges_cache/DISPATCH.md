# Task Assignment: M2 MIME, Ranges & Cache Strategy

## Context
You are explorer_m2_mime_ranges_cache (teamwork_preview_explorer).
Working Directory: D:\project\moonbit\http-server-mbt\.agents\explorer_m2_mime_ranges_cache
Project Root: D:\project\moonbit\http-server-mbt
Original User Request: D:\project\moonbit\http-server-mbt\.agents\ORIGINAL_REQUEST.md
Scope Document: D:\project\moonbit\http-server-mbt\.agents\orchestrator_1\PROJECT.md
Design References: `docs/design.md` (D-03), `docs/tasks.md` (T-006, T-007, T-008)

## Objectives
Design the architecture and exact implementation strategy in `core/` for:
1. MIME type registry & `.types` parser:
   - Comprehensive standard MIME table for static web assets (html, css, js, mjs, json, txt, xml, svg, png, jpg, jpeg, gif, webp, ico, wasm, pdf, zip, gz, br, etc.).
   - Support for custom MIME overrides and parsing standard `.types` files (mapping extension to MIME type).
   - Character set handling (e.g. `text/html; charset=utf-8`).
2. Default extension completion:
   - Handling `defaultExt` (`html` by default) when requesting extensionless path.
3. ETag & Cache Negotiation:
   - Strong and weak ETag format (`W/"..."`).
   - If-None-Match comparison (supporting comma-separated list, `*`, weak comparison).
   - If-Modified-Since HTTP date parsing & RFC 7231 comparison.
   - Cache-Control header generator (seconds to `max-age=...`, -1 to `no-cache, no-store, must-revalidate`).
4. Range requests (RFC 7233):
   - Parse `Range: bytes=start-end`, bare `start-end`, prefix `start-`, suffix `-len`.
   - Calculate `Content-Range: bytes start-end/total`.
   - Detect 416 Range Not Satisfiable when range is inverted (`333-222`) or start >= total.
5. Write detailed strategy in `strategy.md` and `handoff.md`. Do NOT edit source code files.

## 2026-09-11T07:19:04Z
You are explorer_m2_mime_ranges_cache. Working directory: D:\project\moonbit\http-server-mbt\.agents\explorer_m2_mime_ranges_cache. Read D:\project\moonbit\http-server-mbt\.agents\ORIGINAL_REQUEST.md, AGENTS.md, PROJECT.md, and your DISPATCH.md. Design exact architecture and implementation strategy in core/ for MIME types registry, .types parser, default extension, ETag strong/weak, If-None-Match/If-Modified-Since, Range parsing (206/416), and Cache-Control. Write strategy.md and handoff.md, then message parent.
