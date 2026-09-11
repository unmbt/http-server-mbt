## 2026-09-11T14:34:13Z
<USER_REQUEST>
You are the Final Gate & Git Commit Worker for Milestone 4 (Windows Native TransmitFile & IOCP Zero-Copy Implementation T-031).
Your working directory is: E:\project\moonbit\unmbt\http-server-mbt\.agents\worker_final_commit
Authoritative user request: E:\project\moonbit\unmbt\http-server-mbt\ORIGINAL_REQUEST.md (MUST read it first).
Scope document: E:\project\moonbit\unmbt\http-server-mbt\PROJECT.md

MANDATORY INTEGRITY WARNING:
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A teamwork_preview_auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

CRITICAL INSTRUCTIONS FROM USER:
1. Verification:
   - Run `moon check --target native`: MUST yield 0 errors and 0 warnings.
   - Run `moon test --target native`: MUST pass 100% of all tests (83/83 passed, 0 failures, 0 hangs).
   - Run `moon info --target native` and `moon fmt`.
2. Documentation updates:
   - In `docs/tasks.md`: Mark T-031 as completed `- [x] T-031: Windows TransmitFile 与 IOCP 零拷贝传输 (Windows Native, 83/83 tests pass, 0 handle leaks)` with date 2026-09-11 and evidence.
   - In `docs/progress.md`: Update Milestone 4 status to completed with verification evidence (83/83 passed, 0 errors, 0 warnings, zero handle leaks across repeated requests, Win32 TransmitFile kernel zero-copy verified).
3. Local Git Commit Gate:
   - In workspace root `E:\project\moonbit\unmbt\http-server-mbt`:
     Run `git status` to check all modified and untracked files.
     Run `git add -A`.
     Run `git commit -m "feat: 完善 Milestone 4 Windows TransmitFile 零拷贝传输与门禁测试闭环"`.
     Run `git log -1` and `git status` to verify commit succeeded and working tree is clean.
   - STRICT MANDATE: ABSOLUTELY NEVER EXECUTE `git push`! The user strictly commanded: "执行本地 commit（严格禁止 push）！"
4. Report:
   Write full execution evidence to `E:\project\moonbit\unmbt\http-server-mbt\.agents\worker_final_commit\report.md` and `handoff.md`, then send a completion message to orchestrator.
</USER_REQUEST>
