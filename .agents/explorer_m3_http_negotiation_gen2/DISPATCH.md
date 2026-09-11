# Dispatch: explorer_m3_http_negotiation_gen2

## Identity
- Archetype: teamwork_preview_explorer
- Role: Protocol & Compression Analyst
- Working Directory: D:\project\moonbit\http-server-mbt\.agents\explorer_m3_http_negotiation_gen2
- Parent: orchestrator_gen2

## Task & Scope
Investigate and design implementation strategy for HTTP/1.1 protocol handling and pre-compression in Milestone 3:
1. HTTP/1.1 GET/HEAD dispatch in `engine.mbt`:
   - For HEAD requests: compute headers (Content-Length, Content-Type, ETag, Last-Modified, Cache-Control), evaluate conditional 304, but suppress response body (`ResponseBody::Empty`).
2. Conditional requests (304 Not Modified):
   - Evaluate `If-None-Match` and `If-Modified-Since` using `@core.should_return_304`. On 304, return empty body with ETag and cache headers.
3. Byte Range Requests (RFC 7233):
   - Parse `Range` header via `@core.parse_range_spec`.
   - Return 206 Partial Content with `Content-Range: bytes start-end/total` and `ResponseBody::FileRegion`.
   - Return 416 Range Not Satisfiable with `Content-Range: bytes */total` when range is invalid.
4. Pre-compression negotiation:
   - When client sends `Accept-Encoding: br, gzip`, check for `<path>.br` (Brotli) and `<path>.gz` (gzip).
   - Quality preference: prefer `.br` if accepted, then `.gz`.
   - Set `Content-Encoding: br` or `gzip` and `Vary: Accept-Encoding`. The `Content-Type` must remain that of the original uncompressed file!
5. `forceContentEncoding`:
   - If configured for extensions (e.g. `.gz`), force `Content-Encoding: gzip`.
6. In-flight file mutation detection (D-17):
   - Check file size/mtime before/during streaming. Abort if FILE_CHANGED.

## Relevant Files to Read
- D:\project\moonbit\http-server-mbt\.agents\ORIGINAL_REQUEST.md (MANDATORY)
- D:\project\moonbit\http-server-mbt\.agents\orchestrator_gen2\PROJECT.md
- D:\project\moonbit\http-server-mbt\engine.mbt
- D:\project\moonbit\http-server-mbt\core\cache.mbt
- D:\project\moonbit\http-server-mbt\core\range.mbt
- D:\project\moonbit\http-server-mbt\core\mime.mbt
- D:\project\moonbit\http-server-mbt\docs\design.md (D-03, D-17)

## Deliverables


## 2026-09-11T08:03:38Z
You are explorer_m3_http_negotiation_gen2.
Your working directory is D:\project\moonbit\http-server-mbt\.agents\explorer_m3_http_negotiation_gen2.
Read D:\project\moonbit\http-server-mbt\.agents\explorer_m3_http_negotiation_gen2\DISPATCH.md and D:\project\moonbit\http-server-mbt\.agents\ORIGINAL_REQUEST.md.
Investigate HTTP/1.1 GET/HEAD dispatch, conditional 304, Range 206/416, Brotli/gzip pre-compression negotiation, forceContentEncoding, and FILE_CHANGED in-flight mutation detection.
Write your analysis and implementation strategy to strategy.md and handoff.md in your working directory.
When done, report back using send_message.
