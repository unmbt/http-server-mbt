# http-server-mbt 规格设计与需求挖掘报告 (Specification Mining Report)

**生成日期**：2026-09-11  
**规范版本**：版本 4 (2026-09-10)  
**挖掘专员**：spec_miner_docs  
**工作区路径**：`D:\project\moonbit\http-server-mbt\.agents\spec_miner_docs`  
**基准来源**：`docs/proposal.md`、`docs/design.md`、`docs/tasks.md`、`docs/windows-baseline.md`、`ORIGINAL_REQUEST.md`、`AGENTS.md`  
**参考仓库**：`http-party/http-server` @ `0d3b7bb5b6e8a59fd450ae2dca65870009cfcd8b` (14.1.2)  

---

## 1. 任务背景与执行概要

根据 `ORIGINAL_REQUEST.md` 与 SDD（规范驱动开发）指导方针，本项目旨在完善 Windows Native 下原版 `http-server` 的全部功能与测试代码，补充 Windows TransmitFile/IOCP 零拷贝传输、BaseURL 挂载与 SPA/try-files 路由回退，重构优化目录与包架构并彻底消除当前存在的 46 个编译器 Warning，构建商业友好（MIT/Apache-2.0/BSD-3-Clause）的高性能静态文件服务器与可嵌入库。

本报告对项目所有既有文档进行全面规格挖掘，提取完整的需求定义（R1～R4、R-SDD～R-N16）、18 个核心设计契约（D-01～D-18）、34 项任务（T-001～T-034）及其当前实施状态、21 组新增测试（N-01～N-21）、逐例迁移矩阵（C001～C042、CC-01～CC-28、CE-01～CE-02）、46 个编译器告警定位，并整理出标准的功能表与极端边缘案例表。

---

## 2. 需求体系完整目录

### 2.1 用户原始需求 (R1 ～ R4)

| 需求 ID | 名称 | 核心子需求与规范要求 | 验收标准与交付目标 |
|---|---|---|---|
| **R1** | **原版 http-server 功能完整性与 Windows 兼容** | 1. 完整 HTTP/1.1 解析与调度，支持 GET/HEAD。<br>2. 条件请求与缓存协商：ETag、If-None-Match（强/弱比较）、If-Modified-Since、Cache-Control（数字/字符串/max-age）、304 Not Modified 无正文。<br>3. Range 字节区间请求：206 Partial Content、Content-Range 首部生成、无效/越界区间返回 416 Range Not Satisfiable，与条件请求组合。<br>4. 预压缩协商：Brotli (.br) 与 gzip (.gz) 探测、Accept-Encoding 优先级、forceContentEncoding、降级原文件。<br>5. MIME 与扩展名：标准 MIME 表、自定义 MIME 与 `.types` 文件解析、默认扩展名（.html）、404 页面生成。<br>6. 目录索引与渲染：index 查找与重定向、可配置列、排序、路径安全转义 HTML 视图。<br>7. 安全与认证：拦截目录穿越/越界、HTTP Basic Auth（常量时间比较，认证先于文件探测）、CORS/COOP/PNA 安全头、Host 白名单。<br>8. CLI 与生命周期：命令行解析、非法参数在监听前阻断报错、Ctrl+C/信号退出与资源清理。 | 1. 原版 42 个测试文件全部适用断言通过。<br>2. Windows 本机与跨平台行为完全一致。<br>3. 冒烟测试与 CLI 参数校验通过。 |
| **R2** | **核心扩展：Windows 零拷贝传输、BaseURL 挂载与 SPA 路由** | 1. **Windows 内核零拷贝**：基于 `TransmitFile` / IOCP 传输静态明文与 Range 分段；有界缓冲降级；断连取消不泄漏文件与 Socket 句柄。<br>2. **BaseURL 挂载**：`--base-url` 与 `--base-dir` 路由前缀挂载，配置与请求 URL 路径严格归一化。<br>3. **SPA 与 try-files**：`--spa`（未命中回退至根 index.html）与 `--try-files <file>` 回退；未命中兜底不吞鉴权/权限错误；与代理配置互斥校验。 | 1. 零拷贝传输无用户态多次内存拷贝。<br>2. 异常断连无句柄泄漏。<br>3. BaseURL 与 SPA 自动化测试覆盖边界与错误组合。 |
| **R3** | **模块化架构与 0 编译器警告 (0 Warnings)** | 1. 包职责清晰解耦：core、engine、fs/io/zero-copy、server、cmd。<br>2. 彻底解决并消除 46 个编译器 Warning（`redundant_modifier`、`unused_constructor`、`unused_package`、`deprecated` API、`method`/`use` 保留字命名），达到 0 warning、0 error。<br>3. 规范暴露 `.mbti` 接口，符合 MoonBit 习惯用法。<br>4. 许可证合规：严格限定商业友好宽松协议（MIT, Apache-2.0, BSD-3-Clause）。 | 1. `moon check --target native` 输出 0 错误 0 警告。<br>2. `moon info` 与 `moon fmt` 接口规范一致。<br>3. 无循环依赖与内部类型泄露。 |
| **R4** | **全面客观的测试套件迁移与验证** | 1. 对照逐例迁移矩阵（C001～C042、CC-01～CC-28、CE-01～CE-02）建立 Native 单元测试与集成测试。<br>2. 覆盖空文件、常规静态、大文件传输、并发请求、断开连接、异常路径等场景。 | 1. `moon test --target native` 全部迁移测试与新增测试通过。<br>2. 具备可重复验证的客观防线。 |

### 2.2 SDD 规范追踪需求 (R-SDD ～ R-N16)

