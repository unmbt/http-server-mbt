# Orchestrator Context — Milestone 5

## Mission
实现 Milestone 5（CLI 完整性、生命周期与架构规范）：为 `cmd/http-server-mbt` 提供原版对齐的完整命令行参数解析、监听前拦截非法配置、优雅信号退出与许可证合规审计。

## Key References
- Authoritative user request: `E:\project\moonbit\unmbt\http-server-mbt\ORIGINAL_REQUEST.md`
- SDD Contracts: `docs/proposal.md`, `docs/design.md`, `docs/tasks.md` (T-011)
- Project Progress: `docs/progress.md`
- Windows Baseline: `docs/windows-baseline.md`
- Architecture & Rules: `AGENTS.md` (SDD workflow, 0 warnings, resource safety)

## Key Constraints
1. **0 Warnings & 0 Errors**: `moon check --target native` must maintain 0 errors, 0 warnings.
2. **Git Workflow Gate**:
   - Once Milestone 5 code implementation is complete, MUST run `git add -A` and commit locally (e.g. `feat: 实现 Milestone 5 完整 CLI 参数与生命周期`), STRICTLY DO NOT PUSH!
   - Reviewer and Auditor review only after local commit is verified.
   - After all reviews and gates pass, final local commit closure!
3. **Full multi-agent team**: Orchestrator manages workers, reviewers, challengers, and prepares for victory audit.
