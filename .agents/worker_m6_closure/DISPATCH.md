# DISPATCH — worker_m6_closure

## Identity
- Role: teamwork_preview_worker
- Working Directory: E:\project\moonbit\unmbt\http-server-mbt\.agents\worker_m6_closure
- Parent: orchestrator_m6_gen3 (Conv ID: 0b32e84a-00ea-40d9-85b1-44f9feb1b2a5)
- Original Request Path: E:\project\moonbit\unmbt\http-server-mbt\.agents\ORIGINAL_REQUEST.md

## Integrity Warning
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A teamwork_preview_auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

## Objective
Execute R4: Closure, Interface Checks, Formatting, Documentation Synchronization, and Local Git Commit for Milestone 6.

## Specific Tasks
1. Run `moon info --target native` to update/verify `.mbti` interface declarations.
2. Run `moon fmt` to ensure clean code formatting across all MoonBit files.
3. Update documentation files in `docs/`:
   - `docs/tasks.md`: Update Milestone 6 tasks (T-025, T-034, etc.) to completed `- [x]` with evidence (169/169 tests pass, 0 errors, 0 warnings, Reviewer/Challenger/Auditor approvals).
   - `docs/progress.md`: Update Milestone 6 section with the gate closure status, test pass evidence (169/169 pass), zero handle leaks, and ready for victory audit.
4. Run `git status` and `git diff` to review documentation changes and ensure no unexpected changes exist.
5. Stage and commit locally:
   ```bash
   git add docs/tasks.md docs/progress.md
   git commit -m "feat: 完成 Milestone 6 审查门禁闭环与文档同步"
   ```
   Note: If `.mbti` or other files were updated by `moon info` / `moon fmt`, stage those as well.
6. **STRICTLY FORBIDDEN: NEVER execute `git push`!** Only commit locally.
7. Write your handoff report to `E:\project\moonbit\unmbt\http-server-mbt\.agents\worker_m6_closure\handoff.md` with git commit hash and command outputs.
8. Send message back to parent when complete.

## 2026-09-12T11:01:20Z
You are worker_m6_closure.
Your working directory is: E:\project\moonbit\unmbt\http-server-mbt\.agents\worker_m6_closure
Your DISPATCH file is: E:\project\moonbit\unmbt\http-server-mbt\.agents\worker_m6_closure\DISPATCH.md
Your parent is orchestrator_m6_gen3 (conv ID: 0b32e84a-00ea-40d9-85b1-44f9feb1b2a5).

Follow all instructions in DISPATCH.md:
1. Run `moon info --target native`.
2. Run `moon fmt`.
3. Update `docs/tasks.md` and `docs/progress.md` with Milestone 6 completion evidence (169/169 tests pass, 0 errors, 0 warnings, Reviewer/Challenger/Auditor unanimous approval).
4. Stage and commit locally with message `feat: 完成 Milestone 6 审查门禁闭环与文档同步`.
5. STRICTLY FORBIDDEN: NEVER execute `git push`!
6. Write your handoff report to `E:\project\moonbit\unmbt\http-server-mbt\.agents\worker_m6_closure\handoff.md` and send_message back to parent.
