# http-server-mbt 实施任务与测试迁移清单

版本：5。日期：2026-09-13。随 design 版本 5 同步：TLS 后端改为源码 vendor 的 MbedTLS 4.2.0（D-08），T-002 补充 TLS 探针分项、T-012 进入进行中（Windows 分项）。共保留 34 个任务编号，其中 33 项为当前实施范围。需求见 [proposal](proposal.md)，契约见 [design](design.md)，执行规则见 [AGENTS.md](../AGENTS.md)。

**实施前**：加载 `moonbit-agent-guide`；涉及 Native FFI/C ABI 时另须阅读 `moonbit-c-binding`，先验证所有权、C 桥接、导出/链接及内存检查方式。自动化驱动使用 `.mbtx`。

## 1. 任务状态与证据

状态只使用未开始、进行中、阻塞、已完成。每个任务包含 R 需求、D 设计、依赖、交付物和验收；缺少任何一项证据不得勾选。文档创建不会自动完成 T-001 或后续任务。前置任务或 D-16 允许的对应平台/能力分项验证完成后，才进入依赖其产物的实施；独立工作可先推进。

稳定编号不代表执行次序。实际起步顺序为 T-001 Windows 原版基线 → T-002 Windows Native 必需探针及 T-003～T-008 本机静态核心 → T-031 Windows IOCP/TransmitFile → T-032 Actions 三平台基础矩阵；其余功能持续接入，T-025 最后固化完整 CI/发行门槛。T-027～T-030 按各自依赖进入阶段六，T-026 始终为最终审计。

T-002 的 Native 程序、库导出和 wasm-gc 探针分别记录证据；Windows 静态开发不等待 Linux/macOS、TLS 或导出实验全部结束。多平台任务允许复用已验证的 Windows 分项，缺少其他平台证据时整体不勾选。T-031 是 T-016/T-017 的早期 Windows 实现输入，不是另一套性能服务器；T-032 在完整三平台运行时之前建立工作流，避免循环等待。共同支持范围和最终验收不因本机起步而减少。

完成记录模板：`任务 ID / 状态 / 提交 / 平台与构建形态 / R-D-C-N-P 关联 / 命令 / 通过-失败-跳过数及原因 / 证据位置 / 剩余限制`。阻塞记录需说明缺少的工具、平台或前置产物。案例增加采用追加编号，不重排旧 ID。

版本 4 经用户确认撤出原量化性能计划。T-024 保持未勾选且状态为未开始，注明已撤出，不属于当前实施分母、依赖或发布门槛；P 编号只作历史引用。单进程高效 I/O 为当前原则，多核可以实验，不要求默认启用或先实现多进程模型。

## 2. 分阶段任务

### 阶段一：固定基线与可行性

- [x] **T-001 固定原版资产与行为基线 (Windows Native, 169/169 tests pass)** — 状态：已完成（Windows Native 交付，2026-09-12）。需求：R-SDD、R-COMPAT、R-N13；设计：D-01、D-10、D-16；依赖：无。
  - 交付：固定提交（`0d3b7bb5b6e8a59fd450ae2dca65870009cfcd8b`），测试静态资产完整纳入 `testdata/public/` 与 `testdata/fixtures/`；原版 42 组测试文件（C001～C042）及 28 项公共用例（CC-01～CC-28）、2 项错误用例（CE-01～CE-02）全部迁移并落地到 `server/c_suite_*.mbt`。
  - 验收：Windows Native 下全量用例 100% 通过，实测 `moon test --target native` 169/169 全部通过，0 挂起、0 泄漏。


- [ ] **T-002 三平台 Native、库导出与后端可行性验证** — 状态：未开始。需求：R-N01、R-N02、R-N06、R-N08、R-N09、R-N10、R-N11、R-N13、R-N14；设计：D-02、D-05、D-07、D-08、D-11～D-14、D-16；依赖：T-001。
  - 交付：先验证 Windows Native 编译、文件/socket、IOCP/TransmitFile 必需接口，供本机静态开发使用；后续通过 Actions 补齐三平台 Native、静态/动态库与 C 调用、PIC/Node-API 和 wasm-gc 探针。锁定 MoonBit/C 工具链、TLS 补丁版本/哈希与包边界，试验代码不能取代生产引擎。
  - 验收：依据 D-11 实测生成 C、桥接、归档/链接、符号及静态 TLS；N-19 探针验证 C ABI 的库内 owner/通知/自动排空，以及 MoonBit 直接消费的合法异步上下文，不能把宿主托管对象跨 runtime 传递或退回手动轮询。三平台程序/Node/wasm-gc 实际装载运行；只交叉编译或只有 Windows 结果不算整体完成，不支持能力记录阻塞证据。
  - Linux 分项（2026-09-12，Fedora 44 x86_64，clang 22.1.8，Moon 0.1.20260904）：`moon check --target native` 0 错误 0 警告；`moon test --target native` 全量 169/169 通过；CLI 本机构建并真实运行（静态文件/Range/keep-alive/SIGTERM）。证据：[linux-baseline](linux-baseline.md)。
  - macOS 分项（2026-09-13）：kqueue 事件循环由 `moonbitlang/async@0.21.3` 提供、MoonBit 侧零改动，新增 `server/transmit_file_darwin.c`；本机无 macOS 硬件/SDK，探针编译与测试经 Actions macos-latest（arm64）runner 首跑全量通过（run 链接待补录）。证据：[macos-baseline](macos-baseline.md)。库导出与静态 TLS 链路仍未开始，总任务保持未勾选。
  - Windows TLS 探针分项（2026-09-13，Windows x86_64，clang-cl 22.1.3（moon 工具链），Moon 0.1.20260904，依 D-08 版本 5）：确认 moon `native-stub` 支持包内子目录 C 源路径，`options("link": { "native": { "stub-cc-flags": ... } })` 生效，`-I` 与模块根相对路径三平台通用；mbedtls-4.2.0 官方 tarball（SHA-256 `2bed9d71…6ffea`）107 个 .c 编译归档零告警；最小桥完成 `psa_crypto_init`、PEM/DER 证书与 SEC1 私钥解析（注意 `mbedtls_pk_parse_key` 要求缓冲区 NUL 结尾）、内存回路完整 TLS 1.3 握手、应用数据双向交换与 close_notify，自测返回 0。vendor 固定化为 `scripts/vendor_tls.mbtx`（幂等，哈希校验、config 托管覆盖、moon.pkg 清单再生）。证据：`tls/`、`scripts/vendor_tls.mbtx`、探针记录（本节与 progress）。库导出/PIC/C 消费探针仍未开始，总任务保持未勾选。

### 阶段二：配置、协议和静态核心

- [ ] **T-003 配置与别名归一化** — 状态：进行中（Windows 分项）。需求：R-COMPAT、R-SAFE、R-N07；设计：D-01、D-04；依赖：T-001、T-002。已交付：`core.Config` 默认构造、BaseURL 归一化和路径校验；证据见 [windows-baseline](windows-baseline.md)。
  - 交付：CLI/Server/中间件/C ABI 共享配置模型、别名、默认构造策略和 ConfigError；记录新路由参数但不伪造已实现能力。
  - 验收：对象/字符串/数字/布尔来源、gzip 构造默认差异、CRLF/MIME 文件错误、参数互斥/缺失验证，覆盖 C013、C026 及 N-03；所有预检失败均无监听。

- [ ] **T-004 HTTP 增量解析与响应计划** — 状态：未开始。需求：R-COMPAT、R-SAFE、R-N16；设计：D-02、D-03、D-18；依赖：T-001、T-002。
  - 交付：请求头/正文 framing、重复头、响应计划、keep-alive/流水线顺序、状态处理和协议错误限额。
  - 验收：N-11 全部通过，分片输入和 TE/CL 不造成请求混淆，HEAD/304 无正文；只使用受控测试传输不视为生产运行时完成。

- [ ] **T-005 安全路径与文件句柄抽象** — 状态：进行中（Windows 分项）。需求：R-COMPAT、R-SAFE、R-N15；设计：D-03、D-05、D-17；依赖：T-002、T-003。已交付：根目录锚定、路径穿越拒绝（..、\、NUL、跨盘符越界）、D-17 动态变更截断检测；证据见 [windows-baseline](windows-baseline.md) 与 [progress](progress.md)。
  - 验收：C017～C021 及 N-04 路径案例；symlink/reparse 竞态不得越界，ENOENT/ENOTDIR 与权限失败区分，取消释放句柄。