| 需求 ID | 要求与验收依据 | 关联设计 | 实施任务 |
|---|---|---|---|
| **R-SDD** | 需求 → 设计 → 任务 → 测试证据全程追踪；变更契约先同步文档；严禁无证据勾选任务。 | D-01, D-10 | T-001, T-025, T-026 |
| **R-COMPAT** | 逐例迁移固定原版 42 个测试文件语义；包含 28 项公共 fixture；完整包通过全部适用用例与迁移决策。 | D-01, D-03, D-10 | T-001, T-003～T-015, T-026 |
| **R-SAFE** | 保证路径边界、CRLF/XSS 防护、认证顺序、HTTP 边界、背压与资源回收；新回退不绕过安全防线。 | D-03～D-07 | T-003～T-005, T-010, T-016, T-017, T-019, T-020 |
| **R-N01** | Native 文件传输必须具备平台内核传输路径及有界缓冲降级（普通文件、Range、预压缩文件）。 | D-05 | T-002, T-017 |
| **R-N02** | 独立 CLI 无需语言运行时；Linux 提供完全静态二进制及容器镜像；三平台分别报告依赖与体积。 | D-08, D-15 | T-002, T-012, T-022 |
| **R-N03** | 保证高性能原则：优先单进程高效 I/O、按需分配与有界调度；多核作为可选实验（撤出量化指标）。 | D-05, D-09 | T-016 |
| **R-N04** | 无栈连接状态机与轻量事件循环；交付可运行、可选的 Linux io_uring 实验后端。 | D-05 | T-016, T-023 |
| **R-N05** | 复用构建器、有界扫描与高效集合替代高频拼接/嵌套回调；保持目录输出语义与高效流式渲染。 | D-06, D-09 | T-009, T-018 |
| **R-N06** | 提供有版本、所有权和线程契约的 C ABI 动态库；C/Python 验证同一静态引擎；正文不要求整文件进内存。 | D-07 | T-002, T-015, T-020, T-021 |
| **R-N07** | 独立支持 BaseURL、SPA 默认回退与单文件自定义回退；配置冲突在监听前报错退出。 | D-04 | T-003, T-019 |
| **R-N08** | 提供与动态库同 ABI 的原生静态库、依赖/链接清单及 C/Rust 消费示例；验证可链接进应用及 Node 插件。 | D-08, D-11 | T-002, T-027 |
| **R-N09** | 提供 Node-API 插件及 npm 适配；调用托管异步接口，映射背压/取消/关闭，不阻塞 Node 事件循环。 | D-07, D-12 | T-002, T-028 |
| **R-N10** | 交付可运行的 wasm-gc 共享核心与宿主 I/O 适配示例；明确能力矩阵；应用无需手动调度引擎。 | D-13 | T-002, T-029 |
| **R-N11** | 具备可发布的 Mooncakes 模块、公共包入口与干净外部消费验证；供其他 MoonBit 模块作静态文件库。 | D-02, D-07, D-14 | T-015, T-030 |
| **R-N12** | 提供 min/full Docker 镜像封装精简/完整 CLI；默认 Distroless static nonroot，保留 scratch 变体。 | D-08, D-15 | T-022, T-025 |
| **R-N13** | GitHub Actions 工作流覆盖三平台兼容、原生 I/O、消费验证与打包；支持 Windows 本机起步。 | D-10, D-16 | T-001, T-031, T-032, T-025, T-026 |
| **R-N14** | 默认由库托管事件循环、异步操作与关闭排空；公开 API 严禁要求用户手动 pump/run/poll。 | D-05, D-07, D-11～D-14 | T-002, T-015, T-016, T-020, T-021, T-028～T-030 |
| **R-N15** | 下载绑定已打开文件版本；检测到原地修改/截断立即终止；客户端重试从偏移 0 重新请求，不跨版本拼接。 | D-03, D-05, D-17 | T-005, T-007, T-008, T-017, T-033 |
| **R-N16** | 状态机故障注入与模糊测试；保存种子、最小复现与回归语料；纳入三平台持续验证。 | D-10, D-18 | T-004, T-016, T-025, T-034 |

---

## 3. 设计契约深度分析 (D-01 ～ D-18)

### D-01: 基线、迁移决策与默认值
- **基线版本**：`http-party/http-server` @ `0d3b7bb5b6e8a59fd450ae2dca65870009cfcd8b` (14.1.2)。
- **10 项来源差异决策 (AD-01 ～ AD-10)**：
  - **AD-01**：公共案例不是 23 项，实际包含 28 项（`CC-01`～`CC-28`），core 与 middleware 均需完整跑通 28 项。
  - **AD-02**：`gzip` 核心中间件默认 true，但 Server/CLI 默认 false；Brotli 均默认 false。
  - **AD-03**：超时字段为 `idle_timeout_ms`，Server/CLI 默认 120000 ms（CLI `-t` 接收秒值转毫秒）。测试必须包含 1000 ms 真实断连验证。
  - **AD-04**：端口上界修复为 65535。浮点端口 `9090.86` 截断为 9090；`-1`、`65536`、`65537` 返回非零退出码且不监听。
  - **AD-05**：Windows 下 `<dir>` 实体目录 fixture 无法创建跳过，但在三平台补齐 `%00` NUL 请求防崩与 HTML 实体转义测试。
  - **AD-06**：Node 内部事件映射为 MoonBit 结构化结果（Handled/Next/Error）、生命周期事件与结构化委托。
  - **AD-07**：配置非法端口（如 99999）在监听前报错退出；合法但未监听端口在 upgrade 后运行期报错，不崩溃主服务。
  - **AD-08**：路径隔离采用组件/句柄边界；HEAD 请求全链路不丢失；字符集嗅探仅读取前 1024 字节，不整文件读入。
  - **AD-09**：HTTPS 入口支持自签名证书；代理上游验证及 `secure=false` 由 `N-12` 专门测试。
  - **AD-10**：下载期间原地改写立即中断（D-17），Range 续传需强验证器匹配。
