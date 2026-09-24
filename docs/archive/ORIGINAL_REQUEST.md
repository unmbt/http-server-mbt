> 历史快照：归档于 2026-09-25。内容与命令反映当时状态，不作为当前接口或验收结论；参见[当前文档](../README.md)和[路径迁移表](../repository-layout-20260925.md)。

# Original User Request

## 2026-09-11T06:42:31Z

完善 Windows Native 下原版 http-server 的全部功能与测试代码，补充 Windows TransmitFile/IOCP 零拷贝传输、BaseURL 挂载与 SPA/try-files 路由回退，重构优化目录与包架构并彻底消除所有编译器警告。开源依赖及代码引用严格限制为 MIT、Apache-2.0、BSD-3-Clause 等商业友好宽松协议。

Working directory: D:\project\moonbit\http-server-mbt
Integrity mode: benchmark

## References
- 规格设计与实施路线: `docs/proposal.md`, `docs/design.md`, `docs/tasks.md`
- 原版参考提交: `http-party/http-server` @ `0d3b7bb5b6e8a59fd450ae2dca65870009cfcd8b`
- 当前 Windows 状态基线: `docs/windows-baseline.md`

## Requirements

### R1. 原版 http-server 功能完整性与 Windows 兼容
- 实现完整 HTTP/1.1 请求解析与响应调度，支持 GET 与 HEAD 方法。
- 条件请求与缓存协商：支持 ETag、If-None-Match（强/弱比较）、If-Modified-Since、Cache-Control（数字、字符串及 max-age 格式）、304 Not Modified 响应（无正文）。
- Range 字节区间请求：支持 206 Partial Content、Content-Range 首部生成、无效/越界区间返回 416 Range Not Satisfiable，与条件请求正确组合。
- 预压缩内容协商：支持 Brotli (.br) 与 gzip (.gz) 预压缩候选检测、Accept-Encoding 协商与优先级选择、forceContentEncoding 与降级直出。
- MIME 类型与默认扩展名：提供标准 MIME 映射表、支持自定义 MIME 与 `.types` 文件解析、支持默认扩展名补全（如默认 `.html`）及 404 页面生成。
- 目录索引与列表渲染：支持目录 index 文件查找与重定向，提供美观、可配置列、带排序与路径安全转义的 HTML 目录列表视图。
- 安全策略与认证：严格拦截目录穿越与路径越界攻击，支持 HTTP Basic Auth（常量时间安全比较，认证错误先于文件探测），支持 CORS/COOP/PNA 安全头与 Host 白名单。
- CLI 与生命周期管理：提供完整的命令行参数解析（端口、root 目录、base-dir、日志开关、帮助与版本等），非法参数在监听前拦截报错，支持 Ctrl+C/信号优雅退出与资源清理。

### R2. 核心扩展：Windows 零拷贝传输、BaseURL 挂载与 SPA 路由
- Windows 内核级零拷贝传输：利用 Windows Native 下 `TransmitFile` / IOCP 机制传输静态明文文件与 Range 分段，避免用户态二次拷贝；具备健全的有界缓冲降级与断连取消处理，确保不泄漏文件句柄与 Socket 句柄。
- 路径前缀挂载（BaseURL）：支持 `--base-url` 及 `--base-dir` 路由前缀挂载，配置与请求 URL 路径严格归一化处理。
- SPA 与 try-files 路由回退：支持 `--spa`（未命中路由回退至根 `index.html`）与 `--try-files <file>` 回退；未命中兜底不吞掉认证错误与权限错误，与代理配置互斥校验。

### R3. 模块化易维护架构设计与零编译器警告（0 Warnings）
- 设计结构清晰、职责分离、高内聚低耦合的包与目录组织（解耦 core、engine、fs/io/zero-copy、server、cmd 等）。
- 彻底解决并消除当前代码中存在的全部 46 个编译器 Warning（包括但不限于：`redundant_modifier`、`unused_constructor`、`unused_package`、过时的 `deprecated` API、以及 `method`/`use` 等保留字命名），做到 0 warning、0 error。
- 遵循 MoonBit 习惯用法与代码风格，规范 `.mbti` 接口暴露。
- 严格遵循许可合规：涉及的代码或依赖仅允许使用 MIT、Apache-2.0、BSD-3-Clause 等商业友好开源协议。

### R4. 全面客观的测试套件迁移与验证
- 严格对照 `docs/tasks.md` 中的逐例迁移矩阵（C001～C042 及 CC-01～CC-28、CE-01～CE-02 等），建立基于 MoonBit Native 的单元测试与集成测试。
- 覆盖空文件、常规静态资源、大文件传输、并发请求、断开连接、异常路径等场景，确立可重复、客观验证的测试防线。

## Acceptance Criteria

### 编译与代码质量
- [ ] 执行 `moon check --target native`，输出结果为 0 错误（0 errors）且 0 警告（0 warnings）。
- [ ] 执行 `moon info --target native` 与 `moon fmt`，正确生成/更新各模块 `.mbti` 接口文件，且保持规范的代码格式。
- [ ] 架构结构清晰，各子包职责明确，不存在循环依赖或未暴露关键接口的问题。

### 功能与行为验证
- [ ] 执行 `moon test --target native`，全部迁移测试与新增测试均顺利通过。
- [ ] 条件请求（304）、Range（206/416）、预压缩选择、MIME 识别、目录列表与 Basic Auth 单元测试全部通过。
- [ ] BaseURL 前缀匹配与 SPA / try-files 回退机制经自动化测试验证，边界与异常情况处理准确。
- [ ] 编译生成 Release CLI 可执行文件，命令行启动、参数解析、非法端口阻断与平滑退出功能通过冒烟验证。
- [ ] Windows TransmitFile 传输正常工作，并在客户端异常中断或大量传输后无文件/Socket 句柄泄漏。

## Follow-up — 2026-09-11T12:27:00Z

接续 `docs/progress.md` 进度，全面完成 Milestone 3 的代码审查、对抗测试与门禁修复，并实现 Milestone 4 的 Windows Native TransmitFile 与 IOCP 零拷贝静态传输与 Range 支持。

