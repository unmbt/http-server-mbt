## 2026-09-11T18:10:10Z

You are the Project Orchestrator for Milestone 6.

Your working directory is:
E:\project\moonbit\unmbt\http-server-mbt\.agents\orchestrator_m6

The authoritative user request is recorded in:
E:\project\moonbit\unmbt\http-server-mbt\.agents\ORIGINAL_REQUEST.md

Please carefully review the project rules in `AGENTS.md`, `docs/proposal.md`, `docs/design.md`, `docs/tasks.md`, `docs/progress.md`, and `docs/windows-baseline.md`.

## Mission & Requirements for Milestone 6:
1. 原版全量测试套件迁移 (C001～C042, CC-01～CC-28, CE-01～CE-02):
   - 对照 `docs/tasks.md` 逐例迁移矩阵，将 `http-server/test/` 核心测试逻辑移植到 MoonBit Native 测试集；
   - 覆盖条件缓存（304/ETag/IMS）、字节区间 Range（206/416）、预压缩协商（.br/.gz 候选探测）、MIME 类型识别与覆盖、目录索引与列表 HTML 渲染转义、安全策略（路径穿越防御、Basic Auth）、以及命令行配置映射；
   - 兼容 Windows 平台特性与限制（如 AD-05 Windows 特殊路径约束处理）。
2. 真实 HTTP 客户端端到端集成测试:
   - 通过真实 TCP Socket 客户端对运行中的服务发起请求与解析响应；
   - 验证 GET、HEAD、OPTIONS、keep-alive 及错误状态码交互，确保协议解析与响应调度端到端正确。
3. 状态机故障注入与异常并发对抗 (T-034):
   - 引入可重现的状态机故障注入场景：包含网络短写（Short Write）、慢速客户端读取（分段延时）、请求中途异常断连与在途取消；
   - 验证高并发请求及连接异常终止下服务器不挂起、不崩溃，且无 Socket/文件句柄泄漏（0 handle leaks）。
4. 【核心流程与 Git 约束】:
   - Milestone 6 代码实现完成后，必须先执行全部 `git add -A` 并创建本地 commit（例如 `feat: 实现 Milestone 6 原版测试迁移与故障注入测试`），严禁 push！
   - 确认本地 commit 成功后，再交由 Reviewer、Challenger 及 Auditor 开展独立的对抗性代码审查与门禁审计；
   - 全量门禁全票无条件通过后，更新 `.mbti`、运行 `moon fmt`、同步文档（`docs/tasks.md`, `docs/progress.md` 等），完成最终本地 commit（严禁 push），并在你的 working directory 写入 `handoff.md` 后向 Sentinel 汇报完成。
5. 架构整洁度与 0 Warnings 门禁:
   - `moon check --target native` 持续 0 错误、0 警告；
   - `moon test --target native` 100% 全部通过。

Please initialize your `plan.md`, `progress.md`, and `context.md`, dispatch workers/specialists, and orchestrate the full Milestone 6 process.

## 2026-09-11T18:33:01Z

【紧急指令同步：实现部分完成后 commit 后先停下来】

用户最新明确要求：“实现部分完成后commit后先停下来”。

请 Orchestrator 严格执行以下约束并同步给团队：
1. `worker_m6` 完成代码实现与全量测试验证（`moon check` 0 警告、`moon test` 100% 全部通过）后，执行全部 `git add -A` 并创建本地 commit（例如 `feat: 实现 Milestone 6 原版测试迁移与故障注入测试`，严禁 push！）；
2. 本地 commit 成功后，**必须立即暂停推进并停下来**，向 Sentinel 及用户汇报当前完成状态与 commit 哈希及详情；
3. **严禁自动派发或启动 Reviewer、Challenger 及 Auditor 审查阶段**；必须在此等待用户下一步明确指令后，方可进入审查流程！

请确认收到并更新你的 BRIEFING.md / plan.md。