- **配置默认值矩阵**：
  - `root`：优先同级 `./public`，不存在则当前目录 `.`。
  - `port` / `address`：默认 8080，双栈绑定；端口 0 由系统动态分配并返回实际端口。
  - `cache`：3600 秒；`-1` 归一化为 `no-cache, no-store, must-revalidate`。
  - `defaultExt`：`html`。
  - `showDir` / `autoIndex` / `showDotfiles`：默认 true；`dirOverrides404`：默认 false。
  - 安全：Basic Auth、CORS、COOP、PNA、robots、代理、TLS 默认关闭；Host 默认允许所有。
  - 新增特性：`base_url=/`，`fallback=None`，`io_backend=platform`。

### D-02: 包职责与单向依赖架构
- **包划分**：
  - `core`：纯逻辑包（可移植 Native / wasm-gc），包含请求模型、元数据、配置归一化、路径与 MIME 解析、Range/缓存计算、目录 HTML 渲染。**绝对不依赖 Native I/O**。
  - `engine`（根包）：Native 静态引擎，拥有 `StaticEngine`、`Response`（Empty/Bytes/FileRegion/Stream）、文件 lease 管理、本地文件扫描。
  - `server`：完整服务器包，包含监听器、TLS、代理、WebSocket 编排，依赖根包 `StaticEngine`。
  - `cmd`：CLI 命令行解析（`argparse`）、环境变量处理、横幅输出、信号捕获与优雅退出。
  - `internal/http`、`internal/platform`、`internal/runtime`：内部协议状态机、IOCP/epoll 系统调用桥接、无栈事件循环。
- **依赖方向**：严格单向向下：`CLI -> Server -> Engine -> Core`，底层的 `IO` / `Platform` 只由 Native 运行时消费，`Core` 永不反向依赖平台 I/O。

### D-03: 请求处理与静态语义
- **处理顺序流水线**：
  1. HTTP 报文边界检查（防分片走样、TE/CL 冲突、非法控制字符）。
  2. 日志钩子。
  3. Basic Auth 鉴权（常量时间比较，认证失败直接 401，严禁先探测文件是否存在）。
  4. Host 白名单校验（不匹配直接 403）。
  5. 安全响应头注入（CORS、COOP、PNA、自定义头）。
  6. robots.txt 拦截。
  7. 显式规则代理 / 全量代理匹配。
  8. 静态文件引擎处理。
  9. 兜底代理 / 页面回退（SPA/try-files）/ 宿主 Next 错误委托。
- **安全与防护细节**：
  - 请求行上限 8 KiB，头部总量上限 16 KiB，头数量上限 100。
  - URL 百分号解码**仅执行一次**，校验整体有效性，拒绝 NUL 字符。
  - 根目录锚定：逐组件解析，严禁 `/root-other` 字符串前缀撞车；解析 symlink 必须受限于 root 内部。
  - 字符集嗅探：最多读取文件前 1024 字节，支持 UTF-8、ISO-8859-6、Shift_JIS。
  - 强/弱 ETag：弱 ETag 格式 `W/"<tag>"`，弱比较默认开启。
  - Range 语法：支持裸 `3-5` 与标准 `bytes=3-5`，超出返回 416 并附带 `Content-Range: bytes */<length>`。HEAD 请求执行 Range 计算但不发送正文。
  - 目录与 404：若 `dirOverrides404=false`，自定义 404.html 优先于无 index 的目录列表；开启后优先展示目录列表。

### D-04: BaseURL 挂载与 SPA / try-files 回退
- **参数归一化与校验**：
  - `base_url`：接收 `app`、`/app`、`/app/` 统一归一化为 `/app`；根保留 `/`。
  - 拒绝规则：包含完整 URL（如 `http://`）、query、hash、NUL、`..` 点段、反斜杠 `\` 均直接抛 `ConfigError`。
  - `--base-dir` 为 `--base-url` 别名，两者同时存在且归一化值不同时直接报错。
- **互斥冲突矩阵 (监听前报错)**：
  - `--spa` 与 `--try-files <file>` 同时配置 -> **ConfigError**。
  - 页面回退（SPA 或 try-files）与任一代理模式（`--proxy`、`--proxy-all`、`--proxy-config`）同时配置 -> **ConfigError**。
  - `--proxy-all` 未配置 `--proxy` -> **ConfigError**。
  - `try-files` 路径为空、指向目录、绝对路径、或超出 root 边界 -> **ConfigError**。
- **运行时路由契约**：
  - 鉴权与路径安全先于 BaseURL。
  - 前缀匹配基于组件边界：`/app` 匹配 `/app` 与 `/app/xxx`，但不匹配 `/application`。挂载外请求返回 403。
  - 去除前缀后依次尝试：真实文件/预压缩 -> 默认扩展名补全（.html） -> 目录补斜杠 302 -> index 文件 -> 目录列表 -> **回退文件**。
  - **回退契约**：仅针对最终未命中的 GET / HEAD；不检查 Accept 头，缺失的 JS/CSS/API 路径同样回退；回退文件始终相对于 root 查找；内部仅回退一次，不重定向浏览器 URL，不递归触发；启动时验证回退文件存在，运行时若被删除返回最终 404，权限缺失返回 403。

### D-05: Windows TransmitFile / IOCP 零拷贝与资源管理
- **内核零拷贝模型**：
  - Windows 原生采用 `TransmitFile` 配合 IOCP Overlapped 传输明文文件与 Range 分段。
  - 大于单次传输上限的文件进行分段异步传输。
  - 降级机制：TLS 加密传输、动态生成内容（如目录列表）、宿主框架嵌入模式自动降级为有界缓冲流式传输，绝不宣称 TLS 零拷贝。
- **生命周期与防泄漏**：
  - 连接 ID 与操作 ID 必须携带代数（generation），防止槽位复用后迟到完成事件串扰新连接。
  - 客户端提前断连：立即撤销 Socket 监听，调用系统取消接口，**但必须等待 IOCP 完成包到达后才能释放 Overlapped 缓冲与文件句柄**，确保 0 句柄泄漏。
  - 优雅停止：默认 5 秒宽限期，停止 Accept，排空进行中的请求，随后强行取消并清理。

### D-06: 目录渲染算法
- **三步管线**：有界读取目录项元数据 -> 分类与稳定排序 -> HTML 转义流式渲染。
- **算法复杂度**：压缩伴生文件（`.gz`/`.br`）匹配采用 HashSet 达到 $O(N)$；文件名与目录排序达到 $O(N \log N)$。
- **内存优化**：复用具备容量提示的 `StringBuilder`，采用 UTF-8 分块编码输出，避免大目录整页产生双份常驻内存。
- **转义契约**：文件名 HTML 转义（`<dir>` 转为 `&#x3C;dir&#x3E;`）；URL href 编码（空格转 `%20`，加号 `+` 转 `%2B`）；query 继承保留（`&` 转为 `&#x26;`）。