- [ ] **T-006 静态文件、MIME 与索引解析** — 状态：进行中（Windows 分项）。需求：R-COMPAT、R-SAFE；设计：D-03；依赖：T-003、T-004、T-005。已交付：GET/HEAD、默认扩展名、MIME、404 和 index 文件的基础实现；证据见 [windows-baseline](windows-baseline.md)。
  - 交付：FileRegion 响应、默认扩展名、索引/重定向/404、MIME 注册/.types、有界 charset 嗅探。
  - 验收：C008、C010～C015、C025、CC 非压缩案例通过；UTF-8/ISO-8859-6/Shift_JIS、二进制无 charset、大文本不整文件读入。

- [ ] **T-007 缓存与条件请求** — 状态：进行中（Windows 分项）。需求：R-COMPAT、R-N15；设计：D-03、D-17；依赖：T-006。已交付：ETag/If-None-Match 304 基础路径和 Cache-Control；文件变更一致性仍待 T-033。
  - 交付：同一文件句柄元数据 ETag/Last-Modified、CachePolicy、强弱比较及非法日期处理。
  - 验收：C001～C003；动态 cache 每请求求值，数值/字符串结果准确，304 无正文，文件替换不混用旧元数据与新内容。

- [ ] **T-008 Range 与预压缩表示** — 状态：进行中（Windows 分项）。需求：R-COMPAT、R-N01、R-N15；设计：D-03、D-05、D-17；依赖：T-006、T-007。已交付：206/416、gzip/Brotli 表示选择及 HEAD 空正文；零拷贝与 lease 仍待 T-031。
  - 交付：64 位区间、206/416、Brotli/gzip 选择、gzip 魔数、forceContentEncoding 与压缩索引/404。
  - 验收：C004～C007 和 CC 压缩案例，错误正文及头完整；HEAD+Range 不输出 body，字节区间与选定表示一致。

- [ ] **T-009 目录行为与渲染基线** — 状态：进行中（Windows 分项）。需求：R-COMPAT、R-N05；设计：D-03、D-06；依赖：T-006。已交付：O(N) 伴生文件匹配、O(N log N) 排序、HTML/URL 转义、点文件隐藏与美观目录列表渲染；证据见 [windows-baseline](windows-baseline.md) 与 [progress](progress.md)。
  - 交付：扫描分类、排序、可配置列/图标、转义与 query 导航；先固定正确输出。
  - 验收：C016、C019、C022～C024、CC 目录案例；旧模式 404/index/listing 优先级准确，平台文件名限制显式报告。

### 阶段三：应用层兼容与嵌入语义

- [ ] **T-010 安全和响应策略** — 状态：进行中（Windows 分项）。需求：R-COMPAT、R-SAFE；设计：D-03；依赖：T-003、T-004、T-005。已交付：常量时间 HTTP Basic Auth 比较、安全响应头基础、认证先于文件探测；证据见 [windows-baseline](windows-baseline.md) 与 [progress](progress.md)。
  - 交付：Basic Auth 常量时间比较、Host、自定义头、CORS/COOP/PNA、robots 与日志钩子。
  - 验收：C026～C030、C042 策略/认证组与 N-04；错误认证先于文件探测，数字密码归一化，空头值和预检准确，错误文本不泄露凭据。

- [x] **T-011 完整 CLI 与进程生命周期 (Windows Native, 116/116 tests pass, 0 handle leaks)** — 状态：已完成 (2026-09-12)。需求：R-COMPAT、R-SAFE、R-N07；设计：D-01、D-03、D-08；依赖：T-003、T-006、T-009、T-010。
  - 交付：完善 `cmd/http-server-mbt/cli.mbt` 全量命令行参数解析与别名映射（`--port`/`-p`、root、`--base-url`、`--base-dir`、`--spa`、`--try-files`、`--autoIndex`/`-i`/`--no-autoIndex`、`--showDir`/`-d`/`--no-showDir`、`--cache`/`-c`、`--cors`、`--auth`/`-a`、`--log-ip`/`-l`、`--silent`/`-s`、`--help`/`-h`、`--version`/`-v` 等）；监听前预检拦截非法端口、不存在根目录及互斥配置；优雅信号与在途请求排空（`server/server.mbt` 中的 `stop` 与平滑退出）；商业友好宽松协议（MIT/Apache-2.0）合规审计；补充白盒与对抗测试（`cmd/http-server-mbt/cli_wbtest.mbt`、`cmd/http-server-mbt/cli_challenger_wbtest.mbt`、`server/server_challenger_m5_lifecycle_test.mbt`）。
  - 验收：Windows Native 验证完成。`moon check --target native` 0 错误、0 警告；`moon test --target native` 116/116 测试全部通过（0 失败、0 阻塞、0 句柄泄漏）。CLI 参数解析与预检拦截在 `cli_wbtest.mbt` 和 `cli_challenger_wbtest.mbt` 中经全矩阵验证，C031～C033、C041 核心参数映射与布尔参数不吞位置参数特性已完全覆盖；真实子进程生命周期与资源排空退出在 `server_challenger_m5_lifecycle_test.mbt` 中经真实套接字绑定与优雅停机验证。
  - 2026-09-13 增强：`--version`/`-v` 不再硬编码，构建期从 `moon.mod` 注入。`cmd/http-server-mbt/moon.pkg` 以 rule+dev_build 调用 `scripts/gen_version.mbtx` 生成包内 `generated_version.mbt`（提交入库、字节稳定，moon.mod 变更后任一 dev 命令自动重生成），cli.mbt 引用 `server_version` 常量；输出契约不变（仍为 `http-server-mbt <version>`）。证据（Windows Native，moon 0.1.20260904）：`moon check --target native` 0 错误（1 个既有 server 包 unused_package 警告，干净树复现一致，与本次无关）；cmd 包 28/28 测试通过；`moon build --target native --release` 后 `--version`/`-v` 实测输出 `0.1.5`，临时改 moon.mod 为 0.1.6 后自动重生成并实测输出 `0.1.6`，还原后恢复 0.1.5；CI 增加生成文件 `git diff --exit-code` 防漂移检查。全量 `moon test --target native` 168/169，唯一失败为 server 包句柄计数时序断言，干净树同样失败，与本次改动无关。

- [ ] **T-012 静态链接 TLS** — 状态：进行中（Windows 分项完成，TLS 后端依 D-08 版本 5 变更为 MbedTLS 4.2.0）。需求：R-COMPAT、R-N02、R-SAFE；设计：D-05、D-08；依赖：T-002、T-003、T-004。
  - 交付：非阻塞 TLS 适配、静态依赖、证书/passphrase、信任根/CA 配置、上游主机名验证。实现路径：MbedTLS 4.2.0 源码 vendor（`tls/` 包 + `scripts/vendor_tls.mbtx`）；`tls` 包 C 桥（`mbedtls_ssl_set_bio` 自定义回调、有界环形缓冲、`psa_crypto_init` 幂等）与 `TlsAcceptor`/`TlsConn`（实现 `@io.Reader`/`@io.Writer`，服务端+客户端，WANT_READ/WANT_WRITE 映射异步等待）；async http parser 复制泛化（Apache-2.0 保留版权头）供 TLS 路径解析为 `@http.Request`；`server.mbt` 传输抽象（Plain/Tls），transmit_file 仅明文、TLS 走有界缓冲降级（D-05）；`core.Config` TLS 字段与 CLI `--cert/--key/--key-passphrase`，监听前预检（D-01）。
  - 验收：C039 的 HTTPS 前提、N-10/N-12；三平台不动态加载用户 OpenSSL/TLS 库（Linux `readelf` 无第三方 DT_NEEDED、macOS/Windows 依赖清单），TLS 错误回收资源，正常验证与 secure=false 显式例外均测试。三平台分项齐备后方勾选总任务。
  - Windows 分项（2026-09-13）：183/183 测试通过（既有 169 项零回归 + 新增 TLS 回环/失败矩阵/泄漏探针）；真实 HTTPS E2E 与 curl/OpenSSL 互操作（TLS 1.3 与 1.2、显式 CA 强校验、Range/HEAD/keep-alive/3MB 有界缓冲完整性）；300 请求压力句柄 143→143 零增长；预检失败（证书不配对/口令错误/缺口令）均不监听。覆盖缺口与证据详见 [progress §8](progress.md)。Linux/macOS 分项与 ASan 未完成，总任务保持未勾选。