Working directory: E:\project\moonbit\unmbt\http-server-mbt
Integrity mode: benchmark
Requested team: Full multi-agent team

## References
- 规格设计与实施契约: `docs/proposal.md`, `docs/design.md`, `docs/tasks.md`
- 阶段进度说明: `docs/progress.md`
- 当前 Windows 基线: `docs/windows-baseline.md`
- 架构规则: `AGENTS.md` (遵守 SDD 流程、0 Warning 原则、资源安全与所有权规范)

## Requirements

### R1. Milestone 3 审查、检测与对抗加固 (Review & Hardening)
- 对 Milestone 3 已完成的 Engine 业务特性（HTTP/1.1 GET/HEAD 分发、.br/.gz 预压缩协商、HTML 目录列表渲染、SPA/try-files 优雅回退、D-17 文件变更检测）进行全面代码审查与对抗测试。
- 修复当前测试套件中暴露的问题（包括但不限于 `engine_test.mbt` 中 `directory listing vs custom 404 precedence (C016)`，以及 `engine_security_directory_adversarial_test.mbt` 中 `Terminal 404 when fallback file does not exist`）。
- 确保静态目录探测、索引回退、404/403/401 优先级逻辑完全符合 RFC 与 `docs/design.md` 契约，杜绝任何硬编码或伪造实现。

### R2. Milestone 4 Windows Native TransmitFile 与 IOCP 零拷贝传输 (T-031)
- 在 Windows Native 下实现基于 Win32 `TransmitFile` / Overlapped 异步 I/O 的静态文件与 Range 分段内核级零拷贝发送。
- 对接 `engine.mbt` 与 `core/` 中的 `FileRegion(path, offset, length)`，避免用户态大文件缓冲与多次内存拷贝。
- 具备健全的有界缓冲降级机制（对于非文件响应、小数据块或特定平台回退路径）。
- 实现慢客户端与断连取消处理，确保在连接异常中断、客户端主动关闭或高并发传输下绝不泄漏文件句柄与 Socket 句柄。

### R3. 编译整洁度、接口生成与规范审计
- 严格遵循 MoonBit 习惯用法与架构规范，保持全模块 `moon check --target native` 持续 0 错误、0 警告。
- 保证 `moon info --target native` 正确生成/更新各包 `.mbti` 接口描述文件，并通过 `moon fmt` 保持代码风格规范。
- 引用依赖与实现代码严格遵循 MIT、Apache-2.0、BSD-3-Clause 等宽松商业友好开源协议。

## Acceptance Criteria

### 编译与类型检查
- [ ] `moon check --target native` 输出结果为 0 错误（0 errors）、0 警告（0 warnings）。
- [ ] `moon info --target native` 成功更新 `.mbti` 接口，`moon fmt` 格式化无异常差异。

### 行为与测试验证
- [ ] `moon test --target native` 全量单元与对抗测试 100% 通过（无任何失败用例）。
- [ ] 修复 C016 目录列表与自定义 404 优先级逻辑，修复 SPA/try-files 在回退文件不存在时的终端 404 判定。
- [ ] 针对 Windows Native TransmitFile / IOCP 零拷贝与 Range 区间发送，编写并执行端到端或集成测试，验证普通文件、大文件及 Range 切片正确传输。
- [ ] 验证异常断连与慢速传输场景下无文件句柄泄漏（handle leak）和 Socket 泄漏。

## Follow-up — 2026-09-11T12:39:43Z

Milestone 3 的审查、测试修复与门禁验证通过后，在开始执行 Milestone 4 之前：
必须先执行全部 `git add -A` 并创建本地 commit（例如 `git commit -m "feat: 完成 Milestone 3 审查修复与门禁验证"`），但【绝对不要 push】！
确认本地 commit 完成后，再启动 Milestone 4 的实施。请立即同步通知 Orchestrator 并在流程规划中执行此约束。

## Follow-up — 2026-09-11T12:50:10Z

Milestone 4 代码实现完成后，同样先执行全部 `git add -A` 并提交本地 commit（例如 `git commit -m "feat: 实现 Milestone 4 Windows TransmitFile 零拷贝传输"`），严禁 push；在本地 commit 完成后，再交由审查员（Reviewer）和审计员（Auditor）继续进行审查与门禁验证。
请立即通知 Orchestrator 及 worker_m4，将该 commit 节点落实到位。

## Follow-up — 2026-09-11T14:24:38Z

由于服务端重启，继续唤醒并调度团队完成 Milestone 4：

1. 当前状态：
   - Milestone 4 代码实现已完成并已本地 commit：`e4e06fa feat: 实现 Milestone 4 Windows TransmitFile 零拷贝传输`（严格未 push）；
   - 进入门禁审查阶段后，Challenger 编写了 `server/server_challenger_test.mbt`；
   - 当前 `moon test --target native` 结果显示：80 个测试中 79 个通过，1 个失败（`server/server_test.mbt:234 ("server zero handle leaks across repeated requests")` 处断言失败）；

2. 待完成工作：
   - 调度团队定位并修复该句柄泄漏/断言失败问题，确保 `moon check`（0 errors, 0 warnings）与 `moon test` 100% 全部通过；
   - 推动 Reviewer、Challenger、Auditor 完成无条件通过裁决（APPROVE / CLEAN）；
   - 更新文档与接口定义（`moon info`、`moon fmt`），完成 M4 闭环并执行本地 commit（严格禁止 push）！

## Follow-up — 2026-09-11T15:23:34Z

<USER_REQUEST>
实现 Milestone 5（CLI 完整性、生命周期与架构规范）：为 `cmd/http-server-mbt` 提供原版对齐的完整命令行参数解析、监听前拦截非法配置、优雅信号退出与许可证合规审计。

Working directory: E:\project\moonbit\unmbt\http-server-mbt
Integrity mode: benchmark
Requested team: Full multi-agent team

## References
- 规格设计与实施契约: `docs/proposal.md`, `docs/design.md`, `docs/tasks.md` (重点参考 T-011)
- 阶段进度说明: `docs/progress.md`
- 当前 Windows 基线: `docs/windows-baseline.md`
- 架构规则: `AGENTS.md` (遵守 SDD 流程、0 Warning 原则、资源安全与所有权规范)

## Requirements

