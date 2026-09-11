# Milestone 5 Execution Plan: CLI 完整性、生命周期与架构规范

## 1. 目标与范围
- **目标**: 为 `cmd/http-server-mbt` 提供原版对齐的完整命令行参数解析、启动监听前拦截非法配置、跨平台/Windows 优雅信号退出与许可证合规审计。
- **关联规范**:
  - 任务: `docs/tasks.md` (T-011)
  - 设计: `docs/design.md` (D-01, D-02, D-16, D-18)
  - 需求: `docs/proposal.md` (R-N01 ~ R-N16), `ORIGINAL_REQUEST.md` (Milestone 5 Follow-up)
  - 状态基线: `docs/progress.md`, `docs/windows-baseline.md`

## 2. 详细执行阶段

### Phase 1: 现状调研与架构分析 (Survey & Exploration)
- 调度 `teamwork_preview_explorer` 分析：
  1. `cmd/http-server-mbt/` 现有代码结构、参数解析现状及入口逻辑；
  2. `core/config.mbt` 中现有配置字段及需要补充或对齐的配置项；
  3. 现存信号捕获 / 优雅退出支持（MoonBit async / native 运行时或 Win32 控制台控制事件 `SetConsoleCtrlHandler`）；
  4. 现有测试套件结构（83 个测试）及如何为 CLI 添加单元/集成测试。

### Phase 2: Worker 实施 (Implementation & Local Verification)
- 调度 `teamwork_preview_worker` 实施：
  1. 完整命令行参数解析：
     - 端口与地址：`--port` / `-p`、根目录位置参数 `root`、`--base-url`、`--base-dir`
     - 路由与回退：`--spa`、`--try-files <file>`
     - 目录与索引：`--autoIndex` / `-i` / `--no-autoIndex`（默认 true）、`--showDir` / `-d` / `--no-showDir`（默认 true）
     - 缓存与头部：`--cache` / `-c <sec>`（支持数值与 max-age 格式）、`--cors`
     - 认证与安全：`--auth` / `-a <username:password>`
     - 日志与提示：`--log-ip` / `-l`、`--silent` / `-s`、`--help` / `-h`、`--version` / `-v`
  2. 监听前非法参数拦截与配置互斥预检 (Pre-flight Validation)：
     - 端口范围校验（1-65535）
     - root 目录存在性校验（不存在时拦截）
     - base-url / base-dir 格式归一化及校验
     - 互斥配置校验（如 `--spa` 与某些互斥路由）
     - 友好错误信息输出至 stderr 并以非 0 状态退出，禁止进入 TCP 监听
  3. 优雅退出与生命周期 (Graceful Lifecycle)：
     - Windows Native / 跨平台 Ctrl+C / SIGINT 信号监听
     - 退出时安全关闭监听 Socket 并等待在途请求排空，杜绝句柄泄漏
  4. 编译检查与自动化测试：
     - 执行 `moon check --target native`（严格 0 errors, 0 warnings）
     - 为 CLI 编写测试（参数解析单元测试、预检失败测试、端到端冒烟测试）
     - 确保现有 83 项测试持续 100% 通过
     - 更新 `.mbti` 并运行 `moon fmt`

### Phase 3: 核心流程门禁 - 本地 Commit 检查点 (Git Commit Gate)
- **硬性约束**：代码实现与自测通过后，Worker 执行 `git add -A` 并提交本地 commit（例如 `feat: 实现 Milestone 5 完整 CLI 参数与生命周期`）。
- **严格禁止 push**！
- 验证本地 commit 成功后，才进入 Phase 4。

### Phase 4: 多 Agent 审查与对抗测试 (Review & Challenge)
- 调度 2 名 Reviewer (`teamwork_preview_reviewer`) 独立审查：
  - 参数完整性、默认值一致性、类型安全性；
  - 错误处理与 stderr 友好性；
  - 0 警告、0 错误，代码风格与架构规范。
- 调度 2 名 Challenger (`teamwork_preview_challenger`) 对抗测试：
  - 极端边界参数（畸形端口、不存在的路径、特殊字符、空字符串、互斥参数组合）；
  - 优雅退出信号与资源释放验证；
  - 验证 83+ 测试持续 100% 通过。

### Phase 5: 真实性与许可证合规审计 (Forensic Integrity Audit)
- 调度 Forensic Auditor (`teamwork_preview_auditor`)：
  - 深度核查是否有硬编码参数、dummy 实现或伪造逻辑；
  - 核查开源协议合规性（所有引入代码和依赖严格属于 MIT, Apache-2.0, BSD-3-Clause 等商业友好协议）；
  - 一票否决权：若有 INTEGRITY VIOLATION，立刻回滚并重新修复。

### Phase 6: 文档同步与最终本地 Commit 闭环 (Closure)
- 更新 `docs/progress.md` 与相关文档；
- 执行最终本地 commit（`git add -A` + 本地 commit，严格禁止 push）；
- 汇总成果并向 Parent 报告。
