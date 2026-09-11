## 2026-09-11T12:29:00Z
You are Explorer 2 for the Project Survey phase.
Your working directory is: E:\project\moonbit\unmbt\http-server-mbt\.agents\explorer_survey_2
Authoritative user request: E:\project\moonbit\unmbt\http-server-mbt\ORIGINAL_REQUEST.md (MUST read it first).
Project references: docs/proposal.md, docs/design.md, docs/tasks.md (specifically T-031), docs/windows-baseline.md, AGENTS.md.

Task: Deep technical investigation of Milestone 4 Windows Native TransmitFile and IOCP zero-copy transmission (T-031).
Specifically:
1. Examine docs/design.md (D-16 Windows Native baseline, D-17 file change detection, D-18 fault injection) and docs/tasks.md (T-031).
2. Examine server/server.mbt, core/core.mbt (specifically ResponseBody::FileRegion(path, offset, length)), engine.mbt, and target build settings.
3. Investigate the current network I/O stack in `server/`:
   - What library or FFI is currently used? How does `moonbitlang/async/http` or the server accept connections and write response bodies?
   - Can we access or obtain the underlying Windows OS socket handle (SOCKET) from the connection?
   - How can Win32 `TransmitFile` (from `mswsock.dll` / `ws2_32.dll`) or Windows Overlapped I/O be invoked via MoonBit Native C FFI / stub?
   - How does `TransmitFile` handle offset and length (via `OVERLAPPED` structure `Offset` and `OffsetHigh`)?
   - How does TransmitFile handle Range requests (FileRegion with offset > 0 and bounded length)?
   - How should bounded buffer fallback be implemented for non-file responses, in-memory bytes, or when TransmitFile is unavailable / fails?
   - How should slow clients, timeouts, client disconnection, and cancellation be handled to ensure zero handle leaks (both file HANDLE via CloseHandle and socket SOCKET)?
4. Examine MoonBit Native C FFI rules:
   - Review AGENTS.md and moonbit-c-binding requirements.
   - Where should C stubs be placed? (`server/` or a dedicated package or C files in package directory?)
   - How does MoonBit package system handle C files or FFI in `moon.pkg`?
5. Propose a clear, robust architecture and step-by-step implementation plan for T-031.
Write your findings to E:\project\moonbit\unmbt\http-server-mbt\.agents\explorer_survey_2\report.md and handoff.md, then send a message to orchestrator.