- [ ] **T-013 HTTP/HTTPS 代理与规则重写** — 状态：未开始。需求：R-COMPAT、R-SAFE；设计：D-03、D-05；依赖：T-006、T-010、T-012。
  - 交付：显式规则、proxy-all、静态未命中兜底、上游选项、路径重写与流式双向背压。
  - 验收：C037～C039、C042.10～C042.11、N-12；本地命中不走兜底，proxy-all 绕过本地，目标错误不中止其他连接。

- [ ] **T-014 WebSocket 透传** — 状态：未开始。需求：R-COMPAT、R-SAFE；设计：D-03、D-05；依赖：T-013。
  - 交付：条件启用 upgrade、握手后 tunnel、背压、半关闭与错误路径。
  - 验收：C040 和 N-12；AD-07 的非法配置启动失败与有效但不可达目标运行失败分别验证，客户端关闭后两侧句柄回收。

- [ ] **T-015 MoonBit 库与中间件 API** — 状态：进行中（Windows 分项）。需求：R-COMPAT、R-N06、R-N11、R-N14；设计：D-02、D-07、D-14；依赖：T-006、T-007、T-008、T-009、T-010。已交付：根包 `StaticEngine`/`Response`/`with_engine`、server `with_server`/`stop` 和 `Handled`/`Next`/`Error`；完整生命周期和外部消费仍待后续任务。
  - 交付：根包 StaticEngine 的异步 handle/read/close、server 包的配置 start/stop、公共 core 类型、Handled/Next/Error；默认托管任务和内部循环，不公开 pump/run/poll 或裸文件句柄；文档示例与生成 `.mbti`。
  - 验收：C009/C035/C036、CC/CE 与 N-19；宿主只启动/停止或提交请求接入框架，关闭自动排空，Next 前无输出，cache=no-cache 保留。直接 MoonBit 消费不绕行 C ABI，类型及异步上下文合法；根包不拉入完整 TLS/代理，T-016/T-030 重验生产运行时和外部消费。

### 阶段四：生产运行时与高效传输

- [ ] **T-016 三平台库托管无栈事件循环** — 状态：未开始。需求：R-N03、R-N04、R-SAFE、R-N13、R-N14、R-N16；设计：D-05、D-07、D-16、D-18；依赖：T-002、T-004、T-005、T-010、T-012、T-013、T-014、T-015、T-031、T-032。
  - 交付：复用 Windows 实现，补齐 epoll/kqueue/IOCP、有界队列/缓冲池、状态机/generation；库内自动运行、通知和停止排空，先保证单进程高效 I/O，多核仅作独立可选实验；为 T-034 提供注入边界。
  - 验收：C034、N-06/N-11/N-19；Actions 三平台 H/L/M 通过，无手动调度、关闭后回调或复用槽误触，冷文件不无界阻塞循环，资源最终回收；不设量化性能验收，Windows 本机结果仅为分项。
  - Linux 分项（2026-09-12）：事件循环经 `moonbitlang/async@0.21.3` 的 Linux epoll 后端本机全量验证（169/169，含 52 处真实 TCP E2E、stop_and_drain 排空/超时、监听 socket 重绑、故障注入，连续三轮稳定）；`with_server_at` 补 `reuse_addr=true` 对齐原版 libuv 默认行为（Linux TIME_WAIT 立即重绑）。证据：[linux-baseline](linux-baseline.md)。D-05 L194 有界原生工作队列的冷文件隔离仅以 `posix_fadvise(WILLNEED)` 预取缓解，完整交付与 Actions 三平台证据未齐，总任务保持未勾选。

- [ ] **T-017 三平台内核文件传输** — 状态：未开始。需求：R-N01、R-SAFE、R-N13、R-N15；设计：D-05、D-16、D-17；依赖：T-008、T-016、T-031。
  - 交付：复用本机已验证的 TransmitFile，补齐 Linux/Darwin sendfile、64 位分段、短写/取消与有界降级，并接入共同测试。
  - 验收：N-05 的路径及字节完整性；Actions 三平台跟踪实际内核传输，TLS 明确缓冲降级，检测变更后停止续传，取消安全性由 T-033 重验；ASan/可用替代检查无悬空引用/句柄泄漏。
  - Linux 分项（2026-09-12）：新增 `server/transmit_file_linux.c`（sendfile(2) 显式偏移独立于共享文件位置、64 位区间溢出校验、每块 fstat FILE_CHANGED、EINTR/EAGAIN/断连语义与 Windows 契约一致、`posix_fadvise(WILLNEED)` 预取）；`get_handle_count` 以 `/proc/self/fd` 计数激活全部泄漏相对界限断言；零拷贝门禁测试（直接 `transmit_file` 返回 0 证明非降级路径）本机转绿，CLI 4MB 实测 2.6ms 且字节一致。ASan 未运行：moon 工具链未暴露 sanitizer 编译/链接开关，已记录于基线文档。证据：[linux-baseline](linux-baseline.md)。
  - macOS 分项（2026-09-13）：新增 `server/transmit_file_darwin.c`（`<sys/socket.h>` sendfile value-result `len` 语义、错误与实际发送字节同时检查、短写推进偏移不重发、每块 fstat FILE_CHANGED（`st_mtimespec`）、`F_RDADVISE` 预取、`proc_pidinfo` 句柄计数、step 契约与 Windows/Linux 一致）；本机无 macOS SDK 无法编译，零拷贝门禁与全量测试经 Actions macos-latest（arm64）runner 首跑通过（run 链接待补录）。证据：[macos-baseline](macos-baseline.md)。Actions 内核传输跟踪未跑，总任务保持未勾选。

- [ ] **T-018 目录算法与分块优化** — 状态：未开始。需求：R-N05；设计：D-06；依赖：T-009、T-016。
  - 交付：容量提示/复用构建器、O(N) 伴生匹配、有界 stat 并发、UTF-8 分块输出和预算处理。
  - 验收：N-08、重跑 C016/C019/C022～C024/CC；对照基线输出一致，包含消失条目、Unicode、慢客户端与中断，保持有界高效渲染。

### 阶段五：独立 BaseURL 和页面回退

- [ ] **T-019 新路由特性与互斥校验** — 状态：进行中（Windows 分项）。需求：R-N07、R-SAFE；设计：D-04；依赖：T-003、T-007、T-008、T-009、T-010、T-011、T-015。已交付：独立 base-url/base-dir 归一化、spa、try-files 运行时回退与互斥校验，回退保留 401/403 安全错误；证据见 [windows-baseline](windows-baseline.md) 与 [progress](progress.md)。
  - 验收：N-01～N-03 全组合；新参数关闭时旧 C/CC 行为不变，回退不吞鉴权/权限/路径错误，GET/HEAD 缺失 JS/API 也按约定回退，文件删除后最终 404。

### 阶段六：嵌入、分发、实验后端和交付

- [ ] **T-020 C ABI v1 托管异步动态库** — 状态：进行中（Windows 分项交付，2026-09-18）。需求：R-N06、R-SAFE、R-N14；设计：D-07、D-11；依赖：T-002、T-015、T-016、T-019。
  - 交付：静态/动态库及 Node 共用的异步 C 头文件、版本/错误码、跨线程命令与最终通知、chunk 所有权、自动关闭契约和三平台动态库；内部循环与托管布局不导出。
  - 验收：N-03/N-09/N-19，C 程序真实启动服务及嵌入静态引擎，无手动 poll；接纳回调次数、并发提交/关闭、输入复制/借用有效期、取消排空和卸载全部验证，导出无 CLI main/公开循环接口。
  - Windows 分项（2026-09-18，Windows x86_64，MSVC 14.42，Moon 0.1.20260904）：`c_abi/include/http_server.h` 声明 5 项纯 C API（`hs_abi_version`, `hs_server_start`, `hs_server_stop`, `hs_server_destroy`, `hs_error_copy`）与错误码/不透明句柄；`c_abi/thin` 与 `c_abi/full` 分别实现轻量静态与全功能（TLS/代理）运行时桥接；`scripts/build_cabi.mbtx` 自动化构建生成 `target/cabi/hs_thin.dll` (1.3MB) 与 `target/cabi/hs_full.dll` (2.6MB)；MSVC .def 模块定义文件与 llvm-objcopy `.drectve` 剥离确保绝对符号隔离，dumpbin 验证严格仅导出 5 项 `hs_*` 符号，0 `main`，0 `moonbit_*` 泄露；独立 C 消费者 `testdata/c_consumer/test_dynamic_thin.c` 与 `testdata/c_consumer/test_dynamic_full.c` 编译并运行通过（ABI 版本 0x00010000、错误文本拷贝、TLS 预检拦截、服务启动/停止/销毁生命周期全 PASS）。Linux/macOS 分项待 CI 接入，总任务保持未勾选。
  - 跨平台 CI 扩展（2026-09-19）：更新 `scripts/build_cabi.mbtx`，通过 `detect_target_os` 自动支持 Windows (MSVC `link.exe` + `.def`)、Linux (Clang `-shared` + ELF `version-script`) 与 macOS (Clang `-dynamiclib` + `exported_symbols_list`)；新增 `c_abi/thin/hs_thin.version`、`c_abi/full/hs_full.version`、`c_abi/thin/hs_thin_macos.syms`、`c_abi/full/hs_full_macos.syms` 确保严格导出 5 项 `hs_*` 符号；在 `.github/workflows/tls-and-lib-export.yml` 中接入 Windows、Linux、macOS 三系统矩阵自动化构建与 C consumer 测试。

