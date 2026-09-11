## 2026-09-11T12:47:21Z

You are the Worker for Milestone 4 (Windows Native TransmitFile & IOCP Zero-Copy Implementation - T-031).
Your working directory is: E:\project\moonbit\unmbt\http-server-mbt\.agents\worker_m4
Authoritative user request: E:\project\moonbit\unmbt\http-server-mbt\ORIGINAL_REQUEST.md (MUST read it first).
Scope document: E:\project\moonbit\unmbt\http-server-mbt\PROJECT.md
Explorer survey report: E:\project\moonbit\unmbt\http-server-mbt\.agents\explorer_survey_2\report.md (and handoff.md)
Reference docs: docs/design.md (D-16, D-17, D-18), docs/tasks.md (T-031), AGENTS.md (Native/FFI rules, 0 warnings).

MANDATORY INTEGRITY WARNING:
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A teamwork_preview_auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

File Write Ownership:
You have exclusive write ownership over:
- `server/transmit_file_windows.c`
- `server/transmit_file.mbt`
- `server/server.mbt`
- `server/moon.pkg`
- `server/server_test.mbt`
(Do NOT modify engine.mbt or core/ without explicit rationale).

Tasks to implement:
1. Win32 TransmitFile C Stub in `server/transmit_file_windows.c`:
   - `#define WIN32_LEAN_AND_MEAN`, `#include <windows.h>`, `#include <winsock2.h>`, `#include <mswsock.h>`.
   - `#pragma comment(lib, "ws2_32.lib")`, `#pragma comment(lib, "mswsock.lib")`.
   - Implement `MOONBIT_FFI_EXPORT int32_t http_server_transmit_file(SOCKET sock, const wchar_t* path, int64_t offset, int64_t length)`:
     - Open file using `CreateFileW(path, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING, FILE_FLAG_SEQUENTIAL_SCAN, NULL)`. Return error if invalid.
     - Chunk transmission in 2MB blocks (or full region if smaller).
     - Configure `OVERLAPPED` with `Offset` and `OffsetHigh` mapping to 64-bit file position.
     - Call `TransmitFile(sock, hFile, bytes_to_send, 0, &ov, NULL, 0)`.
     - Query `GetFileInformationByHandle` to verify D-17 in-flight size/modification constraints.
     - Unconditionally `CloseHandle(hFile)` on all completion/error paths to guarantee zero handle leaks.
   - Implement `MOONBIT_FFI_EXPORT uint32_t http_server_get_handle_count(void)`:
     - Calls `GetProcessHandleCount(GetCurrentProcess(), &count)` for empirical handle leak verification.
2. MoonBit FFI in `server/transmit_file.mbt`:
   - Declare `#cfg(platform="windows")` and `#cfg(not(platform="windows"))` stubs.
   - Configure `server/moon.pkg` with `"native-stub": ["transmit_file_windows.c"]`.
3. Dispatch in `server/server.mbt`:
   - Connect `FileRegion(path, offset, length)` to zero-copy `TransmitFile` on Windows Native.
   - Read Explorer 2 report for how socket handle is obtained from `@socket.Tcp` or `@http.ServerConnection`.
   - Implement a bounded 64KB chunk streaming fallback for non-Windows platforms or if `TransmitFile` is not applicable.
   - Handle `ResponseBody::Bytes` with bounded streaming.
   - Ensure clean socket closure and error handling on client disconnect / cancellation.
4. Comprehensive Integration Tests in `server/server_test.mbt`:
   - Test static file download (hash / content match).
   - Test HTTP Range requests (206 Partial Content, exact slice).
   - Test handle count stability: record `get_handle_count()` before and after requests, asserting 0 handle leak!
   - Test client disconnect / cancellation handling.
5. Verification:
   - `moon check --target native` MUST be 0 errors, 0 warnings.
   - `moon test --target native` MUST pass 100% (all existing tests + new server tests).
   - `moon info --target native` and `moon fmt`.
6. Deliver report to `report.md` and `handoff.md` in your working directory and message orchestrator.

## 2026-09-11T12:50:43Z

**Context**: User Mandate - M4 Local Git Commit Gate
**Content**: High-priority instruction from user:
Upon completing the code implementation, tests, and verifications for Milestone 4 (and BEFORE handing off for Reviewer and Auditor gate verification):
You MUST execute `git add -A` and create a local commit:
`git commit -m "feat: 实现 Milestone 4 Windows TransmitFile 零拷贝传输"`
CRITICAL: Absolutely DO NOT PUSH (`git push` is strictly forbidden)!
Verify `git status` shows clean working tree ahead by 1 commit.
Document this commit hash and status in your `report.md` and `handoff.md`.
**Action**: Incorporate this step into your Phase 6 completion protocol.