### R1. 完整命令行参数解析与配置映射 (CLI Feature Parity)
- 完善 `cmd/http-server-mbt` 命令行参数体系，全面支持并对齐原版参数：
  - 基础网络与路径：`--port` / `-p`、根目录位置参数 `root`、`--base-url`、`--base-dir`；
  - 路由与回退：`--spa`、`--try-files <file>`；
  - 目录与索引：`--autoIndex` / `-i` / `--no-autoIndex`（默认 true）、`--showDir` / `-d` / `--no-showDir`（默认 true）；
  - 缓存与头部：`--cache` / `-c <sec>`（支持数值与 max-age 格式）、`--cors`（跨域安全头）；
  - 认证与安全：`--auth` / `-a <username:password>`（Basic Auth 凭证）；
  - 日志与提示：`--log-ip` / `-l`、`--silent` / `-s`、`--help` / `-h`、`--version` / `-v`。
- 参数解析严格映射到 `core.Config` 并保持参数名和类型健壮性。

### R2. 监听前非法参数拦截与配置互斥预检 (Pre-flight Validation)
- 在启动监听前严格拦截非法配置：无效端口号（超出 1-65535）、不存在的 root 目录、非法 base-url / base-dir 路径格式、以及互斥配置（如 `--spa` 与互斥路由组合）。
- 发生配置错误时，向 stderr 输出友好错误提示并以非 0 状态退出，绝不进入 TCP 监听或泄露异常栈。

### R3. 进程生命周期与优雅退出 (Graceful Lifecycle)
- 接入跨平台/Windows Native 优雅中断信号捕获（Ctrl+C / SIGINT），在退出时安全关闭监听 Socket 并排空在途请求；
- 杜绝资源与句柄残留，确保命令行可执行文件具备干净的启动与退出生命周期。

### R4. 流程与提交约束 (Git Workflow)
- **【核心流程约束】Milestone 5 代码实现完成后，必须先执行全部 `git add -A` 并创建本地 commit（例如 `feat: 实现 Milestone 5 完整 CLI 参数与生命周期`），严禁 push；确认成功后再交由 Reviewer 和 Auditor 审查；全量审查与门禁验证通过后，再次本地 commit 闭环！**

### R5. 架构整洁度、0 Warnings 与开源协议合规
- 保持全模块 `moon check --target native` 持续 **0 错误、0 警告**；
- 规范更新各包 `.mbti` 接口定义，运行 `moon fmt`；
- 执行开源依赖与源码引用许可证审计，严格限定为 MIT、Apache-2.0、BSD-3-Clause 等宽松商业友好协议。

## Acceptance Criteria

### 编译与接口
- [ ] `moon check --target native` 输出结果为 0 错误、0 警告。
- [ ] `moon info --target native` 规范生成 `.mbti`，`moon fmt` 格式化无异常差异。

### CLI 功能与测试验证
- [ ] 编译生成 Release CLI 可执行文件，通过端到端命令行启动冒烟测试。
- [ ] 参数解析覆盖完整矩阵（`--port`, `root`, `--base-url`, `--base-dir`, `--spa`, `--try-files`, `--autoIndex`, `--showDir`, `--cache`, `--cors`, `--auth`, `--silent` 等）。
- [ ] 非法参数（如非法端口、非法路径）在监听前精准阻断并给出清晰错误提示，非 0 退出。
- [ ] 命令行优雅响应 Ctrl+C 中断信号，退出时释放所有资源与套接字。
- [ ] 现有 83 项单元与集成测试持续 100% 通过，并为 CLI 增加单元与集成测试。
</USER_REQUEST>

## Follow-up — 2026-09-11T17:48:31Z

【网络恢复与继续推进指令】
由于底层 API 连接中断后恢复，请继续推进 Milestone 5 的审查与门禁流程：

1. 当前状态：
   - Worker 已完成核心参数解析与生命周期实现，全量测试 99/99 全部通过，0 错误、0 警告；
   - 本地 Git commit 已就绪：`178bb57 feat: 实现 Milestone 5 完整 CLI 参数与生命周期`（严格未 push）；
   - 审查群组已派发（reviewer_m5_1, reviewer_m5_2, challenger_m5_1, challenger_m5_2, auditor_m5_1）。

2. 后续任务：
   - 推动各审查员、挑战者及审计员完成审查判定，收集 handoff 报告；
   - 若发现任何缺陷及时修复；
   - 门禁全票通过后更新 `.mbti`/`moon fmt`，执行最终本地 commit（严禁 push），并交由 Victory Auditor 进行终审闭环！

## Follow-up — 2026-09-11T18:09:08Z

<USER_REQUEST>
推进 Milestone 6（原版全量测试套件迁移与对抗加固）：对照 docs/tasks.md 逐例迁移矩阵（C001～C042 及 CC-01～CC-28、CE-01～CE-02），补充真实 HTTP 客户端端到端测试与状态机故障注入（T-034）；实现阶段完成后先执行 git add 与本地 commit（严禁 push），再进入审查员（Reviewer）、挑战者（Challenger）与审计员（Auditor）的多阶段对抗审查与终审闭环。

Working directory: E:\project\moonbit\unmbt\http-server-mbt
Integrity mode: benchmark

## References
- 规格契约与实施任务: `docs/proposal.md`, `docs/design.md`, `docs/tasks.md`
- 阶段进度与接续指南: `docs/progress.md`
- 历史基线与执行证据: `docs/windows-baseline.md`
- 团队架构规则: `AGENTS.md` (SDD 流程、0 警告门禁、所有权安全)

## Requirements

### R1. 原版全量测试套件迁移 (C001～C042, CC-01～CC-28, CE-01～CE-02)
- 对照 `docs/tasks.md` 逐例迁移矩阵，将 `http-server/test/` 核心测试逻辑移植到 MoonBit Native 测试集；
- 覆盖条件缓存（304/ETag/IMS）、字节区间 Range（206/416）、预压缩协商（.br/.gz 候选探测）、MIME 类型识别与覆盖、目录索引与列表 HTML 渲染转义、安全策略（路径穿越防御、Basic Auth）、以及命令行配置映射；
- 兼容 Windows 平台特性与限制（如 AD-05 Windows 特殊路径约束处理）。