### D-07: 公共 MoonBit API 与 C ABI v1
- **MoonBit 公共 API**：
  - 库托管异步循环，不暴露裸底层 poll/pump。
  - `StaticEngine`：异步 `handle(req)` 返回 `Handled(Response)`、`Next` 或 `Error(ServerError)`。
  - `Server`：`start(config)` 与 `stop()`。
  - `Response` 的 `FileRegion` 为引擎内部持有的受控 lease，不将裸文件句柄交给外界。
- **C ABI v1 规范**：
  - 符号导出前缀统为 `hs_*`。
  - 句柄类型：`hs_engine_t`、`hs_server_t`、`hs_operation_t`、`hs_response_t`、`hs_chunk_t`。
  - 异步契约：明确区分“拒绝接纳无回调”与“已接纳必有恰好一次最终完成通知”。
  - 线程模型：库内部维护 owner 线程与安全队列，宿主跨线程提交；C 回调在独立上下文触发，禁止在公共入口内直接内联回调。
  - 销毁协议：先发起 close -> 库取消并排空内部在途 I/O -> 触发关闭完成回调 -> 宿主释放持有句柄。

### D-08: 构建分发与静态 TLS
- **目标产物**：
  - 精简 CLI（min）：静态 HTTP、缓存、Range、目录、BaseURL/SPA；剔除 TLS/代理/WebSocket（传入相关参数明确报错）。
  - 完整 CLI（full）：支持全部兼容能力与静态 TLS。
  - C 动态库、C 静态库、Node 插件、wasm-gc 核心包、Mooncakes 模块。
- **静态依赖规则**：Linux 采用 musl 做到完全无动态依赖；Windows 仅依赖系统 DLL（如 `ws2_32.dll`、`mswsock.dll`），避免依赖外部 MSVC Redistributable。
- **TLS 方案**：静态链接受支持的 OpenSSL 3 稳定版本，内置 CA 信任根，支持配置覆盖，支持私钥密码（passphrase），支持 SNI 验证。

### D-09: 高性能原则与历史 P 计划撤出
- 版本 4 已明确**撤出所有量化性能指标**（P-01 产物基准、P-02 启动基准、P-03 内存基准、P-04 连接规模基准、P-05 目录基准、P-06 传输基准及 T-024 任务）。
- 当前核心原则为单进程高效 I/O、按需分配、有界缓冲与背压，不再设置数字性能验收门槛。

### D-10: 测试分层与 N-01 ～ N-21 契约测试组
- **测试层级**：U（纯函数）、H（Native HTTP 服务）、M（中间件）、L（CLI 进程）、F（C ABI 外部测试）、S（系统/生命周期）。
- **21 组新增契约测试**：
  - `N-01`：BaseURL 边界、组件隔离、挂载外 403。
  - `N-02`：SPA 与 try-files 单独及与 BaseURL 组合、GET/HEAD 回退。
  - `N-03`：路由与代理冲突、回退文件删除（404）与权限变更（403）。
  - `N-04`：单双编码目录穿越、根路径撞车、symlink 越界、Windows 盘符/UNC/ADS 注入拦截。
  - `N-05`：内核文件传输字节准确性、64 位偏移、Range 分段、TLS 缓冲降级。
  - `N-06`：资源限额、背压、超时、句柄回收、generation 槽位隔离。
  - `N-07`：Linux io_uring 可用性探测与降级。
  - `N-08`：巨型目录流式排序渲染、Unicode、内存预算耗尽 503。
  - `N-09`：C ABI 结构体大小、UTF-8 边界、并发提交、生命周期排空。
  - `N-10`：独立无运行时二进制环境启动。
  - `N-11`：HTTP 报文分片、TE/CL 歧义拦截、流水线有序响应。
  - `N-12`：TLS 握手、代理双向背压、WebSocket 升级与半关闭。
  - `N-13`：静态库被外部 C/Rust 程序静态链接。
  - `N-14`：Node-API 插件导入、Promise/Readable 映射、Worker 退出清理。
  - `N-15`：wasm-gc 核心在 Node 环境运行、宿主能力注入。
  - `N-16`：独立 MoonBit 模块引入外部消费。
  - `N-17`：Distroless/scratch × min/full 4 种容器组合验证。
  - `N-18`：GitHub Actions 三平台真实构建与全矩阵验证。
  - `N-19`：库托管循环各语言宿主合法上下文验证。
  - `N-20`：下载期间文件原地变更检测、FILE_CHANGED 中断与重试。
  - `N-21`：状态机故障注入与模糊测试回归。

### D-11 ～ D-18: 扩展契约精要
- **D-11 (静态库)**：验证生成 C 桥接与外部工具链归档能力；Windows 严格区分静态 `.lib` 与动态库导出 `.lib`。
- **D-12 (Node-API)**：针对 Node 22/24 LTS、Node-API v8；按 `napi_env` 隔离。
- **D-13 (wasm-gc)**：宿主注入受限文件与计时能力，内部通过不透明 host token 访问。
- **D-14 (Mooncakes)**：提供 `unmbt/http-server-mbt`、`.../server`、`.../core` 三大公共入口。
- **D-15 (Docker)**：非 root（UID 65532）运行，支持只读挂载，提供 min/full 及 scratch 变体。
- **D-16 (Windows 起步路线)**：先在 Windows 本机跑通基线与 TransmitFile，再迁入 Actions 三平台。
- **D-17 (文件变更与重新下载)**：下载期间检测到文件修改/截断立即中断，报 `FILE_CHANGED`；未提交响应报 409，已提交关闭连接；客户端重试必须从 offset 0 重新拉取，严禁不同版本分段拼接。
- **D-18 (故障注入与模糊测试)**：提供可注入调度器，对报文分片、短写、取消乱序、句柄复用进行可重现测试。

