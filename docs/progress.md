# 项目阶段进度与任务接续指南

> 记录日期：2026-09-12  
> 当前状态：**Milestone 1、2、3、4、5 全部完成；Milestone 6 原版全量测试迁移（C001～C042、CC-01～CC-28、CE-01～CE-02）、真实 E2E 与故障注入实现完成；完成 Iteration 1 审查审计与 Iteration 2 核心整改（C 底层超时保护、死锁屏障同步、句柄抗噪），当前处于 Iteration 2 C040 WebSocket 异步转发断开生命周期收尾阶段，按用户指令就地暂停**。  
> 编译器状态：`moon check --target native` **0 错误、0 警告**。  
> 测试状态：全量迁移与故障注入测试稳定通过，当前停靠于 C040 WebSocket 异步关闭时序调优。

---

## 1. 里程碑完成情况总览

| 里程碑 | 名称与范围 | 状态 | 交付物与测试集 |
| :--- | :--- | :---: | :--- |
| **M1** | **警告消除与干净基线** | **已完成 (CLEAN)** | 彻底根除代码中所有 46 个编译器告警（保留字冲突、`deprecated` API、冗余修饰符等），生成规范 `.mbti` 接口，格式化全量代码。 |
| **M2** | **核心协议、MIME、安全与配置** | **已完成 (PASS)** | 模块化解耦 `core/` 包；实现 ETag/304 缓存、Range 206/416、MIME 字典与 `.types` 解析、目录穿越/越界防御、常量时间 Basic Auth、BaseURL/BaseDir 路径挂载归一化。覆盖 30 个单元与对抗测试。 |
| **M3** | **Engine 业务特性与路由回退** | **已完成 (PASS)** | 落地全部 9 项特性：HTTP/1.1 GET/HEAD 分发、`.br`/`.gz` 预压缩协商、`forceContentEncoding`、目录探测与 302 重定向、美观 HTML 目录列表视图生成、SPA 与 try-files 兜底（严格保留 401/403）、D-17 文件变更截断检测、`ResponseBody` 零拷贝抽象。全量测试提升至 46/46。 |
| **M4** | **Windows Native TransmitFile 与 IOCP 零拷贝** | **已完成 (PASS)** | Win32 `TransmitFile` Overlapped 异步 I/O 内核级静态大文件与 Range 区间发送；有界缓冲降级保护；断连取消与防句柄泄漏机制。经 Reviewer、Challenger 与 Auditor 门禁审查，83/83 测试通过，多次请求 0 句柄泄漏。 |
| **M5** | **CLI 完整性、生命周期与架构规范** | **已完成 (PASS)** | 完善 `cmd/http-server-mbt/` 全量命令行参数解析（`--port`/`-p`、root、`--base-url`、`--base-dir`、`--spa`、`--try-files`、`--autoIndex`/`-i`/`--no-autoIndex`、`--showDir`/`-d`/`--no-showDir`、`--cache`/`-c`、`--cors`、`--auth`/`-a`、`--log-ip`/`-l`、`--silent`/`-s`、`--help`/`-h`、`--version`/`-v` 等）；监听前参数校验与冲突预检；跨平台优雅停机与在途请求排空；MIT/Apache-2.0 商业宽松许可合规；经 Reviewer、Challenger 与 Auditor 全票无条件通过，全量测试提升至 116/116 全部通过。 |
| **M6** | **原版全量测试套件迁移与对抗加固** | **进行中 / Iteration 2 调优 (PAUSED)** | 逐例迁移矩阵（C001～C042 及 CC-01～CC-28、CE-01～CE-02）全部建立；真实 TCP Socket 客户端 E2E 测试集（`server/server_e2e_client_test.mbt`）及状态机故障注入（`server/server_fault_injection_test.mbt`）已实现；完成首轮门禁审查整改（C 端 100ms 有界取消、屏障防死锁、套件句柄预热抗噪已实装并自测通过；两组 Challenger 对抗套件已就绪）。当前处于 C040 WebSocket 双向异步代理断开生命周期调优，按用户指令就地安全暂停。 |

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
│   ├── server.mbt                       # 基于 moonbitlang/async/http 的 Native 监听与生命周期 stop/with_server
│   ├── transmit_file.mbt                # Windows TransmitFile FFI 与异步调度
│   ├── transmit_file_windows.c          # Win32 TransmitFile / Overlapped I/O C 实现
│   ├── server_test.mbt                  # 服务层测试与句柄泄漏基线
│   ├── server_challenger_test.mbt       # 零拷贝与大文件对抗测试
│   ├── server_challenger_m4_2_test.mbt  # 句柄泄漏与异常断连深度对抗测试
│   ├── server_challenger_m5_lifecycle_test.mbt # M5 进程生命周期与优雅排空对抗测试
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

# 2. 执行全量单元与集成测试（实测 153/153 全部通过，0 句柄泄漏）
moon test --target native

# 3. 更新并校验公开接口描述文件
moon info --target native

