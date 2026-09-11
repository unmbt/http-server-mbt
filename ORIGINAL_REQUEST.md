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


