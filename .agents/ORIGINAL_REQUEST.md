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

## 2026-09-11T08:00:59Z

【续接执行指示】
上一次执行在 Milestone 2 完成后因模型配额中断。请接续当前已完成进度，继续推进剩余任务！

### 当前已完成成果（经实测核验）
- Milestone 1: Warning Elimination & Clean Baseline 已通过验收（`moon check --target native` 实测 0 警告、0 错误）。
- Milestone 2: Core Protocols, MIME, Security & Config 已通过验收（`moon test --target native` 实测 30/30 测试全部通过，涵盖 cache、range、mime、security、routing、config）。
- 完整状态和交接文档位于：
  - `D:\project\moonbit\http-server-mbt\.agents\orchestrator_1\PROJECT.md`
  - `D:\project\moonbit\http-server-mbt\.agents\orchestrator_1\handoff.md`
  - `D:\project\moonbit\http-server-mbt\.agents\orchestrator_1\progress.md`
  - `D:\project\moonbit\http-server-mbt\.agents\orchestrator_gen2\DISPATCH.md`

### 待完成的核心里程碑与任务
1. **Milestone 3: Engine 业务与路由特性接入**
   - HTTP/1.1 完整请求分发（GET/HEAD）
   - 预压缩内容协商（.br / .gz 候选检测与 Accept-Encoding 优先级选择，forceContentEncoding）
   - 目录索引探测（index.html）与美观的 HTML 目录列表视图渲染（排序、文件大小格式化、转义）
   - SPA / try-files 运行时未命中兜底回退逻辑（不掩盖鉴权与路径越界错误）
2. **Milestone 4: Windows Native TransmitFile 与 IOCP 零拷贝传输**
   - 实现 Windows 内核级 TransmitFile 传输静态明文大文件与 Range 区间
   - 具备有界缓冲降级与断连取消保护，确保无文件句柄与 Socket 句柄泄漏
3. **Milestone 5: CLI、生命周期与架构整洁度**
   - 完整命令行参数解析（--port, root, --base-url, --base-dir, --spa, --try-files, --autoIndex, --showDir, --cache, --cors, --auth, --help, --version 等）
   - 非法参数在监听前拦截报错，优雅响应信号退出并排空资源
   - 始终保持 0 错误、0 编译器警告，规范更新 `.mbti` 与格式化
4. **Milestone 6: 原版全量测试套件迁移（C001~C042 及 CC/CE）与对抗加固**
   - 对照 `docs/tasks.md` 逐例迁移矩阵，编写 Windows Native 单元与集成测试
   - 验证边界条件、并发请求、断开连接及故障注入安全不变量
   - 外部代码与依赖严格限定为 MIT、Apache-2.0、BSD-3-Clause 等宽松商业友好许可

Working directory: D:\project\moonbit\http-server-mbt
Integrity mode: benchmark
Requested team: Full multi-agent team (全功能多 Agent 团队协同推进)

## 2026-09-11T08:18:32Z

【用户明确指令】
用户要求：“m3实现后先停下来”。
请通知 Orchestrator：在 Milestone 3（Engine 特性层）实现完毕且完成 Gate 门禁验证后，立即暂停后续里程碑（暂不启动 Milestone 4），整理并汇总 M3 的交付成果、测试结果及当前状态向用户汇报，等待用户的下一步指示。

## 2026-09-11T08:33:45Z

【用户最终暂停指令】
用户明确要求：“让现有的agent干完手头上的工作后停下来，不用干后续了，然后在docs下记录下进度，方便下次继续任务”。
请注意：当前 Gate 评审员和审计员完成手头审查裁决后，Milestone 3 正式闭环即彻底停止所有后续任务（不启动 M4、M5、M6），在 docs 下完成进度交接与记录，进入完全停止状态。