### R2. 真实 HTTP 客户端端到端集成测试
- 通过真实 TCP Socket 客户端对运行中的服务发起请求与解析响应；
- 验证 GET、HEAD、OPTIONS、keep-alive 及错误状态码交互，确保协议解析与响应调度端到端正确。

### R3. 状态机故障注入与异常并发对抗 (T-034)
- 引入可重现的状态机故障注入场景：包含网络短写（Short Write）、慢速客户端读取（分段延时）、请求中途异常断连与在途取消；
- 验证高并发请求及连接异常终止下服务器不挂起、不崩溃，且无 Socket/文件句柄泄漏（0 handle leaks）。

### R4. 流程与提交约束 (Git Workflow)
- **【核心流程约束】Milestone 6 代码实现部分完成后，必须先执行全部 `git add -A` 并创建本地 commit（例如 `feat: 实现 Milestone 6 原版测试迁移与故障注入测试`），严禁 push！**
- 确认本地 commit 成功后，再交由 Reviewer、Challenger 及 Auditor 开展独立的对抗性代码审查与门禁审计；
- 全量门禁全票无条件通过后，更新 `.mbti`、运行 `moon fmt`、同步文档，完成最终本地 commit（严禁 push），并交由 Victory Auditor 进行归档终审。

### R5. 架构整洁度与 0 Warnings 门禁
- 保持全模块 `moon check --target native` 持续 **0 错误、0 警告**；
- 生成规范的 `.mbti` 接口描述文件并通过 `moon fmt` 保持代码风格一致；
- 开源依赖及代码引用严格限定为 MIT、Apache-2.0、BSD-3-Clause 等宽松商业友好协议。

## Acceptance Criteria

### 编译与接口门禁
- [ ] `moon check --target native` 检查结果为 0 错误（0 errors）、0 警告（0 warnings）。
- [ ] `moon info --target native` 与 `moon fmt` 规范执行，接口描述与格式无异常差异。

### 行为与测试门禁
- [ ] 原版测试迁移（C001～C042 及 CC/CE 矩阵）在 Native 下建立完整断言并 100% 通过。
- [ ] 状态机故障注入测试（短写、慢速读取、断连取消）100% 通过且无句柄泄漏。
- [ ] `moon test --target native` 全量测试套件通过率保持 100%（全 PASS、0 FAIL）。

### 提交流程与审查门禁
- [ ] 实现完成后第一阶段先且必须执行本地 commit（`git add -A` && `git commit`），严禁 push。
- [ ] Reviewer、Challenger、Auditor 独立门禁全票通过并出具 handoff 报告。
- [ ] 门禁全通后完成文档更新并记录最终本地 commit（严禁 push）。
</USER_REQUEST>

## Follow-up — 2026-09-11T18:32:31Z

<USER_REQUEST>
实现部分完成后commit后先停下来
</USER_REQUEST>

【执行约束】：
Worker 完成实现与自测（`moon check` 0 警告、`moon test` 100% 通过）并执行完 `git add -A` 和本地 commit（严禁 push）之后，必须立即暂停流程并向用户汇报停下来，暂不启动后续审查阶段，静候用户下一步确认。

## Follow-up — 2026-09-12T01:58:20Z

<USER_REQUEST>
全面复核 Milestone 6（原版全量测试套件迁移与状态机故障注入）的实现与测试覆盖情况，确认无遗漏后依序推进代码审查（Reviewer）、对抗测试挑战（Challenger）、合规与资源审计（Auditor），并完成门禁全通闭环与独立 Victory Audit 终审归档。

Working directory: E:\project\moonbit\unmbt\http-server-mbt
Integrity mode: benchmark
Requested team: Full multi-agent team

## References
- 规格契约与实施任务: `docs/proposal.md`, `docs/design.md`, `docs/tasks.md`
- 阶段进度与接续指南: `docs/progress.md`
- 原版参考仓库: `http-server/` (commit `0d3b7bb5b6e8a59fd450ae2dca65870009cfcd8b`)
- 团队架构规则: `AGENTS.md` (遵守 SDD 流程、0 警告门禁、所有权安全、禁止 push)

## Requirements

### R1. M6 实现与测试用例迁移完整性复核
- 审查并核对原版 42 个测试文件（C001～C042）、28 项公共用例（CC-01～CC-28）、2 项错误用例（CE-01～CE-02）在 MoonBit Native 中的落地；
- 核验 `server/c_suite_*.mbt`、`server/server_e2e_client_test.mbt`、`server/server_fault_injection_test.mbt` 的断言语义与原版行为的一致性；
- 若发现任何尚未迁移或存在语义偏差的用例，立即补齐并确保 100% 通过。

### R2. 审查员（Reviewer）质量与契约审查
- 对照 `docs/design.md`（D-01～D-18）与 `docs/tasks.md` 逐项核对行为契约；
- 特别验证 AD-01～AD-10 差异记录与平台约束（如 AD-05 Windows 特殊路径约束、AD-03 超时单位、AD-07 WebSocket 启动校验等）；
- 出具详细审查报告（Handoff Report），指出需改进之处或给出通过判定。

### R3. 挑战者（Challenger）对抗测试与压力加固
- 编写专项对抗性测试集（如 `server/server_challenger_m6_test.mbt`）；
- 针对极端场景展开攻击性测试：单字节流式短写、报头截断断连、慢速客户端反压（Slowloris 式读取延时）、并发突发连接、在途请求取消排空；
- 结合 Win32 `GetProcessHandleCount` 强断言验证多次往返与并发异常断连下 0 句柄泄漏（0 handle leaks）。

### R4. 审计员（Auditor）合规与资源审计
- 审计编译状态：全包 `moon check --target native` 保持绝对 **0 错误、0 警告**；
- 审计开源许可证合规：全量源码、测试用例与 testdata 静态资产均遵循 MIT / Apache-2.0 / BSD-3-Clause 等商业友好宽松协议，无 GPL/AGPL 污染；
- 审查资源安全性与内存/句柄所有权生命周期。

