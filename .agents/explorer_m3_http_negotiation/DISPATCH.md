# Task Assignment: M3 HTTP Protocols & Content Negotiation Strategy

## Context
You are explorer_m3_http_negotiation (teamwork_preview_explorer).
Working Directory: D:\project\moonbit\http-server-mbt\.agents\explorer_m3_http_negotiation
Project Root: D:\project\moonbit\http-server-mbt
Original User Request: D:\project\moonbit\http-server-mbt\.agents\ORIGINAL_REQUEST.md
Scope Document: D:\project\moonbit\http-server-mbt\.agents\orchestrator_1\PROJECT.md
Design References: `docs/design.md` (D-03), `docs/tasks.md` (T-006, T-007, T-008)

## Objectives
Design the integration and implementation strategy in `engine.mbt` for:
1. HTTP/1.1 GET and HEAD dispatch:
   - HEAD computes all headers (Content-Length, Content-Type, ETag, Cache-Control, Accept-Ranges, etc.) but returns `Empty` body.
2. Conditional requests (ETag & 304):
   - Evaluate `If-None-Match` and `If-Modified-Since` via `@core.should_return_304`.
   - Return 304 Not Modified with empty body and all caching headers.
3. Range requests (RFC 7233):
   - Evaluate `Range` header via `@core.parse_range_spec`.
   - Return 206 Partial Content with `Content-Range: bytes start-end/total` and sliced body bytes.
   - Inverted or invalid ranges return 416 Range Not Satisfiable with `Content-Range: bytes */total`.
4. Pre-compression content negotiation:
   - Check for disk companion files `<path>.br` and `<path>.gz`.
   - Parse client `Accept-Encoding` header (supporting `br`, `gzip`, `*`, `q=` quality values).
   - Select appropriate representation and set `Content-Encoding` (`br` or `gzip`) and `Vary: Accept-Encoding`.
   - Handle `forceContentEncoding` flag.
5. Deliver `strategy.md` and `handoff.md`.

## 2026-09-11T07:51:06Z
You are explorer_m3_http_negotiation. Working directory: D:\project\moonbit\http-server-mbt\.agents\explorer_m3_http_negotiation. Read D:\project\moonbit\http-server-mbt\.agents\ORIGINAL_REQUEST.md, AGENTS.md, PROJECT.md, and your DISPATCH.md. Design exact strategy for GET/HEAD dispatch, conditional 304, Range 206/416 file slicing, Brotli/gzip pre-compression, and forceContentEncoding in engine.mbt. Write strategy.md and handoff.md, then message parent.