---

## 4. 任务清单与状态跟踪 (T-001 ～ T-034)

目前共有 34 个任务编号，33 项在当前范围内，全部尚未完全勾选（`- [ ]`）。其中 5 项有 Windows 本机分项进展：

| 任务 ID | 名称 | 状态 | 依赖 | 交付物与当前进展 |
|---|---|---|---|---|
| **T-001** | 固定原版资产与行为基线 | 未开始 | 无 | 固定提交哈希，取得 42 个测试文件与 fixtures。 |
| **T-002** | 三平台 Native、库导出与后端可行性验证 | 未开始 | T-001 | 验证 C 导出桥接、静态链接与 IOCP 接口。 |
| **T-003** | 配置与别名归一化 | 进行中（Windows 分项） | T-001, T-002 | 已交付 `core.Config`、BaseURL 归一化、路径校验。 |
| **T-004** | HTTP 增量解析与响应计划 | 未开始 | T-001, T-002 | 增量解析、报文分片、TE/CL 检查。 |
| **T-005** | 安全路径与文件句柄抽象 | 未开始 | T-002, T-003 | 根目录锚定、路径防越界、文件 lease 机制。 |
| **T-006** | 静态文件、MIME 与索引解析 | 进行中（Windows 分项） | T-003～T-005 | 已交付 GET/HEAD、默认 .html、MIME、404 与 index 基础。 |
| **T-007** | 缓存与条件请求 | 进行中（Windows 分项） | T-006 | 已交付 ETag、304 基础与 Cache-Control；待 T-033 接入。 |
| **T-008** | Range 与预压缩表示 | 进行中（Windows 分项） | T-006, T-007 | 已交付 206/416、gzip/Brotli 选择与 HEAD 空正文。 |
| **T-009** | 目录行为与渲染基线 | 未开始 | T-006 | 目录扫描、排序、HTML 转义与 query 继承。 |
| **T-010** | 安全和响应策略 | 未开始 | T-003～T-005 | Basic Auth 常量时间比较、CORS/COOP/PNA、Host 白名单。 |
| **T-011** | 完整 CLI 与进程生命周期 | 未开始 | T-003, T-006, T-009, T-010 | 完整 CLI 参数解析、监听前校验、Ctrl+C 退出。 |
| **T-012** | 静态链接 TLS | 未开始 | T-002～T-004 | 静态链接 OpenSSL 3、证书校验、SNI 支持。 |
| **T-013** | HTTP/HTTPS 代理与规则重写 | 未开始 | T-006, T-010, T-012 | 规则代理、proxy-all、路径重写与双向背压。 |
| **T-014** | WebSocket 透传 | 未开始 | T-013 | Upgrade 握手、字节透传、半关闭处理。 |
| **T-015** | MoonBit 库与中间件 API | 进行中（Windows 分项） | T-006～T-010 | 已交付 `StaticEngine`、`with_server`、`Handled`/`Next`。 |
| **T-016** | 三平台库托管无栈事件循环 | 未开始 | 众多前置 | epoll/kqueue/IOCP、无栈状态机、generation 槽位隔离。 |
| **T-017** | 三平台内核文件传输 | 未开始 | T-008, T-016, T-031 | 承接 TransmitFile 与 sendfile，64 位偏移，有界降级。 |
| **T-018** | 目录算法与分块优化 | 未开始 | T-009, T-016 | O(N) 伴生匹配、流式分块、内存预算保护。 |
| **T-019** | 新路由特性与互斥校验 | 未开始 | T-003 等 | `--base-url`、`--spa`、`--try-files` 冲突校验与回退。 |
| **T-020** | C ABI v1 托管异步动态库 | 未开始 | T-002, T-015, T-016, T-019 | 导出 `hs_*` 接口，托管内部线程，异步结果通知。 |
| **T-021** | C 与 Python 最小集成示例 | 未开始 | T-020 | C/Python 动态库加载与生命周期验证。 |
| **T-022** | 独立二进制与镜像分发 | 未开始 | 众多前置 | 精简/完整 CLI 编译、Linux 静态二进制、Docker 镜像。 |
| **T-023** | 可运行 io_uring 实验后端 | 未开始 | T-016, T-017 | Linux io_uring 探测与安全回退。 |
| **T-024** | 原性能基准交付 | **未开始（已撤出）** | 无 | **已撤出当前范围**，保留编号，不作门槛要求。 |
| **T-025** | GitHub Actions 完整验证与发布门槛 | 未开始 | 各集成任务 | Actions 自动化全流程与发布前检查门槛。 |
| **T-026** | 完整兼容与重构交付审计 | 未开始 | T-001～T-034 | 全量规范、测试、交付物综合审计。 |
| **T-027** | 静态库打包与 C/Rust 消费 | 未开始 | T-002, T-017, T-020 | 三平台静态库归档与 C/Rust 静态链接示例。 |
| **T-028** | Node-API 插件与 npm 适配包 | 未开始 | T-020, T-027 | `.node` 原生插件与 npm 包装。 |
| **T-029** | 可运行 wasm-gc 实验引擎 | 未开始 | T-002, T-015, T-018, T-019 | wasm-gc 编译与 Node 宿主 I/O 运行。 |
| **T-030** | Mooncakes 包与外部 MoonBit 消费 | 未开始 | T-015, T-016, T-019, T-029 | 验证 `moon add` 干净外部工程消费。 |
| **T-031** | Windows 本机 IOCP/TransmitFile 静态传输 | 未开始 | T-001～T-008 | Windows 本机最小 IOCP 状态机与 TransmitFile 传输。 |
| **T-032** | GitHub Actions 三平台基础矩阵 | 未开始 | T-001, T-031 | 建立跨平台 CI 基础骨架。 |
| **T-033** | 文件变更中断与重新下载 | 未开始 | T-005 等 | 运行时文件修改探测、FILE_CHANGED 中断与重试。 |
| **T-034** | 状态机故障注入与模糊测试 | 未开始 | T-004 等 | 故障调度器、边界模糊测试。 |