### R5. 门禁闭环、文档同步与独立 Victory Audit 终审归档
- 在各门禁全票无条件通过后，更新并校验公开接口文件（`moon info --target native`）与代码格式化（`moon fmt`）；
- 同步更新 `docs/progress.md` 与 `docs/tasks.md` 中 Milestone 6 任务状态与实测证据；
- 执行本地提交（`feat: 完成 Milestone 6 审查门禁闭环与文档同步`，严禁 push）；
- 派发独立 Victory Auditor 开展最终完整性核验，生成归档报告并执行最终本地归档提交（`docs: 归档 Milestone 6 独立 Victory Audit 终审记录`，严禁 push）。

## Acceptance Criteria

### 编译与质量门禁
- [ ] `moon check --target native` 输出结果保持 0 errors, 0 warnings。
- [ ] `moon info --target native` 与 `moon fmt` 执行无接口破坏与格式差异。

### 测试与行为门禁
- [ ] 原版迁移用例矩阵（C001～C042, CC-01～CC-28, CE-01～CE-02）100% 覆盖并断言无误。
- [ ] 真实 TCP Socket E2E 与状态机故障注入测试 100% 通过。
- [ ] 对抗测试（Challenger）覆盖慢速反压与并发异常中断，且实测句柄差值为 0（0 handle leaks）。
- [ ] `moon test --target native` 全量测试通过率保持 100%（全 PASS、0 FAIL）。

### 审查与审计门禁
- [ ] Reviewer、Challenger、Auditor 各自独立出具 Handoff 报告并通过门禁判定。
- [ ] 严格遵守 Git 本地提交规范，全过程严禁执行 `git push`。
</USER_REQUEST>

## Follow-up — 2026-09-12T02:48:51Z

<USER_REQUEST>
继续完成m6的门禁、审查、挑战、审计等
</USER_REQUEST>

## Follow-up — 2026-09-12T10:37:00Z

<USER_REQUEST>
由独立的多 Agent 团队对当前仓库中 Milestone 6（原版全量测试套件迁移、真实 TCP Socket E2E、T-034 状态机故障注入、C040 WebSocket 异步双向代理与生命周期管理）的全部实现代码与测试套件进行严格的多角色独立审查（Reviewers）、对抗测试挑战（Challengers）与合规取证审计（Auditors），杜绝单 Agent 自审自鉴，出具独立客观的门禁裁决与终审归档。

Working directory: E:\project\moonbit\unmbt\http-server-mbt
Integrity mode: benchmark

## References
- 规格契约与实施任务: `docs/proposal.md`, `docs/design.md`, `docs/tasks.md`
- 阶段进度与接续指南: `docs/progress.md`
- 原版参考仓库: `http-server/` (commit `0d3b7bb5b6e8a59fd450ae2dca65870009cfcd8b`)
- 团队规则与规范: `AGENTS.md` (严格遵守 SDD 规范、0 警告门禁、Native FFI 所有权安全、严格本地 Git 提交、严禁执行 git push)

## Requirements

### R1. 多角色独立代码与契约审查（Reviewers）
- 审查员必须独立审查 `core/`、`server/`（含 `server.mbt`、`transmit_file.mbt`、`transmit_file_windows.c`）以及原版 42 组测试用例的落地情况（`server/c_suite_*.mbt`）；
- 严格对照 `docs/design.md`（D-01～D-18）与 `docs/tasks.md` 逐条核实契约实现，重点审查：
  - C034 空闲超时断连（`.04` 真实 1000ms 空闲断连与 AD-03 规范）；
  - C040 WebSocket 双向代理生命周期（`.01～.04` 协议级关闭帧、握手升级与错误隔离，杜绝 IOCP 读阻塞死锁）；
  - AD-05 纯 HTML `<dir>` 实体转义跨平台测试；
- 独立出具审查报告（Handoff Report），附带详实代码行级证据与明确裁决（`APPROVE` / `REQUEST_CHANGES`）。

### R2. 独立对抗性压力与边缘挑战（Challengers）
- 挑战者独立设计并执行攻击性对抗测试套件（如 `server_challenger_m6_test.mbt` 与 `server_challenger_m6_edge_test.mbt`）；
- 验证极端场景的系统韧性：
  - 单字节分片短写与畸形报头截断风暴；
  - Slowloris 慢读反压与 `TransmitFile` Overlapped I/O 缓冲区阻塞；
  - 高并发突发并发连接与在途请求排空（`stop_and_drain` 屏障同步）；
  - 极端 Range 边界攻击（32 组边界测试）；
  - 基于 Win32 `GetProcessHandleCount` 验证跨周期多轮压测下 0 句柄单调泄漏；
- 独立出具挑战者报告，若发现挂起、死锁或泄漏立即提出阻断。

### R3. 独立法医式合规与资源审计（Forensic Auditor）
- 审计编译与类型安全：执行 `moon check --target native`，全仓必须保持绝对 **0 错误、0 警告**；
- 审计测试执行：独立运行全量测试套件（`moon test --target native`），确认 169 项测试通过率必须保持 **100%（全 PASS、0 FAIL）**；
- 审计开源许可合规：审查全量代码、依赖（`moonbitlang/async` Apache-2.0）与静态资产，确认全量属于 MIT/Apache-2.0 商业宽松许可，严禁 GPL/AGPL 限制性代码污染；
- 审计反作弊与实现真伪（Benchmark Mode）：核查全量实现是否真实，杜绝硬编码测试预期、桩函数或伪造通过；
- 出具法医式审计报告与裁决。

### R4. 独立 Victory Audit 终审与本地归档
- 在审查员、挑战者、审计员全票无条件通过后，执行 `moon info --target native` 与 `moon fmt` 接口及格式校验；
- 核验本地 Git 提交合规性，严格确认当前工作区干净且**绝无任何 `git push` 行为**；
- 独立 Victory Auditor 出具终审报告并完成本地归档记录。

## Acceptance Criteria

### 编译与静态质量门禁
- [ ] `moon check --target native` 输出结果保持 0 errors, 0 warnings。
- [ ] `moon info --target native` 接口一致，`moon fmt` 格式化无差异。