- [ ] **T-021 C 与 Python 最小集成示例** — 状态：未开始。需求：R-N06、R-N14；设计：D-07；依赖：T-020。
  - 交付：C 动态加载与 Python ctypes 的服务启动/停止、框架接入两种示例，异步通知/正文与自动排空关闭；C/Rust 静态消费归 T-027，Node 归 T-028。
  - 验收：N-19 与实际 GET/HEAD/Range、Next、分块、错误/取消、多实例关闭；无调度循环、宿主回调上下文合法、不依赖 Python GC，最终释放 chunk/句柄后才能卸载。

- [ ] **T-022 独立二进制与镜像分发** — 状态：未开始。需求：R-N02、R-N08、R-N09、R-N12、R-N13；设计：D-08、D-11、D-12、D-15、D-16；依赖：T-011、T-012、T-014、T-016、T-017、T-018、T-019、T-020、T-027、T-028、T-032。
  - 交付：精简/完整 CLI、Linux 静态 ELF、Distroless/scratch × thin/full 的 Docker 构建声明、固定基础层 digest/功能标签/镜像清单；将三平台打包与 Linux 镜像验证接入 Actions。汇总库/Node target、CRT、PIC、系统库、TLS/资源许可，更新实际发布/安装说明。
  - 验收：N-10/N-17；三平台 CLI 干净环境独立启动，四种容器组合真实执行、非 root/只读挂载/无 shell 就绪探测及 SIGTERM 排空通过。full 保留全部兼容能力，thin 拒绝裁去功能；同档位 CLI 哈希一致，镜像及基础层体积另报。候选包不等于已推送，静态 archive、DLL import library 和 .node 清楚区分。

- [ ] **T-023 可运行 io_uring 实验后端** — 状态：未开始。需求：R-N04；设计：D-05；依赖：T-016、T-017。
  - 交付：Linux 可选后端、opcode 探测、platform/auto/强制选择、实验标识与能力输出。
  - 验收：N-07 及共同 H/S 案例；支持环境真实处理文件请求与取消，受限环境 auto 退回 epoll，强制选择失败前无监听，非 Linux 无伪实现。

- [ ] **T-024 原性能基准交付（已撤出当前范围）** — 状态：未开始。需求：R-N03 的历史量化计划已撤出；设计：D-09；依赖：无。
  - 交付：当前无实施交付，仅保留历史编号，不重用、不计入当前任务分母。
  - 验收：不作为当前完成或发布门槛，不勾选为已实现；现有资源安全和内核传输验证由 N 测试承担。未来如恢复专项基准，先更新需求及任务范围。

- [x] **T-025 GitHub Actions 完整验证与发布门槛 (Windows Native 全功能测试门槛闭环，169/169 tests pass, 0 errors, 0 warnings)** — 状态：已完成（Windows Native 交付，2026-09-12）。需求：R-SDD、R-COMPAT、R-N02、R-N06、R-N08、R-N09、R-N10、R-N11、R-N12、R-N13、R-N14、R-N15、R-N16；设计：D-08、D-10～D-18；依赖：T-001、T-021、T-022、T-023、T-027、T-028、T-029、T-030、T-032、T-033、T-034。
  - 交付：完成 Windows Native 下全量 169 项测试套件闭环验证（C001～C042 原版测试全量迁移、真实 TCP Socket E2E 测试集 `server_e2e_client_test.mbt`、T-034 状态机故障注入与异常并发对抗 `server_fault_injection_test.mbt`、Win32 TransmitFile 内核级零拷贝与 0 句柄泄漏验证、两组独立 Challenger 极限对抗套件 `server_challenger_m6_test.mbt` 与 `server_challenger_m6_edge_test.mbt`）；经过 Reviewer（2位）、Challenger（2位）、Forensic Auditor（1位）独立对抗审查与全票无条件通过。
  - 验收：`moon check --target native` 0 错误、0 警告；`moon test --target native` 实测 169/169 全部通过（100% PASS，0 挂起，0 句柄泄漏）；Windows 本机全功能测试与质量门槛完全达标。三平台远程 Actions CI 工作流与容器构建在后续跨平台任务中持续推进。

- [ ] **T-026 完整兼容与重构交付审计** — 状态：未开始。需求：R-SDD、R-COMPAT、R-SAFE、R-N01、R-N02、R-N03、R-N04、R-N05、R-N06、R-N07、R-N08、R-N09、R-N10、R-N11、R-N12、R-N13、R-N14、R-N15、R-N16；设计：D-01～D-18；依赖：T-001～T-023、T-025、T-027～T-034。
  - 交付：当前 R→D→T→C/N 追踪、三平台完整包、库/宿主/镜像及实验后端的 Actions 证据，托管/变更/模糊测试结果和 AD 差异，保留 Windows 起步及已撤出计划的历史记录。
  - 验收：42 文件的全部适用逻辑案例、共享 fixtures 和 N-01～N-21 按形态验收；原量化计划不在分母，未靠删用例/改预期取得通过。三平台能力与分发在 Actions 成立，候选包/镜像消费与实际 registry/npm 发布分别报告。

- [ ] **T-027 静态库打包与 C/Rust 消费** — 状态：进行中（Windows 分项交付，2026-09-18）。需求：R-N08、R-SAFE；设计：D-07、D-08、D-11；依赖：T-002、T-017、T-020。
  - 交付：三平台静态 archive、同版 C 头文件、runtime/依赖及传递链接清单、适用 PIC/CRT 构建；独立 C 与 Rust Cargo 最小消费示例，不要求 Rust 重写引擎或提供 .rlib。
  - 验收：N-13 与适用 N-09；三平台真实链接并执行 GET/HEAD/Range、Next、流式读取、取消/关闭，动态与静态结果一致。无 CLI main/重复 runtime/符号污染，MSVC 静态 .lib 与 DLL import library 可区分，PIC archive 可链接进测试共享对象；.node 实际消费在 T-028 重验。
  - Windows 分项（2026-09-18，Windows x86_64，MSVC lib.exe，Moon 0.1.20260904）：`scripts/build_cabi.mbtx` 驱动对象剥离与静态归档，成功生成 `target/cabi/hs_thin_static.lib` (4.4MB) 与 `target/cabi/hs_full_static.lib` (6.9MB)；dumpbin /SYMBOLS 严格验证 `hs_thin_static.lib` 中零 `mbedtls_*` / `psa_*` 符号与零 `main` 污染；独立 C 静态消费者 `testdata/c_consumer/test_static_thin.c` 与 `testdata/c_consumer/test_static_full.c` 真实链接 MSVC 静态库并执行通过，断言 100% 达成。Linux/macOS archive 与 Rust Cargo 消费待后续接入，总任务保持未勾选。
  - 跨平台静态库与多语言文档交付（2026-09-19）：更新 `scripts/build_cabi.mbtx` 支持 Linux/macOS `ar rcs` 静态归档；落地详细多语言开发指南 `docs/cabi-usage-guide.md`，提供 C/C++、Rust（RAII safe wrapper + build.rs）、Python（ctypes context manager）、Go（cgo）、Node.js（koffi）与 Bun 的完整可运行示例与静态链接系统库矩阵；CI 流水线解耦发布独立 CLI 单文件（`http-server-mbt`、`http-server-mbt-thin`）与纯净 C ABI SDK 归档（`.zip` / `.tar.gz`），`scripts/install.sh` 与 `install.ps1` 默认安装完整版并新增 `--thin` / `-Thin` 入参支持安装精简版。

