# 项目阶段进度与任务接续指南

> 记录日期：2026-09-12  
> 当前状态：**Milestone 1、2、3、4、5、6 全部完成！Milestone 6 原版全量测试迁移（C001～C042、CC-01～CC-28、CE-01～CE-02）、真实 TCP E2E、状态机故障注入、C040 WebSocket 双向异步代理与生命周期闭环已全部达成并通过审查。经 Reviewer（2位）、Challenger（2位）、Forensic Auditor（1位）独立审查审计，全票无条件 APPROVED / PASSED (CLEAN)**。  
> 编译器状态：`moon check --target native` **0 错误、0 警告**。  
> 测试状态：`moon test --target native` **169/169 全部 PASS，0 FAIL，0 挂起，0 句柄泄漏**。

---

## 1. 里程碑完成情况总览

| 里程碑 | 名称与范围 | 状态 | 交付物与测试集 |
| :--- | :--- | :---: | :--- |
| **M1** | **警告消除与干净基线** | **已完成 (CLEAN)** | 彻底根除代码中所有 46 个编译器告警（保留字冲突、`deprecated` API、冗余修饰符等），生成规范 `.mbti` 接口，格式化全量代码。 |
| **M2** | **核心协议、MIME、安全与配置** | **已完成 (PASS)** | 模块化解耦 `core/` 包；实现 ETag/304 缓存、Range 206/416、MIME 字典与 `.types` 解析、目录穿越/越界防御、常量时间 Basic Auth、BaseURL/BaseDir 路径挂载归一化。覆盖 30 个单元与对抗测试。 |
| **M3** | **Engine 业务特性与路由回退** | **已完成 (PASS)** | 落地全部 9 项特性：HTTP/1.1 GET/HEAD 分发、`.br`/`.gz` 预压缩协商、`forceContentEncoding`、目录探测与 302 重定向、美观 HTML 目录列表视图生成、SPA 与 try-files 兜底（严格保留 401/403）、D-17 文件变更截断检测、`ResponseBody` 零拷贝抽象。全量测试提升至 46/46。 |
| **M4** | **Windows Native TransmitFile 与 IOCP 零拷贝** | **已完成 (PASS)** | Win32 `TransmitFile` Overlapped 异步 I/O 内核级静态大文件与 Range 区间发送；有界缓冲降级保护；断连取消与防句柄泄漏机制。经 Reviewer、Challenger 与 Auditor 门禁审查，83/83 测试通过，多次请求 0 句柄泄漏。 |
| **M5** | **CLI 完整性、生命周期与架构规范** | **已完成 (PASS)** | 完善 `cmd/http-server-mbt/` 全量命令行参数解析（`--port`/`-p`、root、`--base-url`、`--base-dir`、`--spa`、`--try-files`、`--autoIndex`/`-i`/`--no-autoIndex`、`--showDir`/`-d`/`--no-showDir`、`--cache`/`-c`、`--cors`、`--auth`/`-a`、`--log-ip`/`-l`、`--silent`/`-s`、`--help`/`-h`、`--version`/`-v` 等）；监听前参数校验与冲突预检；跨平台优雅停机与在途请求排空；MIT/Apache-2.0 商业宽松许可合规；经 Reviewer、Challenger 与 Auditor 全票无条件通过，全量测试提升至 116/116 全部通过。 |
| **M6** | **原版全量测试套件迁移与对抗加固** | **已完成 (ALL PASS & AUDITED)** | 原版逐例迁移矩阵（C001～C042 及 CC-01～CC-28、CE-01～CE-02）全部落地；真实 TCP Socket 客户端 E2E 测试集（`server_e2e_client_test.mbt`）、T-034 状态机故障注入（`server_fault_injection_test.mbt`）、C040 WebSocket 双向转发及生命周期全部调优通过；两组独立 Challenger 对抗套件（`server_challenger_m6_test.mbt`、`server_challenger_m6_edge_test.mbt`）全部通过；多方门禁全票 APPROVED，全量测试达到 169/169 100% 通过。 |

---

## 2. 核心架构与模块清单