### 测试执行与行为门禁
- [ ] 原版迁移用例矩阵（C001～C042、CC-01～CC-28、CE-01～CE-02）全部覆盖并断言无误。
- [ ] `server/server_e2e_client_test.mbt` 真实 TCP 握手与 HTTP Wire-level 报文解析测试 100% 通过。
- [ ] `server/server_fault_injection_test.mbt` 状态机故障注入测试 100% 通过，无挂起与死锁。
- [ ] 两组 Challenger 对抗套件全部通过，Win32 `GetProcessHandleCount` 验证 0 句柄泄漏。
- [ ] `moon test --target native` 全仓 169 项测试通过率保持 100%（全 PASS、0 FAIL）。

### 审查与归档门禁
- [ ] Reviewers、Challengers、Forensic Auditor 各自独立出具 Handoff 报告并全票给出通过判定。
- [ ] 全过程严格本地 Git 提交，严禁执行 `git push`。
- [ ] 独立 Victory Auditor 完成终审归档报告。
</USER_REQUEST>

## 2026-09-18T12:00:00Z

# Teamwork Project Prompt — Draft

> Status: Launched
> Goal: Craft prompt → get user approval → delegate to teamwork_preview
> Requested team: 全功能多智能体团队（Full team）

在 MoonBit 项目 `http-server-mbt` 中设计并实现 `thin` 与 `full` 双版本分层打包机制（涵盖 CLI、C ABI 动态库与静态库导出），其中 `thin` 版本解耦 `tls` 及其 MbedTLS C 桩代码，保持轻量高效与零加密依赖；`full` 版本集成当前分支已实现的 MbedTLS TLS 功能，并完成反向代理（Proxy）功能的架构设计与接口就绪，为下一步全面支持原版 `http-server` 代理特性奠定基础。

Working directory: E:/project/moonbit/unmbt/http-server-mbt
Integrity mode: development

## Requirements

### R1. 核心包解耦与传输抽象（Decouple Server from TLS）
重构 `server` 与 `core` 的依赖拓扑，剥离对 `unmbt/http-server-mbt/tls` 的硬依赖。
- 引入传输层/连接处理抽象（如 `Acceptor` 或连接生命周期处理回调），使基础静态 HTTP 服务器不直接引用 `tls` 包及其底层 100 余个 MbedTLS C 源文件。
- `thin` 版本纯粹基于静态文件服务依赖构建；`full` 版本通过依赖注入接入 TLS 传输层，并预留代理（Proxy）拦截点。
- 保持项目既有全部 183 项测试（C001～C042 原版迁移、TLS 回环测试等）零回归。

### R2. 双版本 CLI 构建与分发（Thin & Full CLI）
建立 `thin` 与 `full` 两种构建形态的 CLI 体系：
- `thin` CLI：精简构建，仅包含静态 HTTP、Range、缓存、预压缩、SPA/try-files、目录列表与 Basic Auth 等主线功能。遇到 `--cert`、`--key`、`--proxy` 等参数时，必须输出明确错误提示并以状态码 1 退出，禁止静默忽略（符合 D-08 / D-15 规范）。
- `full` CLI：完整构建，包含全部基础功能以及 TLS（`--cert`、`--key`、`--key-passphrase`）及后续代理参数。
- 支持通过构建脚本或独立包入口构建出独立的 `thin` 与 `full` 可执行文件。

### R3. C ABI 动静态库双版本导出流水线（C ABI Export Pipeline）
依据 D-07 与 D-11 的 `hs_*` 托管异步 C ABI 规范：
- 提供基于 `.mbtx` 脚本驱动的自动化构建工具链，支持导出 C 头文件及对应产物。
- 分别导出 `thin` 与 `full` 版本的动态库（Windows `.dll`、Linux `.so`、macOS `.dylib`）与静态库（Windows `.lib`、Linux/macOS `.a`）。
- 导出的库不得包含 CLI main 入口，隐藏内部符号，导出符号严格限定为 `hs_*` API。
- `thin` 版本的动态/静态库不携带任何 MbedTLS 符号与对象，实现极端体积优化与无 C 加密依赖。

### R4. 反向代理（Proxy）架构设计与接口就绪
为下一步实现原版 `http-server` 的反向代理功能完成架构设计与接口准备：
- 深入对齐原版代理规范（测试 C037~C039、C041，以及任务 T-013）：包括 `--proxy`（静态未命中兜底）、`--proxy-all`（全量直通）、`--proxy-config`（路径重写规则）与 `proxyOptions`（HTTPS 上游跳过校验等）。
- 在文档或架构规范中完成 Proxy 请求流转状态机（Resolving -> Proxying -> Idle）、配置数据结构与流式转发接口设计，确保与 R1 的传输抽象无缝协同。

## Acceptance Criteria

### 依赖隔离与编译验证
- [ ] 运行构建脚本或编译命令验证：`thin` 版本编译过程中完全不参与编译 `tls` 包及其 MbedTLS C 桩代码，产物体积显著小于 `full` 版本。
- [ ] `moon check --target native` 在所有改动包上保持 0 错误。
- [ ] `moon test --target native` 全量通过（既有 183 项测试零回归）。

### CLI 行为与参数校验
- [ ] `thin` CLI 独立执行验证：正常提供静态文件与 SPA 服务；传入 `--cert` 或 `--proxy` 时报错退出（exit code 1），提示当前构建不支持该功能。
- [ ] `full` CLI 独立执行验证：正常加载证书并支持真实 HTTPS 请求与 TLS 1.3/1.2 协商。

### C ABI 动静态库导出
- [ ] 运行自动化构建脚本，能成功在 Windows 本机生成 `thin` 和 `full` 的动态库（`.dll`）与静态库（`.lib`）。
- [ ] 导出产物经符号检查确认具备 `hs_abi_version` 等 `hs_*` 接口，无 `main` 符号污染。
- [ ] 提供最小 C 调用验证程序，成功链接动态库/静态库并完成初始化与 ABI 版本查询。

### 规范文档与 Proxy 设计
- [ ] 更新 `docs/design.md`、`docs/tasks.md` 或输出专项 ADR，清晰记录 thin/full 解耦设计决策与 Proxy 架构接入方案。

## Follow-up — 2026-09-18T12:30:50Z