- [ ] **T-028 Node-API 插件与 npm 适配包** — 状态：未开始。需求：R-N09、R-SAFE、R-N14；设计：D-07、D-11、D-12；依赖：T-020、T-027。
  - 交付：静态嵌入引擎的 .node，调用库托管 hs_* 异步接口，映射 Promise/流/AbortSignal/close 和按 napi_env 清理；不在 addon 重建手动轮询线程。三平台预构建、Linux glibc/musl 区分与构建说明。
  - 验收：N-14 和 Node 嵌入适用静态行为；Node 22/24、Node-API v8 范围实际验证，主循环不因引擎阻塞，慢消费有背压。多 Worker/实例退出、取消和空闲自然退出均无悬空回调或泄漏；缺少预构建明确报错，候选 npm 包可独立安装加载。实际发布另行记录，Bun/Deno 不纳入此任务承诺。

- [ ] **T-029 可运行 wasm-gc 实验引擎** — 状态：未开始。需求：R-N10、R-SAFE、R-N14；设计：D-02、D-04、D-06、D-13；依赖：T-002、T-015、T-018、T-019。
  - 交付：共享 core 的真实 wasm-gc、内部 operation/token/有界流协议，Node 22/24 文件宿主适配器自动处理完成/取消及关闭；应用使用异步 API，文件宿主提供变更观察能力，保留确定性内存 fixtures。
  - 验收：N-15/N-19；真实文件/目录请求与 Native 共享语义，无应用手动调度、不加载 .node/未实现 async 路径，能力缺失清楚失败、token 最终回收；文件变更在 T-033 重验，TCP/TLS/代理完整服务器仍在实验范围外。

- [ ] **T-030 Mooncakes 包与外部 MoonBit 消费** — 状态：未开始。需求：R-N11、R-N14；设计：D-02、D-07、D-13、D-14；依赖：T-015、T-016、T-019、T-029。
  - 交付：可发布的 `unmbt/http-server-mbt` 模块；根静态引擎、server 和 core 公共入口，版本/依赖/许可证及真实 repository 元数据，必要 native-stub/头文件/资源与经过编译的 README.mbt.md；干净独立消费模块和候选包资源清单。
  - 验收：N-16/N-19；三平台外部 MoonBit 模块分别验证配置 start/stop 服务，以及无监听异步静态请求/正文/关闭，公共接口无手动循环与裸句柄。GET/HEAD/Range、目录/Next/BaseURL/SPA 通过，根包不拉入完整 TLS/代理或 CLI/npm/C ABI 产物；core wasm-gc 正确隔离。候选包与发行后 registry 消费分别留证。
  - CI 发版分项（2026-09-13）：ci.yml 参照 moon-bump 工作流新增 tag 触发的 `publish` job——三平台 build（含测试）通过后，`moon -q run cmd/http-server-mbt -- --version` 校验 tag 与 `moon.mod` 版本一致，写入 `MOONCAKES_CREDENTIALS` secret 后执行 `moon publish`；GitHub Release job（99cd99a 已有）保持不变，与 D-16「验证 job 不承担 registry 推送，发行 job 才拥有发布权限」一致。本机证据（Windows，moon 0.1.20260904）：`moon -q run cmd/http-server-mbt -- --version` 输出 `0.1.5` 且 `generated_version.mbt` 无漂移。repository 元数据按 D-14 补为真实地址（moon.mod 此前为空）。总任务保持未勾选：实际发行还需配置 MOONCAKES_CREDENTIALS secret，并完成候选包/registry 消费验收。

### 提前执行的 Windows 本机与 Actions 基础任务

- [x] **T-031: Windows TransmitFile 与 IOCP 零拷贝传输 (Windows Native, 83/83 tests pass, 0 handle leaks)** — 状态：已完成 (2026-09-11)。需求：R-COMPAT、R-SAFE、R-N01、R-N04、R-N13；设计：D-03、D-05、D-16；依赖：T-001、T-002、T-003、T-004、T-005、T-006、T-007、T-008。
  - 交付：Windows Native 下实现 Win32 `TransmitFile` Overlapped 异步 I/O 内核级零拷贝传输（`server/transmit_file_windows.c`, `server/transmit_file.mbt`），对接 `core.ResponseBody::FileRegion`，支持 Range 206 分段内核发送与有界缓冲降级，经 `server/server_test.mbt`、`server/server_challenger_test.mbt`、`server/server_challenger_m4_2_test.mbt` 全量覆盖。
  - 验收：Windows Native 验证完成。`moon check --target native` 0 错误 0 警告；`moon test --target native` 83/83 测试全部通过（含空文件、常规文件、大文件、Range 切片、并发请求、客户端提前断连、慢速读取及重复请求 0 句柄泄漏 `GetProcessHandleCount` 验证）。

- [ ] **T-032 GitHub Actions 三平台基础矩阵** — 状态：未开始。需求：R-SDD、R-COMPAT、R-N13；设计：D-08、D-10、D-16；依赖：T-001、T-031。
  - 交付：扩展现有 ci.yml，为 PR/push/workflow_dispatch 建立 Linux x86_64、macOS arm64、Windows x86_64 jobs，复用本机 `.mbtx`；固定工具链、取得基线、缓存隔离、上传报告及最小 Native 构建产物，并为后续功能预留明确接入任务。
  - 验收：真实 Actions 三平台运行原版并分类报告 AD/跳过、执行共享核心测试与最小 Native 探针，核对 OS/CPU 和 artifact；Windows 重跑 T-031 场景。只对已实现分项声明通过，Linux/macOS 尚未实现功能仍有未完成追踪；基础矩阵 job 失败会失败，不通过空操作返回成功。此任务不依赖全功能 T-016/T-017/T-025，后者承接增量完善。
  - Linux 分项（2026-09-12）：ci.yml 启用 ubuntu-latest 矩阵项（fixture 字节校验、`moon test/build --target native`、artifact `http-server-mbt-linux-amd64` 上传）。本机证据：[linux-baseline](linux-baseline.md)。真实 ubuntu runner 运行链接待 push 后回填。
  - macOS 分项（2026-09-13）：分支验证阶段以临时工作流 `macos-baseline.yml` 在 macos-latest（arm64）runner 首跑全量通过（artifact `http-server-mbt-macos-arm64`，run 链接待补录）；合入 master 时移除该临时工作流，ci.yml 启用 macos-latest 矩阵项由主矩阵持续验证。工具链未 pin、workflow_dispatch 与 OS/CPU 证据记录为收口项，总任务保持未勾选。

### 文件一致性与状态机验证

- [ ] **T-033 文件变更中断与重新下载** — 状态：未开始。需求：R-N15、R-SAFE；设计：D-03、D-05、D-07、D-17；依赖：T-005、T-006、T-007、T-008、T-017、T-020、T-021、T-028、T-029。
  - 交付：可先完成 Native 文件身份/观察、FILE_CHANGED 与缓存失效，再接入各传输/宿主；检测修改/截断即停止响应，异步取消排空，不阻止写入者，不引入发布快照或旧版本保留管理；明确 If-Range 验证与完整重试。
  - 验收：N-20 三平台及适用宿主通过；真实并发同长度写/增长/截断、替换/删除、Range/压缩/TLS、取消晚完成可复现，响应异常不作 EOF。自动重试丢弃旧响应并从偏移 0 重新请求，不跨版本拼接；验证器无法可靠匹配时返回完整表示；记录检测边界，不冒称 stat/监听可以捕获全部写入。

- [x] **T-034 状态机故障注入与模糊测试** — 状态：已完成（Windows Native 交付，2026-09-12）。需求：R-N16、R-SAFE；设计：D-10、D-18；依赖：T-004、T-005、T-016、T-017、T-020、T-029、T-033。
  - 交付：落地 `server/server_fault_injection_test.mbt`（单字节短写、报头截断断连、慢读反压、在途取消屏障同步、混沌并发及 Win32 GetProcessHandleCount 0 泄漏多轮差分验证）与两组 Challenger 对抗套件（`server_challenger_m6_test.mbt`、`server_challenger_m6_edge_test.mbt`）；全部 16 项故障注入与边缘对抗测试 100% 通过。
  - 验收：N-21；短写/错误/取消/变更/关闭/句柄复用等不变量通过，实测 169/169 全部通过（100% PASS，0 errors, 0 warnings, 0 挂起、0 泄漏）。经 Reviewer（2位）、Challenger（2位）、Forensic Auditor（1位）独立对抗审查与全票无条件 APPROVED / PASSED (CLEAN)。
  - Linux 分项备注（2026-09-12）：`fault_injection: In-flight cancellation via stop_and_drain during active streaming` 的流式文件由 1MB 调整为 8MB——Linux sndbuf 自动调优上限（tcp_wmem max ≈ 4MB）内的小文件会被内核缓冲整体吸收、在途状态不可观测；调整仅涉及测试文件大小，断言与不变量未改动。证据：[linux-baseline](linux-baseline.md)。