---

## 5. 发现功能清单 (Features Discovered)

按照 Specification Miner 规范标准格式整理：

| # | 类别 (Category) | 特性 (Feature) | 描述 (Description) | 输入 (Inputs) | 输出 (Outputs) | 错误行为 (Error Behavior) | 发现途径 (Discovered Via) |
|---|---|---|---|---|---|---|---|
| 1 | 协议与调度 | HTTP/1.1 GET/HEAD | 核心请求解析与方法调度，流水线有序响应 | TCP 报文流 | HTTP 响应报文 | 非法请求行返回 400，超限拒绝并断连 | D-03, R1, C008 |
| 2 | 缓存协商 | ETag 协商与 304 | 支持强/弱 ETag 与 If-None-Match 对比 | `If-None-Match`, `If-Modified-Since` | 304 Not Modified（无正文）或 200 | 畸形日期视为缓存未命中，返回 200 | D-03, C001, C003 |
| 3 | 缓存策略 | Cache-Control 策略 | 支持秒数、字符串及动态求值 | `cache` 配置 | `Cache-Control` 响应头 | 配置非法返回 ConfigError | D-01, D-03, C002 |
| 4 | 分段请求 | Range 字节区间 | 支持裸 `3-5` 及 `bytes=3-5` 分段 | `Range` 请求头 | 206 Partial Content + Content-Range | 越界/倒置返回 416 Range Not Satisfiable | D-03, C004 |
| 5 | 内容协商 | Brotli/gzip 预压缩 | 自动匹配磁盘伴生 `.br`/`.gz` 文件 | `Accept-Encoding` 请求头 | 200 + Content-Encoding + 对应压缩字节 | 文件损坏或魔数不合降级原文件 | D-03, C005, C006, CC-27 |
| 6 | 内容协商 | forceContentEncoding | 显式压缩扩展名是否强制带编码头 | `--force-content-encoding` 开关 | 200 + 指定编码头 | 未开启则无 Content-Encoding | D-03, C007 |
| 7 | MIME 类型 | 默认与自定义 MIME | 扩展名映射、默认 html 补全与 `.types` 解析 | 请求路径, `.types` 文件 | 对应 Content-Type + Charset | 缺失 `.types` 文件在启动时报错抛异常 | D-03, C010～C014 |
| 8 | 路径解析 | 默认扩展名补全 | 缺失扩展名时默认尝试追加 `.html` | URL 路径（如 `/index`） | 200 读取 `/index.html` 内容 | 文件不存在继续走 404/回退流程 | D-03, C015, CC-07 |
| 9 | 目录索引 | index.html 查找 | 目录自动寻找 index 文件并重定向 | 目录请求（如 `/subdir/`） | 200 返回 index.html 正文 | 无 index 则走 404 或列表展示 | D-03, CC-09, CC-14 |
| 10 | 目录重定向 | 补尾斜杠 302 | 目录请求未带尾斜杠自动补全 | 目录路径（如 `/subdir`） | 302 Found，Location 带尾斜杠 | showDir/autoIndex 均关时返回 404 无重定向 | D-03, CC-10, C025 |
| 11 | 目录渲染 | HTML 目录列表视图 | 美观可排序的目录列表视图，支持列配置与图标 | 目录 GET 请求 | 200 HTML 页面 | 条目消失容错；内存预算不足返回 503 | D-06, C016, C022～C024 |
| 12 | 安全防护 | 目录穿越拦截 | 拦截 `../`、反斜杠、双重编码越界访问 | 恶意 URL 路径 | 403 Forbidden 或 404 拒绝 | 严禁泄露 root 外任何文件 | D-03, N-04, C017 |
| 13 | 认证机制 | HTTP Basic Auth | 常量时间比较密码，认证检查优先于文件探测 | `Authorization: Basic ...` | 200 访问成功 | 凭据缺失/错误返回 401 Access denied | D-03, C042.12～19 |
| 14 | 安全策略 | CORS / COOP / PNA | 跨域资源共享、隔离与私有网络策略头注入 | 对应 CLI/配置参数 | 响应头注入对应安全头字段 | 未配置则不输出多余头 | D-03, C027～C029 |
| 15 | 安全策略 | Host 白名单 | 限制请求 Host 头只允许受信任域名/IP | `Host` 头 | 200 正常通过 | 不匹配返回 403 Forbidden | D-03, C030 |
| 16 | 核心扩展 | Windows TransmitFile | 基于 Windows IOCP 的内核级零拷贝传输 | 明文静态文件 / Range | 高效内核 I/O 传输 | 异常断连取消等待完成包，无句柄泄漏 | D-05, R2, T-031 |
| 17 | 核心扩展 | BaseURL 路径挂载 | 将服务挂载于子前缀，严格组件边界匹配 | `--base-url`, `--base-dir` | 映射并去除前缀后响应 | 挂载外请求返回 403 空正文 | D-04, R2, N-01 |
| 18 | 核心扩展 | SPA 路由回退 | 未命中路由回退至根目录 `index.html` | `--spa` | 200 返回根 index.html | 与代理互斥；权限/认证错误不回退 | D-04, R2, N-02 |
| 19 | 核心扩展 | try-files 路由回退 | 未命中路由回退至指定单个相对文件 | `--try-files <file>` | 200 返回指定文件内容 | 路径非法/越界监听前报错退出 | D-04, R2, N-02 |
| 20 | 架构演进 | 运行时文件变更检测 | 下载中检测文件原地修改/截断立即中断 | 正在下载的文件发生变更 | FILE_CHANGED 状态，中止传输 | 未提交报 409，已提交关闭连接不当 EOF | D-17, R-N15, T-033 |
| 21 | 架构演进 | 库托管异步生命周期 | 库内部管理事件循环与调度，外部无需手动驱动 | `start()` / `stop()` | 异步结果通知 | 关闭时自动排空在途请求与回调 | D-05, D-07, R-N14 |
| 22 | 嵌入生态 | C ABI 导出与宿主桥接 | 跨语言稳定 C ABI，支持 C/Python/Rust 嵌入 | C 结构体与函数调用 | `hs_*` 接口调用结果 | 结构体版本不符报 ABI_MISMATCH | D-07, D-11, T-020 |
| 23 | 嵌入生态 | Node-API 插件 | 提供原生 Node 插件与 npm 适配 | Node.js 异步调用 | 返回 Promise / 流式正文 | 主循环不阻塞，Worker 清理无悬挂 | D-12, T-028 |
| 24 | 嵌入生态 | 实验 wasm-gc 共享核心 | core 逻辑运行于 WasmGC，宿主提供 I/O | wasm 字节码与宿主契约 | 宿主驱动的 HTTP 处理 | 能力缺失明确报错 | D-13, T-029 |
| 25 | 嵌入生态 | Mooncakes 模块入口 | 作为库引入其他 MoonBit 静态文件处理框架 | `moon add` 依赖 | `StaticEngine` 实例 | 静态包不强制拉入 TLS/代理依赖 | D-14, T-030 |
| 26 | 运维交付 | Docker min/full 镜像 | Distroless static nonroot 基础层，最小化体积 | Dockerfile 构建参数 | 容器镜像产物 | min 镜像传入 TLS 参数明确报错 | D-15, T-022 |