<USER_REQUEST>
继续做完当前的cli部分min/full打包，但是准备开始做动态库静态库导出前记录已完成的工作内容后停下来，以便后面能根据记录的文档继续完成动静态库导出的实现
</USER_REQUEST>

【阶段目标与执行边界调整】：
1. 目标范围：
   - 聚焦完成 Milestone 1（核心包架构解耦：server 与 tls 解耦，传输层抽象）与 Milestone 2（Thin 与 Full 双版本 CLI 构建、参数校验与隔离、全量 183 项既有测试及新增 CLI 测试保障）。
   - 完成 Proxy 的架构设计与接口预留文档梳理。
2. 【关键暂停点（PAUSE / STOP）】：
   - 在完成 CLI 部分的 thin/full 构建、测试及验证后，在准备开始做 Milestone 3（动态库与静态库导出流水线）之前，必须：
     a. 详细记录已完成的工作内容（包括包拓扑变更、CLI 产物差异、编译与测试验证数据）；
     b. 整理动静态库导出的后续接续方案与指引文档；
      c. 立即停下来（PAUSE / STOP），向用户汇报已完成的工作与接续文档位置，暂不启动动静态库导出的实际编码与构建！





## Follow-up — 2026-09-18T13:08:02Z

<USER_REQUEST>
# Teamwork Project Prompt — Draft

> Status: Launched
> Goal: Craft prompt → get user approval → delegate to teamwork_preview
> Requested team: 全功能多智能体团队（Full team）

基于已完成的架构解耦与 CLI 双版本打包基础（详见 `docs/cli-thin-full-and-cabi-handover.md`），在 MoonBit 项目 `http-server-mbt` 中设计并实现 `thin` 与 `full` 双版本 C ABI 动静态库导出流水线，包括纯净 `hs_*` 符号导出控制、`.mbtx` 驱动的动静态库构建脚本、以及独立的 C 语言消费程序验证。

Working directory: E:/project/moonbit/unmbt/http-server-mbt
Integrity mode: development

## References
- 规格契约与设计文档: `docs/design.md` (D-07, D-11), `docs/tasks.md` (T-020, T-027)
- 接续交接指南: `docs/cli-thin-full-and-cabi-handover.md`

## Requirements

### R1. C ABI 桥接层与符号纯洁性（C ABI Interface & Symbol Isolation）
依据 D-07 与 D-11 的 `hs_*` 托管异步 C ABI 规范：
- 创建 C 桥接包，导出纯 C 头文件（`http_server.h`）与 `hs_*` 接口（`hs_abi_version`, `hs_server_start`, `hs_server_stop`, `hs_error_copy` 等），不暴露 MoonBit 托管对象或内部 runtime 布局。
- 分别支持 `thin`（纯静态 HTTP 服务器，零加密 C 依赖）与 `full`（集成 TLS 传输层与代理能力）两组导出实现。
- 建立导出符号隔离控制机制（Windows 使用 `.def` 文件或显式导出标记）：确保动态库与静态库中严禁包含 CLI `main` 入口符号，严禁泄露未授权内部符号；`thin` 库中绝对不包含任何 MbedTLS / PSA-Crypto 符号。

### R2. 纯 `.mbtx` 驱动的动静态库构建流水线（Build Pipeline）
编写自动化构建驱动脚本（`scripts/build_cabi.mbtx`），驱动本地编译器与归档器（如 clang / cl / lib.exe / llvm-ar）：
- 自动化完成 MoonBit 对象文件编译生成与中间目录解析。
- 构建导出 `thin` 版本的动态库（Windows `hs_thin.dll` + `hs_thin.lib`）与静态库（Windows `hs_thin_static.lib`）。
- 构建导出 `full` 版本的动态库（Windows `hs_full.dll` + `hs_full.lib`）与静态库（Windows `hs_full_static.lib`）。
- 产物输出至固定发行目录（如 `target/cabi/`），并提供清晰的构建日志与产物清单。

### R3. 独立 C 语言消费者编译与运行验证（C Consumer Smoke Tests）
在 `testdata/c_consumer/` 创建独立的 C 测试程序：
- 编写独立的 C 代码，分别通过动态链接（引用 `hs_thin.lib` / 加载 `hs_thin.dll`）与静态链接（引用 `hs_thin_static.lib`）进行编译。
- 在 Windows 本机执行 C 测试程序，验证调用 `hs_abi_version()` 正确返回预期版本号，验证服务配置与生命周期调度无崩溃、无内存访问违规。
- 确保全仓既有 228 项 MoonBit 测试持续保持 100% 通过（0 回归、0 警告）。

## Acceptance Criteria

### 产物与符号隔离
- [ ] 运行 `scripts/build_cabi.mbtx` 能够成功在 Windows 本机生成 `hs_thin.dll`、`hs_thin.lib`、`hs_thin_static.lib`、`hs_full.dll`、`hs_full.lib`、`hs_full_static.lib`。
- [ ] 符号检查确认：导出的动态库仅暴露 `hs_*` 导出符号，绝不含 `main` 入口。
- [ ] 符号检查确认：`hs_thin` 动态库与静态库中绝对不包含 `mbedtls_*`、`psa_*` 符号。

### C 程序调用验证
- [ ] 独立 C 测试程序能够成功编译并链接 `hs_thin` 动态库，运行无崩溃且正确输出 ABI 版本号。
- [ ] 独立 C 测试程序能够成功编译并链接 `hs_thin_static` 静态库，运行无崩溃且行为一致。

### 全仓测试与整洁度
- [ ] `moon check --target native` 全仓保持 0 错误、0 警告。
- [ ] `moon test --target native` 全仓全量测试保持 100% 全部通过。
</USER_REQUEST>

## Follow-up — 2026-09-19T03:28:44Z

<USER_REQUEST>
# Teamwork Project Prompt — Post-Implementation Review, Adversarial Challenge & Compliance Audit

> Status: Launched
> Goal: Craft prompt → get user approval → delegate to teamwork_preview
> Requested team: 全功能多智能体团队（审查、对抗挑战、规范审计独立运作）