```text
http-server-mbt/
├── core/                                # 纯逻辑核心层（无平台 I/O 依赖，支持 Native & wasm-gc）
│   ├── cache.mbt                        # ETag 强弱比较、If-None-Match、If-Modified-Since、Cache-Control
│   ├── config.mbt                       # 服务配置模型、默认值构造与参数互斥预检
│   ├── core.mbt                         # Request / Response / ResponseBody (Empty, Bytes, FileRegion)
│   ├── mime.mbt                         # 标准 MIME 字典表、动态 .types 解析器与扩展名嗅探
│   ├── range.mbt                        # 字节 Range 解析 (bytes=start-end) 与 Content-Range 格式化
│   ├── routing.mbt                      # BaseURL / BaseDir 挂载前缀归一化与 SPA 回退配置
│   ├── security.mbt                     # 目录穿越防御 (.. / \ / NUL)、常量时间 Basic Auth
│   ├── core_test.mbt                    # Core 基础单元测试
│   ├── routing_config_adversarial_test.mbt # 路由与配置对抗测试
│   ├── security_auth_range_adversarial_test.mbt # 安全、认证与 Range 对抗测试
│   └── moon.pkg                         # 包声明
├── engine.mbt                           # 根包静态文件引擎 (StaticEngine)
│   ├── StaticEngine::handle             # 统一请求分发 (安全前检 -> 目录重定向 -> 索引 -> 兜底 -> 协商)
│   ├── 预压缩内容协商                    # Brotli (.br) 优先、gzip (.gz 带有 0x1F 0x8B 校验)
│   ├── 目录列表生成                      # O(N) 伴生文件去重、O(N log N) 排序、HTML/URL 转义、点文件隐藏
│   ├── 路由回退                         # SPA (--spa) 与 try-files (--try-files <file>) 优雅回退 (保留 401/403)
│   └── D-17 文件变更检测                # 在途文件长度检测 (FILE_CHANGED 立即终止)
├── engine_test.mbt                      # Engine 业务与路由全量集成测试 (18 个测试)
├── server/                              # 服务承载层
│   ├── server.mbt                       # 基于 moonbitlang/async/http 的 Native 监听与生命周期 stop/with_server/WebSocket proxy
│   ├── transmit_file.mbt                # Windows TransmitFile FFI 与异步调度
│   ├── transmit_file_windows.c          # Win32 TransmitFile / Overlapped I/O C 实现 (100ms 超时防悬挂)
│   ├── server_test.mbt                  # 服务层基础测试与句柄泄漏基线 (10 tests)
│   ├── server_challenger_test.mbt       # 零拷贝与大文件对抗测试 (11 tests)
│   ├── server_challenger_m4_2_test.mbt  # 句柄泄漏与异常断连深度对抗测试 (5 tests)
│   ├── server_challenger_m5_lifecycle_test.mbt # M5 进程生命周期与优雅排空对抗测试 (5 tests)
│   ├── server_challenger_m6_test.mbt    # M6 对抗套件 1: 短写、截断风暴、Slowloris、高并发突发 (5 tests)
│   ├── server_challenger_m6_edge_test.mbt # M6 对抗套件 2: 流式排空取消、极速断连、Range 边界攻击、循环压测 (4 tests)
│   ├── server_e2e_client_test.mbt       # M6 真实 TCP Socket 客户端端到端集成测试 (6 tests)
│   ├── server_fault_injection_test.mbt  # M6 T-034 状态机故障注入与并发对抗测试 (7 tests)
│   ├── c_suite_common_cases_test.mbt    # M6 原版公共测试矩阵 CC-01~28, CE-01~02, C008/009/035/036
│   ├── c_suite_protocol_test.mbt        # M6 原版协议测试矩阵 C001~C007, C010~C015
│   ├── c_suite_directory_security_test.mbt # M6 原版目录与安全矩阵 C016~C030
│   ├── c_suite_network_lifecycle_test.mbt # M6 原版网络与生命周期矩阵 C031~C034, C037, C040
│   ├── c_suite_main_test.mbt            # M6 原版综合场景测试 C042
│   └── moon.pkg
├── cmd/http-server-mbt/                 # 命令行可执行入口
│   ├── main.mbt                         # CLI 主入口与服务生命周期调度
│   ├── cli.mbt                          # CLI 参数解析、默认值、别名与预检校验
│   ├── cli_wbtest.mbt                   # CLI 白盒单元测试 (参数矩阵、非法输入拦截等)
│   ├── cli_challenger_wbtest.mbt        # 对抗性 CLI 白盒测试 (极端边界与互斥校验)
│   └── moon.pkg
├── testdata/                            # 测试静态资产与 Fixtures (纯宽松开源资产)
│   ├── public/                          # 原版测试用例映射目录 (html, js, txt, gz, br, 特殊路径等)
│   └── fixtures/                        # 原版测试固定根目录
├── docs/                                # 项目规划、设计、任务与进度文档
│   ├── proposal.md                      # 重构提案与需求追踪 (R-N01 ~ R-N16)
│   ├── design.md                        # 架构与行为设计契约 (D-01 ~ D-18)
│   ├── tasks.md                         # 34 项实施任务与逐例测试迁移矩阵 (C001 ~ C042)
│   ├── windows-baseline.md              # Windows 原生基线与执行证据记录
│   └── progress.md                      # 本文档：阶段进度与任务接续指南
└── .agents/                             # 多 Agent 协同元数据、审查记录与状态库
```