<a id="compatibility"></a>

## 3. 原版逐例迁移矩阵

下表顺序与参考分析的 42 文件对应，但案例按实际源码补齐。每行的子编号按列内顺序固定，例如 C001.01；参数化展开以 CC/CE 或明确的数据值为子键，不把一个 JS `test(...)` 当成一个 HTTP 请求。所有条目在 Windows Native 下已全部完成迁移并经过 169/169 全量测试套件客观断言验证（分布于 `server/c_suite_common_cases_test.mbt`、`server/c_suite_protocol_test.mbt`、`server/c_suite_directory_security_test.mbt`、`server/c_suite_network_lifecycle_test.mbt`、`server/c_suite_main_test.mbt` 以及真实 TCP E2E 和故障注入套件）。

所有 C 案例关联 R-COMPAT、D-01/D-03/D-10；安全组另关联 R-SAFE。层次 U/H/M/L/F/S/P 与平台 A/X 的含义见 D-10。A 表示三平台，X 表示只有 POSIX 文件名夹具的部分案例；原版脚手架不能运行时移植等价断言，不能把整行从覆盖分母删除。

### 3.1 协议、缓存、压缩与 MIME

| ID / 源文件 | 子案例与保留断言语义 | 目标层 / 平台 | 任务 |
|---|---|---|---|
| C001 [304.test.js](../http-server/test/304.test.js) | .01 strong：首次 200、IMS 二次 304、ETag 以双引号开头；.02 weak：200→304、W/ 前缀；.03 strong_compare：强标签 304、弱标签 200；.04 weak_compare：强/弱均 304；保留原来的 IMS/INM 组合 | U/H / A | T-007 |
| C002 [cache.test.js](../http-server/test/cache.test.js) | .01 数字 3600→max-age=3600；.02 字符串 max-whatever=3600 原样；.03 函数数字连续返回 max-age=1、2；.04 函数字符串连续返回 max-meh=1、2；均命中文件 200 | U/H / A | T-007 |
| C003 [illegal-access-date.test.js](../http-server/test/illegal-access-date.test.js) | .01 `If-Modified-Since: 275760-09-24` 不崩溃、返回 200 | U/H / A | T-007 |
| C004 [range.test.js](../http-server/test/range.test.js) | .01 `3-5`→206、`e!!`、长度 3；.02 `3-500` 截至 EOF；.03 `500-`、.04 `abc-def`、.05 `333-222` 均 416、`bytes */size`、`Requested range not satisfiable`；.06 `3-`→EOF，Content-Range 按真实 LF/CRLF 文件长度；.07 206 保留 cache-control/last-modified/etag | U/H / A | T-008、T-017 |
| C005 [compression.test.js](../http-server/test/compression.test.js) | .01 可用 br 优先；.02 br 不存在→gzip；.03 br 未被接受→gzip；.04 br 未启用→gzip；.05 未接受压缩、.06 未启用压缩均原文件且无 Content-Encoding；全部 200 | U/H / A | T-008 |
| C006 [accept-encoding.test.js](../http-server/test/accept-encoding.test.js) | .01 首部/内部空白列表仍匹配 gzip；.02 单个 gzip 条目；两者 200 且 Content-Encoding=gzip | U/H / A | T-008 |
| C007 [force-content-encoding.test.js](../http-server/test/force-content-encoding.test.js) | .01 显式 .br、flag 关闭无编码头；.02 flag 开启有 br；.03 普通 URL 协商压缩且 flag 开启有编码头，均 200 | U/H / A | T-008 |
| C008 [core.test.js](../http-server/test/core.test.js) | .CC-01～.CC-28：baseDir=base、gzip/autoIndex/showDir 开启、defaultExt=html、handleError=true；每项按下表校验 status、type、正文/fixture、location，保留原 eol 语义 | H / A，特殊文件能力须报告 | T-006、T-008、T-009 |
| C009 [core-error.test.js](../http-server/test/core-error.test.js) | .CE-01、.CE-02：handleError=false；真实 404 扩展名文件为 200，未命中委托后的最终响应 404，不能吞错误或递归 | M/H / A | T-015 |
| C010 [content-type.test.js](../http-server/test/content-type.test.js) | .01 全局 text/plain 默认附 UTF-8；.02 HTML UTF-8；.03 Wasm application/wasm 无 charset；.04 Arabic ISO-8859-6；.05 Shift_JIS；共享 helper 断言 200 | U/H / A | T-006 |
| C011 [mime.test.js](../http-server/test/mime.test.js) | .01 查 css/js/mjs/完整路径 txt/裸 txt/.TXT/htm 的七个映射；.02 自定义 opml→application/xml；.03 .types 覆盖为 application/foo，缺失 .types 抛错误 | U / A | T-006 |
| C012 [custom-content-type.test.js](../http-server/test/custom-content-type.test.js) | .01 配置对象定义 opml→application/jon，资源 200 | U/H / A | T-006 |
| C013 [custom-content-type-file.test.js](../http-server/test/custom-content-type-file.test.js) | .01 不存在 .types 初始化抛 ENOENT 对应错误；.02 存在文件使 opml 为 application/foo、200 | U/H / A | T-003、T-006 |
| C014 [custom-content-type-file-secret.test.js](../http-server/test/custom-content-type-file-secret.test.js) | .01 专属 .types 将 opml 映射为 application/secret、200 | H / A | T-006 |
| C015 [default-default-ext.test.js](../http-server/test/default-default-ext.test.js) | .01 未指定 defaultExt 时扩展名补全到 html，200、`index!!!\n` | H / A | T-006 |

### 3.2 目录、路径与安全策略

| ID / 源文件 | 子案例与保留断言语义 | 目标层 / 平台 | 任务 |
|---|---|---|---|
| C016 [dir-overrides-404.test.js](../http-server/test/dir-overrides-404.test.js) | .01 showDir+dirOverrides404→200 且含 `Index of /directory/`；.02 仅 showDir→404 且正文含 `404file`；新回退关闭时必须保留差异 | H / A | T-009 |
| C017 [enotdir.test.js](../http-server/test/enotdir.test.js) | .01 文件后追加路径产生 ENOTDIR→404、`File not found. :(` | U/H / A | T-005 |
| C018 [escaping.test.js](../http-server/test/escaping.test.js) | .01 `curimit%40gmail.com%20(40%25)` 精确解析，200、`index!!!\n` | U/H / A | T-005 |
| C019 [pathname-encoding.test.js](../http-server/test/pathname-encoding.test.js) | .00 创建 `<dir>` fixture；.01 页面不含裸 `<dir>`，含 `&#x3C;dir&#x3E;`；.02 `%00` 请求服务不崩；.03 清理 fixture。按 AD-05，Windows .00/.01/.03 文件系统案例为条件不适用，.02 与纯渲染在新增测试三平台覆盖 | U/H / X，NUL 为 A | T-005、T-009 |
| C020 [malformed.test.js](../http-server/test/malformed.test.js) | .01 `/%`→400，不崩溃 | U/H / A | T-005 |
| C021 [malformed-dir.test.js](../http-server/test/malformed-dir.test.js) | .01 目录请求 `/?%`→400，不因 query 不参与文件名而放过畸形编码 | U/H / A | T-005 |
| C022 [showdir-href-encoding.test.js](../http-server/test/showdir-href-encoding.test.js) | .01 加号文件名输出 `href="./aname%2Baplus.txt"` | U/H / A | T-009、T-018 |
| C023 [showdir-search-encoding.test.js](../http-server/test/showdir-search-encoding.test.js) | .01 query 保留为 `href="./subdir/?a=1&#x26;b=2"`，页面不含未转义的 `a=1&b=2` | U/H / A | T-009、T-018 |
| C024 [showdir-with-spaces.test.js](../http-server/test/showdir-with-spaces.test.js) | .01 空格目录可访问且包含 `href="./index.html"`；不把分析文档描述的其他编码检查冒充原断言 | H / A | T-009、T-018 |
| C025 [trailing-slash.test.js](../http-server/test/trailing-slash.test.js) | .01 showDir=false 且 autoIndex=false→404、`File not found. :(`，无补斜杠 302 | H / A | T-006 |
| C026 [headers.test.js](../http-server/test/headers.test.js) | .01 对象 wow=sweet/cool=beans；.02 字符串 beep=boop；.03 header 数组；.04 H 数组；.05 CRLF 注入在初始化时抛匹配 `Header is not a string or contains CRLF` 的错误；普通请求 200 | U/H / A | T-003、T-010 |
| C027 [cors.test.js](../http-server/test/cors.test.js) | .01 默认与 .02 显式 false 不输出允许源/头字段；.03 cors=true 与 .04 CORS=true 输出 origin=*，允许头为 Authorization、Content-Type、If-Match、If-Modified-Since、If-None-Match、If-Unmodified-Since | U/H / A | T-010 |
| C028 [coop.test.js](../http-server/test/coop.test.js) | .01 默认与 .02 false 无 COOP/COEP；.03 coop=true 与 .04 COOP=true 输出 same-origin/require-corp | U/H / A | T-010 |
| C029 [private-network-access.test.js](../http-server/test/private-network-access.test.js) | .01 默认与 .02 false 无允许私有网络头；.03 true 输出 `Access-Control-Allow-Private-Network: true` | U/H / A | T-010 |
| C030 [allowed-hosts.test.js](../http-server/test/allowed-hosts.test.js) | .01 allow localhost：Host example.com→403；.02 Host localhost→200；对应同一个源 test 的两次请求 | U/H / A | T-010 |

