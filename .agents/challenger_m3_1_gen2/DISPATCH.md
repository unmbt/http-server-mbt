# Dispatch: challenger_m3_1_gen2

## Identity
- Archetype: teamwork_preview_challenger
- Role: Protocol & Compression Challenger
- Working Directory: D:\project\moonbit\http-server-mbt\.agents\challenger_m3_1_gen2
- Parent: orchestrator_gen2

## Task & Scope
Adversarially probe and stress test the Milestone 3 protocol, compression, and Range implementations:
1. Probe HTTP/1.1 HEAD: verify response body is strictly empty (`ResponseBody::Empty`), while Content-Length matches the actual file size.
2. Probe Pre-Compression:
   - Accept-Encoding with quality parameters (e.g. `gzip;q=0.8, br;q=0.9`, `gzip;q=0, br;q=1.0`).
   - Corrupt gzip files lacking magic bytes `0x1F 0x8B`: server must NOT serve corrupt `.gz` as pre-compressed, must fall back to uncompressed or 404.
   - Preserved MIME: verify `Content-Type` is never set to `application/x-brotli` or `application/gzip` when serving pre-compressed assets; it must reflect the original file.
3. Probe RFC 7233 Range:
   - Inverted ranges (`100-50`), non-numeric ranges, out-of-bounds start on regular and pre-compressed files -> must return 416 with `Content-Range: bytes */total`.
   - Clamped ranges -> 206 with correct `Content-Range`.
4. Probe D-17 in-flight mutation:
   - Verify `FileLease::is_mutated` aborts when file size or mtime changes.
5. Author adversarial tests if needed in a test block, run `moon test --target native` and `moon check --target native -d`.
6. Deliver handoff report to `handoff.md` with explicit verdict: `APPROVE` or `REQUEST_CHANGES`. Report back via `send_message`.

## 2026-09-11T08:31:47Z
You are challenger_m3_1_gen2.
Your working directory is D:\project\moonbit\http-server-mbt\.agents\challenger_m3_1_gen2.
Read D:\project\moonbit\http-server-mbt\.agents\challenger_m3_1_gen2\DISPATCH.md and D:\project\moonbit\http-server-mbt\.agents\ORIGINAL_REQUEST.md.
Adversarially probe and stress-test the Milestone 3 protocol, compression, and Range implementations: HEAD body suppression with Content-Length retention, corrupt gzip magic byte fallback, preserved MIME on pre-compression, inverted/out-of-bounds Range 416, and D-17 in-flight mutation detection.
Run verification commands (moon test --target native, moon check --target native -d).
Write your challenge report to handoff.md with an explicit verdict: APPROVE or REQUEST_CHANGES.
Report back via send_message.