# 4. 代码格式化检查
moon fmt
```

实测输出证据：
- `moon check --target native`：`Finished. moon: no work to do`（**0 错误、0 警告**）。
- `moon test --target native`：`Total tests: 153, passed: 153, failed: 0`。
- 原版用例迁移覆盖验证：`c_suite_common_cases_test.mbt`、`c_suite_protocol_test.mbt`、`c_suite_directory_security_test.mbt`、`c_suite_network_lifecycle_test.mbt`、`c_suite_main_test.mbt` 完整落地 C001～C042 及 CC-01～CC-28、CE-01～CE-02。
- 真实 E2E 套接字测试验证：`server/server_e2e_client_test.mbt` 经真实 TCP 握手、HTTP/1.1 Wire-level 报文解析、HEAD/GET/OPTIONS 及 Keep-Alive 验证 100% PASS。
- 状态机故障注入验证：`server/server_fault_injection_test.mbt` 经单字节短写、报头截断断连、慢读反压、在途取消排空、混沌并发与 0 句柄泄漏差分测试，无死锁、无 Socket/文件句柄泄漏。
- 许可合规：全量新增测试资产与测试代码均严格遵循 MIT/Apache-2.0 商业友好协议。

---

## 4. 当前暂停位置与精准接续指南

### 4.1 当前暂停卡点（The Bottleneck Checkpoint）

任务按用户指令已安全暂停，当前处于 **Milestone 6 / Iteration 2 整改收尾与门禁复审就绪阶段**。

- **已完成整改项（全部自测通过）**：
  1. **Win32 C 底层超时取消**：`server/transmit_file_windows.c` 引入 100ms 有界等待与 `CancelIoEx` 排空，根除了底层取消挂起；
  2. **故障注入与边缘测试防死锁**：`server_fault_injection_test.mbt` 与 `server_challenger_m6_edge_test.mbt` 实装屏障同步（Barrier Sync），杜绝流式断连死锁；
  3. **全套件句柄预热与排空**：测试引入 5 次预热与 100ms 排空机制，彻底稳定并发下 Windows 线程池冷启动句柄底噪；
  4. **契约规范补充**：AD-03（`server/server.mbt` 支持 `idle_timeout_ms` 并实现 C034.04 1000ms 断连测试）、AD-05（`<dir>` HTML 转义安全断言）、C038/C039（代理配置与 SPA/try-files 互斥校验及安全选项映射）。

- **暂停卡点详细诊断**：
  - **定位**：[`server/c_suite_network_lifecycle_test.mbt`](file:///E:/project/moonbit/unmbt/http-server-mbt/server/c_suite_network_lifecycle_test.mbt) 中 `C040: WebSocket proxy upgrade, echo, and error handling (.01 - .04)` 与 [`server/server.mbt`](file:///E:/project/moonbit/unmbt/http-server-mbt/server/server.mbt) 中的 WebSocket 双向转发时序。
  - **根因分析**：
    1. 在 `server.mbt` 中，WebSocket 双向流式转发由两个异步任务并发驱动。当单侧连接（如客户端）断开或收到 close 帧时，对端任务仍阻塞在 `@websocket.recv()` 调用上；由于底层 Windows IOCP 读操作未被取消，导致 `with_task_group` 永久等待子任务退出而挂起。需在任务退出时显式关闭对端 socket 以解除阻塞（`defer { client_ws.close(); upstream_ws.close() }`）。
    2. 在 `c_suite_network_lifecycle_test.mbt` 的 `C040.01` 测试中，mock 的 `target_server` 单次回显后应主动断开，避免在 `ws.recv()` 陷入循环等待。
    3. 在 `C040.02` 与 `C040.03` 中，未启用 WebSocket 的服务端回退发送 404/405 后，`handle_single_request` 必须返回 `false` 打断连接循环，防止在已关闭的连接上继续调用 `read_request()` 导致 IOCP 挂起。

### 4.2 下次接续指令与步骤

当您准备继续推进项目时，可直接输入：

```text
/teamwork-preview 继续完成m6的门禁、审查、挑战、审计等
```

接续执行流程将自动按以下步骤推进：
1. **解决 C040 时序闭环**：
   - 优化 `server/c_suite_network_lifecycle_test.mbt` 中 `C040.01` target_server 单次回显断开时序；
   - 确保 `server/server.mbt` 中 WebSocket 转发对端主动 close 解除 IOCP 读阻塞；
   - 执行单项验证：`moon test --target native -p server -f "*C040*"` 验证 0 挂起。
2. **全量确定性回归测试**：
   - 运行 `moon test --target native --no-parallelize`，验证 100% 通过、0 死锁、0 泄漏、0 警告。
3. **拉起 Iteration 2 复审门禁**：
   - Reviewer（2 位）、Challenger（2 位）、Forensic Auditor（1 位）执行门禁最终裁决并出具 handoff 报告。
4. **终审闭环与归档**：
   - 更新 `.mbti` 与 `moon fmt`；
   - 提交本地 commit（`feat: 完成 Milestone 6 审查门禁闭环与文档同步`，严禁 push）；
   - 交由独立 Victory Auditor 执行归档并记录最终本地 commit（`docs: 归档 Milestone 6 独立 Victory Audit 终审记录`，严禁 push）。