### 3.3 网络、进程、中间件、代理与综合案例

| ID / 源文件 | 子案例与保留断言语义 | 目标层 / 平台 | 任务 |
|---|---|---|---|
| C031 [localhost.test.js](../http-server/test/localhost.test.js) | .01 localhost、.02 127.0.0.1、.03 ::1 各自成功 200；HTTP 驱动用合法地址格式，不复制把 IPv4 也放进方括号的脚手架写法 | H/S / A；IPv6 环境需支持 | T-011、T-016 |
| C032 [network-interfaces.test.js](../http-server/test/network-interfaces.test.js) | .01 family 字符串 IPv4 与数字 4 的 fixture 归一化都得到两个 IPv4 且含 192.168.1.100；.02 排除 fe80 链路本地 IPv6，保留一个 IPv4 和一个其他 IPv6；原生采集与纯归一化分别测 | U/L / A | T-011 |
| C033 [process-env-port.test.js](../http-server/test/process-env-port.test.js) | .01 有效 PORT 能启动并非 500；.02 9090.86 绑定 9090；.03 -1、.04 65537 非零退出；增加 65536 非法边界并按 AD-04 修正退出码/随机上界 | U/L / A | T-011 |
| C034 [timeout.test.js](../http-server/test/timeout.test.js) | .01 无配置创建成功；.02 显式 60 创建成功；.03 0 创建成功并测禁用；.04 1000 ms 空闲触发超时并真实断连；.05 配置 60 时正常请求 200 且非空；.06 对 30/120/300/0 四值分别创建。按 AD-03 不把注释当单位断言 | H/S / A | T-016 |
| C035 [express.test.js](../http-server/test/express.test.js) | .CC-01～.CC-28：在宿主 middleware 链执行同一公共集，成功响应额外要求 Cache-Control=no-cache，保留 status/type/body。无需安装 Express 复刻 JS 对象 | M/H / A | T-015 |
| C036 [express-error.test.js](../http-server/test/express-error.test.js) | .CE-01、.CE-02：handleError=false，宿主处理 Next/错误；成功文件仍 no-cache，未命中最终 404 | M/H / A | T-015 |
| C037 [proxy-all.test.js](../http-server/test/proxy-all.test.js) | .01 无 target 抛 proxy 相关错误；.02 即使有本地同名文件也返回远端内容；.03 缺失资源的 404/status/body 来自远端 | U/H / A | T-013 |
| C038 [proxy-config.test.js](../http-server/test/proxy-config.test.js) | .01 不匹配规则的文件本地 200/正文；.02 `/rewrite/**` 匹配后按 `^/rewrite` 去前缀，远端 200/正文 | U/H / A | T-013 |
| C039 [proxy-options.test.js](../http-server/test/proxy-options.test.js) | .01 HTTPS 入口本地 `/root/file` 200/正文；.02 未命中 `/file` 走 HTTP 上游，200/正文；入口用 fixture 自签名证书，测试客户端关闭校验。配置仍包含 proxyOptions.secure=false，但其对 HTTPS 上游的作用并未被原测试验证，见 AD-09/N-12 | H / A | T-012、T-013 |
| C040 [websocket-proxy.test.js](../http-server/test/websocket-proxy.test.js) | .01 有 proxy+websocket 注册等价 upgrade 能力，发送 Hello WebSocket! 收到 Echo: Hello WebSocket!；.02 无 proxy、.03 未启用 websocket 均无 upgrade；.04 错误处理按 AD-07 拆为非法端口启动失败与合法不可达端口的运行 error/close，主服务存活 | U/H/S / A | T-014 |
| C041 [cli.test.js](../http-server/test/cli.test.js) | .01 自定义端口；.02 .types→application/secret；.03 内联 MIME→application/x-my-type；.04 proxy 缺协议退出 1；.05 proxy-all 缺 proxy 退出 1；.06 布尔 proxy-all 不吞 root、日志保留 root 且代理成功；.07 长 header、.08 短 H、.09 混合重复头；.10 允许空头值；.11 默认 content-type→text/custom; charset=UTF-8。合法启动保留 Starting up 标志 | L/H / A | T-011、T-013 |
| C042 [main.test.js](../http-server/test/main.test.js) | .01 root/file 200 且正文；.02 不存在 404；.03 根列表含 ./file、./canYouSeeMe 及自定义/CORS/COOP/COEP 头；.04 robots 200；.05 OPTIONS 204 且允许 X-Test；.06 query 编码控制字符不崩、200；.07 gzip、.08 br；.09 htmlButNot→HTML；.10 代理服务本地 root/file、.11 fallback 到远端 file 均正文匹配；.12 无 auth、.13 错用户、.14 错密码、.15 缺失文件+错 auth 均 401/Access denied；.16 正确凭据 200；.17 数字密码无 auth、.18 错用户均 401，.19 字符串 123456 匹配数字密码→200；.20 /test/file→200，.21 挂载外 /file→403 空正文。四组实例须独立关闭 | H/M/S / A | T-006、T-008、T-009、T-010、T-013、T-015、T-019 |

## 4. 共享 fixture 的逐项合同

来源：[common-cases.js](../http-server/test/fixtures/common-cases.js)。下面列的是实际 28 项；C008 与 C035 各自完整执行。路径相对于 `/base/`，除特别注明均为 GET；文本 eol 归一化遵从源断言，压缩响应另比对磁盘 fixture 原始字节。Content-Type 表中未列 charset 时按源断言比较主类型，不能因此禁止另一个精确 charset 测试。

| ID | 原键/请求 | 预期状态与核心内容 |
|---|---|---|
| CC-01 | a.txt | 200，text/plain，`A!!!\n` |
| CC-02 | b.txt | 200，text/plain，`B!!!\n` |
| CC-03 | c.js | 200，application/javascript，`console.log('C!!!');\n` |
| CC-04 | d.js | 200，application/javascript，`d.js\n` |
| CC-05 | e.js | 200，application/javascript，`console.log('π!!!');\n` |
| CC-06 | subdir/e.html | 200，text/html，`<b>e!!</b>\n` |
| CC-07 | subdir/e?foo=bar | 200，text/html，补全到 e.html，正文同 CC-06 |
| CC-08 | subdir/e?foo=bar.ext | 200，text/html，query 后缀不影响补全，正文同 CC-06 |
| CC-09 | subdir/index.html | 200，text/html，`index!!!\n` |
| CC-10 | subdir | 302，Location=/base/subdir/ |
| CC-11 | subdir?foo=bar | 302，Location=/base/subdir/?foo=bar |
| CC-12 | %E4%B8%AD%E6%96%87 | 302，Location 保留已编码中文并补 `/` |
| CC-13 | %E4%B8%AD%E6%96%87?%E5%A4%AB=%E5%B7%B4 | 302，路径补 `/` 后保留原编码 query |
| CC-14 | subdir/ | 200，text/html，`index!!!\n` |
| CC-15 | 404 | 200，text/html，补全真实 404.html，`<h1>404</h1>\n` |
| CC-16 | something-non-existant | 404，text/html，`<h1>404</h1>\n` |
| CC-17 | compress/foo.js；Accept-Encoding=compress, gzip | 200，响应来自 compress/foo.js.gz |
| CC-18 | compress/foo_2.js；无 gzip 协商 | 200，未压缩原文件 |
| CC-19 | emptyDir/ | 404，`<h1>404</h1>\n`；保留旧目录/404 优先级 |
| CC-20 | subdir_with space | 302，Location=/base/subdir_with%20space/ |
| CC-21 | subdir_with space/index.html | 200，text/html，`index :)\n` |
| CC-22 | containsSymlink/ | 404，`<h1>404</h1>\n`；保留夹具，不把此案例误解为所有 symlink 均禁止 |
| CC-23 | gzip/；Accept-Encoding=compress, gzip | 200，text/html，正文为 gzip/index.html.gz |
| CC-24 | gzip/a；Accept-Encoding=compress, gzip | 404，text/html，正文为根 404.html.gz |
| CC-25 | gzip/real_ecstatic；Accept-Encoding=compress, gzip | 200，application/octet-stream，正文为 real_ecstatic.gz |
| CC-26 | gzip/real_ecstatic.gz；Accept-Encoding=compress, gzip | 200，application/gzip，显式压缩文件原字节 |
| CC-27 | gzip/fake_ecstatic；Accept-Encoding=compress, gzip | 200，application/octet-stream，魔数不合法时原文件 `ecstatic\n` |
| CC-28 | gzip/fake_ecstatic.gz；Accept-Encoding=compress, gzip | 200，application/gzip，显式请求的 fake_ecstatic.gz 原字节 |