---

## 3. 本地验证证据（可随时复现）

在 Windows PowerShell 下执行以下验证命令：

```powershell
# 1. 验证编译与类型检查（必须保持 0 错误、0 警告）
moon check --target native

# 2. 执行全量单元与集成测试（实测 169/169 全部通过，0 挂起、0 句柄泄漏）
moon test --target native

# 3. 更新并校验公开接口描述文件
moon info --target native

# 4. 代码格式化检查
moon fmt
```

实测输出证据：
- `moon check --target native`：`Finished. moon: ran 5 tasks, now up to date`（**0 错误、0 警告**）。
- `moon test --target native`：`Total tests: 169, passed: 169, failed: 0`（**100% PASS**）。
- 原版用例迁移覆盖验证：`c_suite_common_cases_test.mbt`、`c_suite_protocol_test.mbt`、`c_suite_directory_security_test.mbt`、`c_suite_network_lifecycle_test.mbt`、`c_suite_main_test.mbt` 完整落地 C001～C042 及 CC-01～CC-28、CE-01～CE-02。
- 真实 E2E 套接字测试验证：`server/server_e2e_client_test.mbt` 经真实 TCP 握手、HTTP/1.1 Wire-level 报文解析、HEAD/GET/OPTIONS 及 Keep-Alive 验证 100% PASS。
- 状态机故障注入验证：`server/server_fault_injection_test.mbt` 经单字节短写、报头截断断连、慢读反压、在途取消排空屏障同步、混沌并发与 0 句柄泄漏差分测试，无死锁、无 Socket/文件句柄泄漏。
- 许可合规：全量新增测试资产与测试代码均严格遵循 MIT/Apache-2.0 商业友好协议。

---

## 4. Milestone 6 审查与对抗闭环总结

Milestone 6 经多角色独立深度交叉复审与对抗挑战，全部达成全票无条件 APPROVED / PASSED (CLEAN) 终审裁决（Gate Result: **PASS**）：
1. **Reviewer 1 (`reviewer_m6_1_gen3`)**: **APPROVE**  
   - 验证了 C034 空闲超时真实 1000ms 断连（`.04`）、C040 WebSocket 代理升级与错误隔离（`.01～.04`）、故障注入屏障防死锁同步及纯 HTML `<dir>` 转义。
2. **Reviewer 2 (`reviewer_m6_2_gen3`)**: **APPROVE**  
   - 验证了 169 个测试全量 100% 通过、0 告警 0 错误、接口 `.mbti` 一致性与 MoonBit 2026 编码规范。
3. **Challenger 1 (`challenger_m6_1_gen3`)**: **APPROVE**  
   - 验证了短写分片、截断风暴、Slowloris 零拷贝背压、高并发突发与循环无句柄增长 5 项极限压测套件。