---

## 6. 极端边缘案例清单 (Edge Cases)

| # | 特性 (Feature) | 极端/异常输入 (Input) | 预期观察行为 (Observed Behavior) |
|---|---|---|---|
| 1 | 缓存协商 | `If-Modified-Since: 275760-09-24`（极大非法年份） | 服务不崩溃，非法日期解析失败直接忽略，降级为普通未命中并返回 200 (C003) |
| 2 | 字节分段 | `Range: 333-222`（起止范围倒置） | 返回 416 Range Not Satisfiable，带 `Content-Range: bytes */size`，正文为错误说明 (C004.05) |
| 3 | 字节分段 | `Range: 500-`（起始偏移超出实际文件大小） | 返回 416 Range Not Satisfiable (C004.03) |
| 4 | 字节分段 | `Range: abc-def`（非数字格式） | 返回 416 Range Not Satisfiable (C004.04) |
| 5 | 方法语义 | `HEAD` 请求附加 `Range: bytes=0-10` | 状态码为 206，计算并输出正确响应头（含 Content-Length=11），但**严格不输出任何正文字节** (D-03, N-05) |
| 6 | URL 编码 | `GET /%` 或 `GET /?%`（畸形单百分号） | 立即返回 400 Bad Request，服务不崩溃；query 中的畸形百分号同样在路径阶段拦截 (C020, C021) |
| 7 | URL 编码 | `GET /%00` 或路径中含 NUL 字符 | 立即返回 400 或 404 拒绝，严禁截断路径导致越界或空指针异常 (AD-05, C019.02) |
| 8 | 路径安全 | `GET /root-other/file`（根目录同前缀撞车攻击） | 严格按目录组件边界比较，必须判定为根目录外并直接拦截返回 403/404 (D-03, N-04) |
| 9 | 路径安全 | 符号链接（Symlink）指向 root 目录外部 | 路径解析时检测最终句柄或组件边界，越界符号链接禁止访问，返回 403 或 404 (D-03, N-04) |
| 10 | 路径安全 | 目录请求 `GET /file/`（对普通文件追加斜杠，触发 ENOTDIR） | 正确转换为 404 Not Found（正文 `File not found. :(`），不抛出内部未捕获 I/O 异常 (C017) |
| 11 | 目录渲染 | 文件名包含 `<dir>` 标签及加号 `+` | HTML 列表中名称安全转义为 `&#x3C;dir&#x3E;`，href 链接编码为 `%2B` (C019, C022) |
| 12 | 目录渲染 | 请求 URL 带 query 参数访问目录（如 `/?a=1&b=2`） | 目录子项链接必须继承 query 参数，且 `&` 必须实体化为 `&#x26;` (C023) |
| 13 | 目录与404 | 目录无 index.html，`showDir=true` 且 `dirOverrides404=false`，但根下有 `404.html` | 返回 404 状态码，正文为 `404.html` 内容，**不展示**目录列表 (C016.02, CC-19) |
| 14 | 目录重定向 | `showDir=false` 且 `autoIndex=false` 访问裸目录 `/subdir` | 直接返回 404，**不发生**补斜杠 302 重定向 (C025) |
| 15 | 认证优先 | 用户名/密码错误，同时请求的文件不存在 | 必须立即返回 401 Access denied，**严禁先探测文件**而泄露文件存在性 (R1, D-03, C042.15) |
| 16 | 认证安全 | Basic Auth 比较与数字密码匹配 | 采用常量时间比较防时序侧信道攻击；配置数字密码 `123456` 时传入字符串 `"123456"` 正确匹配通过 200 (D-03, C042.19) |
| 17 | 端口配置 | CLI/环境变量指定浮点端口 `PORT=9090.86` | 自动向下截断为有效整型端口 9090 并成功启动监听 (AD-04, C033.02) |
| 18 | 端口配置 | CLI/环境变量指定非法端口（如 `-1`、`65536`、`99999`） | 在创建 Socket 监听前立即向 stderr 报错并退出码 1，**绝对不开启监听** (AD-04, AD-07, C033.03) |
| 19 | 路由挂载 | BaseURL 为 `/app`，客户端请求 `/application` | 严格按组件边界匹配，`/application` 不属于挂载范围，直接返回 403 空正文 (D-04, N-01) |
| 20 | 路由回退 | 开启 `--spa`，客户端请求缺失的 `/api/users/list` 或 `missing.js` | 不按扩展名或 Accept 过滤，最终未命中的 GET 统一回退读取根目录 `index.html`，返回 200 (D-04, N-02) |
| 21 | 路由互斥 | 同时指定 `--spa` 与 `--try-files shell.html` | 配置初始化阶段直接抛 `ConfigError`，进程退出，不启动监听 (D-04, N-03) |
| 22 | 路由互斥 | 开启 `--spa` 同时开启 `--proxy http://upstream` | 配置交叉校验直接抛 `ConfigError`，拒绝启动 (D-04, N-03) |
| 23 | 路由回退 | 运行时作为回退目标的文件被外部删除 | 打开文件失败，直接返回最终 404，不再递归触发二次回退 (D-04, N-03) |
| 24 | 文件变更 | 客户端大文件下载过程中，磁盘文件被原地截断或覆写 | 检测到文件句柄身份/长度变化，立即标记 FILE_CHANGED；已提交的连接直接关闭，严禁跨版本补零或拼接 (D-17, N-20) |
| 25 | 续传一致 | 客户端携带 `If-Range` 尝试对已变更文件断点续传 | 强验证器不匹配，拒绝返回 206，自动降级返回完整的 200 响应 (D-17, N-20) |
| 26 | 客户端断连 | TransmitFile 在途传输时客户端强制 RST 断开 Socket | 状态机调用取消，**严格保持 Overlapped 缓冲区与文件句柄存活**，直至 IOCP 完成包返回后安全回收，不泄漏句柄 (D-05, N-05, N-06) |
| 27 | 协议安全 | 请求头中包含 CRLF 注入字符 | 增量解析阶段直接拒绝并断开连接，抛出明确协议错误 (C026.05) |
| 28 | 协议安全 | 请求中同时包含 `Transfer-Encoding: chunked` 与 `Content-Length` | 判定为 TE/CL 走样攻击，立即拒绝请求并关闭连接 (D-03, N-11) |