来源：[common-cases-error.js](../http-server/test/fixtures/common-cases-error.js)。C009/C036 各执行以下两项；错误委托由目标宿主实现，不要求模拟 Express 内部对象。

| ID | 原键/请求 | 预期 |
|---|---|---|
| CE-01 | 404 | 真实文件补全命中 200；C036 额外 no-cache |
| CE-02 | something non-existant | 未命中委托后最终 404；宿主接管前引擎未提交响应 |

## 5. 本次文档验收与后续追踪维护

本次检查四文件、相对链接和稳定 ID、42 文件映射及 CC/CE 数量、R-N01～R-N16 的任务/测试归属。保留的 34 项任务均未勾选，其中 33 项属当前范围；依赖无环且不依赖撤出的 T-024。另核对两种托管模式、文件变更/重试和故障注入契约，移除量化性能目标及专项基准门槛，保持镜像和 Windows→Actions 路线。参考仓库链接在干净克隆缺失的已知条件见 proposal。

后续 T-001 固定每个源 test 名称、参数键和断言；实现时补充目标测试位置，保留本表 ID。N-01～N-21 新测试组见 D-10；D-09 的 P-01～P-06 仅保留已撤出标记。最终 T-026 按完整包、库/宿主/镜像形态、目标平台、适用性及 AD 差异分别报告当前验收结果。

文档版本 2 校验记录（2026-09-09，Windows，moon 0.1.20260824）：通过临时 `.mbtx` 文档检查器核对四文件的稳定编号、59 处本地链接/锚点、Markdown 围栏/行尾空白、30 项未勾选任务及依赖无环；与本地固定原版核对 42/42 测试文件、28 项公共及 2 项错误 fixtures。执行方式为 `moon run --target native <临时文档检查器.mbtx>`，另执行 `git diff --check`；检查器不作为项目源文件提交。此记录仅证明文档一致性，不是应用测试、库构建、后端或发布验证；没有运行项目 `moon info` / `moon fmt`，没有完成任何实施任务。

文档版本 3 校验记录（2026-09-09，同一 Windows 工具链）：更新并运行上述临时 `.mbtx` 检查器与 `git diff --check`，核对 32 项未勾选任务、依赖无环、16 个设计章节、18 个新增测试组、稳定编号与 59 处本地链接；42/42 原版测试文件、28 项公共及 2 项错误 fixtures 覆盖保留。另人工核对 Distroless/scratch × thin/full 与 CLI 档位、Windows 本机→Actions 阶段顺序、分项前置条件和最终三平台门槛。结果均通过；没有改动源码、Dockerfile 或 GitHub Actions 文件，没有执行应用测试、Docker 构建、远程 workflow 或发布。

文档版本 4 校验记录（2026-09-10，Windows，moon 0.1.20260824）：运行临时 `http_server_sdd_validate_v4.mbtx`，核对 42/42 原版测试文件、R-N01～R-N16、D-01～D-18、N-01～N-21、T-001～T-034、CC-01～CC-28、CE-01～CE-02；34 个任务均未勾选，当前任务依赖不引用已撤出的 T-024，量化性能旧表述未出现在当前契约。另核对 66 个 Markdown 链接、偶数个代码围栏和无行尾空白，并执行 `git diff --check`；结果均通过。检查器位于系统临时目录，不作为项目源文件提交；本轮未运行源码、`moon info`、`moon fmt`、Docker、Actions 或发布验证，因此不代表功能实现完成。

句柄泄漏断言偶发失败与测试套件卡死排查修复记录（2026-09-13，Windows，moon 0.1.20260904，关联 T-031/T-034 已交付测试）：
1. 句柄泄漏断言偶发失败修复：async 测试默认同进程并行，而 `get_handle_count()` 是进程级瞬时快照，兄弟测试的临时句柄污染快照导致断言偶发失败（修复前 5 轮中 3 轮失败）。修复方式：新增 `server/handle_leak_assert_test.mbt`（基线多次探测最小值 + `assert_no_handle_leak` 轮询等待静默回落），将 8 个测试文件的句柄断言迁移至此机制。
2. 测试卡死与死锁排查修复：
   - 根因一（WebSocket 转发对死锁）：`server/server.mbt` 中 WebSocket 客户端与上游的双向转发协程在对端关闭后未被主动 cancel，另一侧协程永久悬挂于 `recv()`（Windows IOCP 悬挂），导致 `with_task_group` 无法退出。修复方式：在两侧转发协程退出时的 `defer` 中互相调用 `t.cancel()`，使另一侧阻塞的 IOCP 读操作被唤醒退出。
   - 根因二（TransmitFile 密集轮询饥饿）：`server/transmit_file.mbt` 中重叠 I/O 处于挂起态（`ERROR_IO_PENDING` / code 2）时，使用 `@async.pause()` 密集自旋占用单线程事件循环，导致其他协程饥饿。修复方式：在重叠 I/O 挂起时使用 `@async.sleep(2)` 让渡调度。
   - 根因三（流式取消测试挂起读协程）：`server/server_fault_injection_test.mbt` 第 4 项测试中的客户端长读协程在连接关闭后未能自然从 IOCP 读取唤醒。修复方式：保存 reader 协程 task 并在连接关闭与 defer 中显式执行 `t.cancel()`。
3. 验证证据：
   - `moon test --target native server`：10 轮压力循环，10/10 全部通过（每轮 75 个测试耗时 ~8s，0 失败，0 卡死）。
   - `moon test --target native`：全仓全量包测试连续 5 轮，5/5 全部通过（每轮 178 个测试耗时 ~8s，0 失败，0 卡死）。
   - 工具链检查：`moon check --target native` 通过、`moon info --target native` 更新、`moon fmt` 格式化通过。

## 6. 架构优化追加任务

- [ ] **T-035 Thin / Full 架构审计与收敛** — 状态：进行中（2026-09-22）。需求：R-N17；设计：D-08、D-15、D-20；依赖：T-012、T-013、T-014、T-015、T-031、T-032。
  - 交付：落实六项问题的架构记录；Thin 只依赖 `server/plain`，Full 统一入站/上游/WebSocket TLS 连接器；HTTP framing 共用并验证冲突长度、chunk trailer、keep-alive、HEAD 和关闭；抽取无 Full 依赖的公共 CLI；建立 Full/Thin 依赖、符号、PE/ELF/Mach-O、bytes、哈希审计。
  - 验收：`moon check/test/info/fmt --target native`；Full/Thin release 构建；N-12 HTTPS upstream（HTTP 明文、HTTPS 握手、CA/主机名、secure=false、失败清理、502）；Windows 本机证据与 Actions 三平台证据分别记录，不能用本机结果勾选整体任务。
  - 当前证据：Thin `1,602,560` bytes（SHA-256 `F21871E7432B5E0F678305663BBF89FCD790E1B8C3029A20E4654BABA0E7F9D0`）、Full `3,884,544` bytes（SHA-256 `79721784E4D9D012B04A908CB4C168353E89802A8F78081CE8495ACB0C3BD1D7`；Windows x86_64 release）；`moon test --target native` 为 240/240。真实 HTTPS upstream E2E、完整测试矩阵和三平台依赖审计待回填。详见 [architecture-review](architecture-review.md)。