对已完成的 `http-server-mbt` 项目 `thin` 与 `full` 双版本 CLI 打包及 C ABI 动静态库导出流水线（Milestone 1 ~ 3，commit `9cabfb9` 与 `a5c3edf`）进行全方位、多视角的独立代码审查（Review）、对抗挑战（Adversarial Challenge）与规范合规审计（Audit），确保无内存泄漏、无符号污染、无边界未捕获崩溃，严格契约达标。

Working directory: E:/project/moonbit/unmbt/http-server-mbt
Integrity mode: development

## References
- 规格契约与设计文档: `docs/design.md` (D-07, D-08, D-11), `docs/tasks.md` (T-020, T-027)
- 历史交接指南: `docs/cli-thin-full-and-cabi-handover.md`
- 核心实现包: `c_abi/`, `cmd/http-server-mbt-thin/`, `cmd/http-server-full/`, `full/`, `server/`
- 构建驱动与测试: `scripts/build_cabi.mbtx`, `testdata/c_consumer/`

## Requirements

### R1. 多维度代码与架构独立审查（Independent Architecture & Code Review）
- **架构解耦审查**：审查 `server/` 是否彻底解耦加密 C 依赖（`server/moon.pkg` 仅依赖基础运行时与系统 I/O，无 `tls` 依赖）；审查 `full/` 是否纯粹通过依赖注入承载 TLS Acceptor。
- **C ABI 契约审查**：逐行审查 `c_abi/include/http_server.h`、`c_abi/thin/` 与 `c_abi/full/`：
  - 导出接口契约是否严格遵循 D-07 / D-11 规范（仅暴露 `hs_abi_version`, `hs_server_start`, `hs_server_stop`, `hs_server_destroy`, `hs_error_copy` 5 个公开 API）。
  - 是否有任何 MoonBit 托管对象（String, Bytes, 闭包指针）跨越 ABI 泄露给外部宿主。
  - 内存与生命周期管理：句柄分配与销毁是否具备所有权边界，错误信息拷贝是否防止缓冲区溢出。
- **构建驱动与跨平台契约**：审查 `scripts/build_cabi.mbtx` 是否完全遵循 `.mbtx` 纯 MoonBit 约束，工具链探测与对象清洗逻辑是否健壮。

### R2. 严苛对抗挑战与边界模糊测试（Adversarial Challenge & Boundary Stressing）
- **C ABI 异常与攻击面挑战**：
  - 空指针输入（NULL config / NULL err_buf）、空字符串、超长字符串、畸形非合法 JSON 格式输入。
  - 极端网络参数：非法端口（负数、0、65536、溢出数值）、不可达绑定地址、不存在的静态根目录。
  - TLS 组合攻击：指定 cert 但缺失 key、指定 key 但缺失 cert、证书文件不存在、证书与私钥内容损坏或格式错误，验证是否先于监听精准拦截并安全报错。
- **生命周期与状态机重入挑战**：
  - 服务器重复启动（double start）、重复停止（double stop）、未启动即销毁、停止后重复销毁。
  - 验证在任何非法调用顺序下，C ABI 接口均不发生段错误（Segmentation fault）、空指针解引用或不可恢复 panic。
- **符号隔离与纯净度对抗审计**：
  - 使用 `dumpbin /EXPORTS` 严格检查 `target/cabi/hs_thin.dll` 与 `target/cabi/hs_full.dll`，确认仅导出 5 个公共 `hs_*` 符号，严禁存在 CLI `main` 入口或任何 MoonBit 编译器运行时符号。
  - 使用 `dumpbin /SYMBOLS` 严格审计 `target/cabi/hs_thin_static.lib`，确认绝对不含任何 `mbedtls_*` 或 `psa_*` 符号。
- **CLI 拦截与退出码挑战**：
  - 向 `http-server-mbt-thin` 传入 `--cert`、`--key`、`--proxy` 等高级参数，确认严格退出状态码 1，标准错误输出可操作指引，且系统上无残留端口监听。

### R3. SDD 规范合规审计与全量质量门禁（SDD Audit & Regression Gate）
- **规范与任务一致性核验**：
  - 核查 `docs/proposal.md`、`docs/design.md`（D-07, D-08, D-11）与 `docs/tasks.md`（T-020, T-027），确认文档差异（AD 记录）、功能描述与 Windows 交付证据完全闭环。
- **全流程自动化验证**：
  - 重新执行 `moon run scripts/build_cabi.mbtx`，验证全部 6 项动静态库产物生成与 4 组独立 C 测试程序执行 100% PASS。
  - 重新执行全仓 `moon check --target native`，保持 0 errors, 0 warnings。
  - 重新执行全仓 `moon test --target native`，确保全部 230 项测试 100% 通过（0 失败、0 回归）。
- **产出综合审计报告**：
  - 综合审查员（Reviewer）、挑战者（Challenger）与审计员（Auditor）的独立结论，给出最终评审通过与签署决议。

## Acceptance Criteria

### 独立代码审查通过标准
- [ ] 架构审查通过：`server/` 无任何加密/MbedTLS 静态符号泄漏，双版本功能按模块清晰解耦。
- [ ] C ABI 审查通过：头文件设计与实现严格遵循 D-07 / D-11，无托管类型泄露，生命周期清晰无死锁风险。

### 对抗挑战通过标准
- [ ] C ABI 对抗测试通过：NULL、非法 JSON、极端端口、非法 TLS 路径输入均安全返回对应错误码，0 崩溃、0 段错误。
- [ ] 状态机重入测试通过：多次 start/stop/destroy 调用具备幂等性与防护，无悬挂指针。
- [ ] 符号隔离审计通过：动态库导出符号严格仅为 5 个 `hs_*`，无 `main` 符号；`thin` 静态库零 MbedTLS 符号。
- [ ] CLI 对抗测试通过：`http-server-mbt-thin` 遇到不支持选项严格退出码 1 且无监听。

### SDD 审计与全仓门禁标准
- [ ] `docs/design.md` 与 `docs/tasks.md` 规范与状态记录 100% 准确反应该实现与交付证据。
- [ ] `scripts/build_cabi.mbtx` 端到端执行通过，4 个独立 C 消费者测试 100% PASS。
- [ ] `moon check --target native` 保持 0 errors, 0 warnings。
- [ ] `moon test --target native` 230/230 测试 100% PASS。
</USER_REQUEST>
