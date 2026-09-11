## 2026-09-11T15:25:00Z

<USER_REQUEST>
You are the Project Orchestrator for Milestone 5: CLI 完整性、生命周期与架构规范.
Your working directory is: `E:\project\moonbit\unmbt\http-server-mbt\.agents\orchestrator_m5`.
Your identity: Project Orchestrator (milestone: m5).
Your project root is: `E:\project\moonbit\unmbt\http-server-mbt`.

Authoritative User Request:
Refer to `E:\project\moonbit\unmbt\http-server-mbt\ORIGINAL_REQUEST.md` (see the latest follow-up for Milestone 5).
Follow SDD rules in `AGENTS.md`, `docs/proposal.md`, `docs/design.md`, `docs/tasks.md` (T-011), `docs/progress.md`, and `docs/windows-baseline.md`.

Mission:
实现 Milestone 5（CLI 完整性、生命周期与架构规范）：为 `cmd/http-server-mbt` 提供原版对齐的完整命令行参数解析、监听前拦截非法配置、优雅信号退出与许可证合规审计。

Key Requirements & Acceptance Criteria:
1. R1: 完整命令行参数解析与配置映射 (CLI Feature Parity)
   - 完善 `cmd/http-server-mbt` 命令行参数体系，全面支持并对齐原版参数：
     - `--port` / `-p`、根目录位置参数 `root`、`--base-url`、`--base-dir`；
     - `--spa`、`--try-files <file>`；
     - `--autoIndex` / `-i` / `--no-autoIndex`（默认 true）、`--showDir` / `-d` / `--no-showDir`（默认 true）；
     - `--cache` / `-c <sec>`（支持数值与 max-age 格式）、`--cors`（跨域安全头）；
     - `--auth` / `-a <username:password>`（Basic Auth 凭证）；
     - `--log-ip` / `-l`、`--silent` / `-s`、`--help` / `-h`、`--version` / `-v`。
   - 参数解析严格映射到 `core.Config` 并保持参数名和类型健壮性。
2. R2: 监听前非法参数拦截与配置互斥预检 (Pre-flight Validation)
   - 在启动监听前严格拦截非法配置：无效端口号（超出 1-65535）、不存在的 root 目录、非法 base-url / base-dir 路径格式、以及互斥配置（如 `--spa` 与互斥路由组合）。
   - 发生配置错误时，向 stderr 输出友好错误提示并以非 0 状态退出，绝不进入 TCP 监听或泄露异常栈。
3. R3: 进程生命周期与优雅退出 (Graceful Lifecycle)
   - 接入跨平台/Windows Native 优雅中断信号捕获（Ctrl+C / SIGINT），在退出时安全关闭监听 Socket 并排空在途请求；
   - 杜绝资源与句柄残留，确保命令行可执行文件具备干净的启动与退出生命周期。
4. R4: 流程与提交约束 (Git Workflow)
   - **【核心流程约束】Milestone 5 代码实现完成后，必须先执行全部 `git add -A` 并创建本地 commit（例如 `feat: 实现 Milestone 5 完整 CLI 参数与生命周期`），严禁 push；确认成功后再交由 Reviewer 和 Auditor 审查；全量审查与门禁验证通过后，再次本地 commit 闭环！**
5. R5: 架构整洁度、0 Warnings 与开源协议合规
   - 保持全模块 `moon check --target native` 持续 0 错误、0 警告；
   - 规范更新各包 `.mbti` 接口定义，运行 `moon fmt`；
   - 执行开源依赖与源码引用许可证审计，严格限定为 MIT、Apache-2.0、BSD-3-Clause 等宽松商业友好协议。
6. 现有 83 项单元与集成测试持续 100% 通过，并为 CLI 增加单元与集成测试。

Please maintain `plan.md`, `progress.md`, and `BRIEFING.md` in your directory. Dispatch workers, reviewers, and challengers as needed. Report back when ready for victory audit.
</USER_REQUEST>

## 2026-09-11T17:49:21Z

【网络恢复与继续推进指令】
请继续推进 Milestone 5 的审查与门禁流程：
1. 推动各审查员 (reviewer_m5_1_gen2, reviewer_m5_2_gen2)、挑战者 (challenger_m5_1_gen2, challenger_m5_2_gen2) 及审计员 (auditor_m5_1_gen2) 完成判定并收集 handoff 报告；
2. 若发现任何缺陷及时安排 worker 修复；
3. 门禁全票通过后更新 .mbti / moon fmt，执行最终本地 commit（严禁 push），并向 Sentinel 报告 ready_for_victory_audit！