4. **Challenger 2 (`challenger_m6_2_gen3`)**: **APPROVE**  
   - 验证了流式排空取消、极速断连、Range 边界攻击与跨周期循环压测 4 项极端边缘套件。
5. **Forensic Auditor (`auditor_m6_1_gen3`)**: **PASSED (CLEAN)**  
   - 审计确认 0 GPL/AGPL 污染、0 假实现/硬编码打桩、Win32 `TransmitFile` / IOCP 真实集成与 0 句柄泄漏。

---

## 5. 门禁闭环与终审归档状态

当前代码库已稳定就绪，所有 M1～M6 承诺任务与质量门禁均已彻底闭环：
- 编译与类型状态：`moon check --target native` **0 错误、0 警告**。
- 接口与代码规范：`moon info --target native` 与 `moon fmt` 保持完全规范一致。
- 测试套件状态：`moon test --target native` 实测 **169/169 全部通过（100% PASS，0 挂起，0 句柄泄漏）**。
- 审查审计门禁：Reviewer（2位）、Challenger（2位）、Forensic Auditor（1位）全票无条件 APPROVED / PASSED (CLEAN)，Gate Status: PASS。
- 终审完成：独立第三方 Victory Auditor 已完成三阶段法医审计，出具 `VICTORY CONFIRMED`，并在本地生成终审提交 `fc0a9ba`。

---

## 6. 相比原版 http-server 的核心重构与拓展能力

本项目基于 MoonBit 对经典 Node.js 版 `http-party/http-server`（基线 commit `0d3b7bb5`）进行了底层体系级的现代重构与多项重要拓展：

1. **内核级异步零拷贝传输（Win32 TransmitFile + IOCP）**：
   - *原版*：依赖 Node.js/V8 Stream 管道与 libuv，每次文件下发均在用户态 Buffer 产生内存拷贝并受 GC 压力与碎片化干扰。
   - *拓展*：在 Windows Native 下直接接入 Win32 `TransmitFile` + Overlapped I/O，静态文件与 Range 区间完全由操作系统内核 DMA 传输至网络套接字，显著降低 CPU 占用与上下文切换；具备 100ms 超时防悬挂与自动有界缓冲降级保护。
2. **深度路由回退与安全状态隔离（Enhanced SPA & try-files）**：
   - *原版*：仅支持粗粒度的 `--spa`（404 时将请求粗暴重写为 `index.html`），可能意外掩盖重要鉴权与越界错误。
   - *拓展*：不仅支持 `--spa`，还新增 `--try-files <file>` 精确指定回退文件；并在核心路由状态机中设立安全屏障，**严格保留 401（未授权）与 403（禁止访问）**，坚决不进行 SPA 回退覆盖；支持 `--base-url` 与 `--base-dir` 灵活挂载前缀归一化。
3. **智能预压缩协商与内容完整性校验（Smart Pre-compression & Magic Check）**：
   - *原版*：仅按后缀探测 `.gz` / `.br` 是否存在，不检查压缩文件实际内容是否合法损坏。
   - *拓展*：支持 Brotli (`.br`) 与 gzip (`.gz`) 双算法协商并优先选择最高效的 Brotli；内建 gzip `0x1F 0x8B` 二进制魔数校验，杜绝伪劣残卷错误下发；支持 `forceContentEncoding` 强制头输出与原文件优雅降级直出。
4. **原生全双工 WebSocket 异步双向代理（WebSocket Proxy Lifecycle）**：
   - *原版*：依赖第三方 `http-proxy` 库，在连接异常中断或反向代理超时时存在长连接挂死与句柄泄漏风险。
   - *拓展*：在 Native 异步运行时中原生实现 `Upgrade: websocket` 协议升级握手与双向透明流管道转发；具备独立连接生命周期隔离与异常断连自动排空，彻底消除 IOCP 读阻塞死锁，高并发压测下保持 **0 句柄泄漏**。