---

## 7. 当前代码库编译器 46 个 Warning 审计

执行 `moon check --target native` 得到的 46 个警告详细分布与消除策略：

| 警告类型 (Warning Type) | 数量 | 涉及文件与位置 | 产生根因 | 重构消除方案 |
|---|---|---|---|---|
| `redundant_modifier` | 3 | `engine.mbt:28:3`, `29:3`, `30:3` | `pub struct Response` 中字段显式标记了多余的 `pub` 修饰符 | 移除字段前的 `pub`，保持结构体 `pub struct` 即可 |
| `unused_constructor` | 2 | `engine.mbt:62:3`, `64:3` | `enum HandleResult` 中的 `NotFound` 与 `Closed` 变体未被使用 | 评估并由核心路由补齐使用构造，或按设计重构简化变体 |
| `deprecated` (String to_bytes) | 2 | `engine.mbt:244:26`, `304:16` | 使用了废弃的 `String::to_bytes()` 方法 | 替换为现代标准库 `@encoding/utf8.encode(s)` |
| `deprecated` (BytesView to_bytes) | 1 | `engine.mbt:270:60` | 使用了废弃的 `BytesView::to_bytes()` | 替换为现代标准库 `to_owned()` |
| `deprecated` (Show to_string) | 1 | `server/server.mbt:35:45` | 使用了废弃的 `Show` 实现转字符串 | 采用 `Debug` 相关 API 或 `@debug.to_string` |
| `deprecated` (Map::new) | 2 | `server/server.mbt:37:41`, `44:62` | 使用了废弃的 `Map::new()` | 替换为现代推荐的 `Map([], capacity=...)` 或字面量 |
| `reserved_keyword` (`method`) | 6 | `engine_test.mbt:17, 31, 40, 65, 78`<br>`server/server.mbt:32, 41` | `method` 为 MoonBit 保留关键字，作为字段名或变量名产生告警 | 字段与变量统一重命名为 `meth` 或 `http_method` |
| `reserved_keyword` (`use`) | 4 | `server/server.mbt:12, 14, 24, 30` | `use` 为 MoonBit 保留关键字，作为回调函数名产生告警 | 重命名为 `handler`、`callback` 或 `action` |
| `unused_package` | 3 | `moon.pkg:2, 4`<br>`server/moon.pkg:4` | 引入了未使用的 `moonbitlang/async` 或 `moonbitlang/async/http` | 清理 `moon.pkg` 中多余的导入项，保持包最小依赖 |
| 其余分散告警 | 22 | `core/`、`engine.mbt`、`server/` | 类型推导多余修饰、过时辅助函数调用等 | 逐文件进行格式化与现代语法适配，消除至 0 warning |

---

## 8. 实施指南与后续步骤

1. **零警告清理**：优先由重构任务对 `engine.mbt`、`server.mbt`、`engine_test.mbt` 及各 `moon.pkg` 执行代码现代化改造，彻底消除 46 个 Warning，确保 `moon check --target native` 达到 0 warning 0 error。
2. **测试夹具与基线固化 (T-001)**：将 `http-server/` 参考仓库中的 42 个测试文件和 28 项 `common-cases` 映射入 Native 测试套件。
3. **Windows TransmitFile 传输接入 (T-031)**：在已有的静态引擎基础上，完成 Windows IOCP Overlapped TransmitFile 传输与句柄防泄漏保护。
4. **BaseURL 与 SPA 回退实现 (T-019)**：在 `core` 与 `engine` 中实现 `--base-url` 归一化与 `--spa`/`--try-files` 路由回退及互斥检查。
5. **多平台与 Actions 集成 (T-032, T-025)**：从 Windows 本机推进至 Linux/macOS 三平台持续验证。