5. **D-17 运行时在途文件变更检测与防护（Dynamic File Mutation Defense）**：
   - *原版*：静态分发期间缺乏对外部文件变动的保护，文件若被原地截断或重写，客户端会接收到不可预知的损坏残卷或版本拼接。
   - *拓展*：严格遵循 D-17 规范，服务端绑定已打开文件句柄，一旦探测到在途传输文件被外部篡改或截断（`FILE_CHANGED`），立即终止响应并自动取消排空，确保静态分发的数据强一致性。
6. **T-034 状态机故障注入抗攻击加固（Fault-Tolerant State Machine）**：
   - *原版*：缺乏对单字节短写切片、畸形报头截断风暴、Slowloris 慢读反压等网络恶劣环境的系统性对抗测试。
   - *拓展*：专门设计 T-034 故障注入套件与 32 组极端 Range 边界对抗攻击套件；结合 `stop_and_drain` 优雅停机屏障排空与 Win32 `GetProcessHandleCount` 实时句柄监控，验证系统在极限高压下无死锁、无挂起、跨周期无句柄泄漏。
7. **纯原生单文件二进制与零运行时开销（Zero Runtime Dependencies）**：
   - *原版*：运行必须依赖 Node.js 庞大环境及数百个 `node_modules` 依赖包，分发与容器镜像体积庞大，冷启动慢。
   - *拓展*：MoonBit 纯 Native 静态编译，单个独立可执行文件直接拷贝即可运行，零外部依赖，毫秒级冷启动，常驻内存仅数 MB。

---

## 7. 多平台支持现状与后续接续路线 (Linux & macOS 待完成)

按照架构设计契约（D-16）与任务规划（`docs/tasks.md`），多平台支持的推进节奏与当前状态如下：

| 平台与架构 | 当前状态 | 核心能力基线 | 后续接续里程碑与任务 |
| :--- | :---: | :--- | :--- |
| **Windows x86_64** | **✅ 已完成并闭环 (Verified)** | Win32 `TransmitFile` + IOCP Overlapped 内核零拷贝、全量 CLI 参数、169/169 测试 100% 通过、0 警告、0 句柄泄漏、独立 Victory Audit 验收通过 | Milestone 1 ～ Milestone 6 已全面闭环交付 |
| **Linux x86_64** | **🔶 本机分项完成 (Local Verified)** | `sendfile(2)` 显式偏移内核零拷贝 + `epoll` 事件循环（moonbitlang/async 后端）、fstat `FILE_CHANGED` 检测、`/proc/self/fd` 句柄泄漏监控、`reuse_addr` 立即重绑、169/169 测试本机 100% 通过（连续三轮）、CLI 大文件 4MB/2.6ms 字节一致；证据见 [linux-baseline](linux-baseline.md) | 已对接 Milestone 7 的 **T-032** Linux 分项（ubuntu runner 运行待回填）、**T-002/T-016/T-017** Linux 分项（2026-09-12）；待 **T-022**（musl 静态 ELF 与 Distroless 镜像）、**T-023**（io_uring 实验后端）、**T-012**（静态 TLS）与三平台 Actions 汇总验收 |
| **macOS arm64 / x86_64** | **⏳ 待完成 (Pending)** | C 层保留优雅占位：无原生实现时自动降级有界缓冲路径（功能正确、无零拷贝）；规划接入 macOS 原生 `kqueue` + Darwin `sendfile`（调用签名与 Linux 不同，需独立实现） | 对接 **Milestone 7**：任务 **T-032**（GitHub Actions 三平台持续集成矩阵）、**T-016**（事件循环扩展）、**T-017**（原生零拷贝）与 **T-022**（macOS 独立二进制分发） |

> 📌 **多平台推进原则（D-16 承诺）**：
> 1. 本项目采用“Windows 本机基线先行跑通全功能，再接入 Actions 三平台持续集成与全平台原生调用”的研发策略；
> 2. Windows 本机的完整交付绝不缩减 Linux 与 macOS 的最终支持承诺与同等质量门槛；
> 3. 后续 Milestone 7 将首先由 T-032 建立 GitHub Actions 真实 Runner 矩阵（Linux x86_64、macOS arm64、Windows x86_64），确保三平台在同一规范、同一接口和同一测试套件下持续验证与发行。


