# 项目阶段进度与任务接续指南

> 记录日期：2026-09-12  
> 当前状态：**Milestone 1、2、3、4、5 全部完成，Milestone 6 代码实现部分已完成并已本地 Commit，全套门禁测试 153/153 100% 通过（0 失败、0 句柄泄漏），当前按用户指令暂停，等待启动审查门禁**。  
> 编译器状态：`moon check --target native` **0 错误、0 警告**。  
> 测试状态：`moon test --target native` **153 / 153 测试全部通过**（0 失败、0 阻塞、0 句柄泄漏）。

---

## 1. 里程碑完成情况总览

| 里程碑 | 名称与范围 | 状态 | 交付物与测试集 |
| :--- | :--- | :---: | :--- |
| **M1** | **警告消除与干净基线** | **已完成 (CLEAN)** | 彻底根除代码中所有 46 个编译器告警（保留字冲突、`deprecated` API、冗余修饰符等），生成规范 `.mbti` 接口，格式化全量代码。 |
| **M2** | **核心协议、MIME、安全与配置** | **已完成 (PASS)** | 模块化解耦 `core/` 包；实现 ETag/304 缓存、Range 206/416、MIME 字典与 `.types` 解析、目录穿越/越界防御、常量时间 Basic Auth、BaseURL/BaseDir 路径挂载归一化。覆盖 30 个单元与对抗测试。 |
| **M3** | **Engine 业务特性与路由回退** | **已完成 (PASS)** | 落地全部 9 项特性：HTTP/1.1 GET/HEAD 分发、`.br`/`.gz` 预压缩协商、`forceContentEncoding`、目录探测与 302 重定向、美观 HTML 目录列表视图生成、SPA 与 try-files 兜底（严格保留 401/403）、D-17 文件变更截断检测、`ResponseBody` 零拷贝抽象。全量测试提升至 46/46。 |
| **M4** | **Windows Native TransmitFile 与 IOCP 零拷贝** | **已完成 (PASS)** | Win32 `TransmitFile` Overlapped 异步 I/O 内核级静态大文件与 Range 区间发送；有界缓冲降级保护；断连取消与防句柄泄漏机制。经 Reviewer、Challenger 与 Auditor 门禁审查，83/83 测试通过，多次请求 0 句柄泄漏。 |
| **M5** | **CLI 完整性、生命周期与架构规范** | **已完成 (PASS)** | 完善 `cmd/http-server-mbt/` 全量命令行参数解析（`--port`/`-p`、root、`--base-url`、`--base-dir`、`--spa`、`--try-files`、`--autoIndex`/`-i`/`--no-autoIndex`、`--showDir`/`-d`/`--no-showDir`、`--cache`/`-c`、`--cors`、`--auth`/`-a`、`--log-ip`/`-l`、`--silent`/`-s`、`--help`/`-h`、`--version`/`-v` 等）；监听前参数校验与冲突预检；跨平台优雅停机与在途请求排空；MIT/Apache-2.0 商业宽松许可合规；经 Reviewer、Challenger 与 Auditor 全票无条件通过，全量测试提升至 116/116 全部通过。 |
| **M6** | **原版全量测试套件迁移与对抗加固** | **实现完成 / 审查待启动 (PAUSED)** | 对照 `docs/tasks.md` 逐例迁移矩阵（C001～C042 及 CC-01～CC-28、CE-01～CE-02）；构建真实 TCP Socket 客户端 E2E 测试集（`server/server_e2e_client_test.mbt`）；实现 D-18 / T-034 状态机故障注入测试集（`server/server_fault_injection_test.mbt`，涵盖单字节短写、截断断连、慢速反压、在途取消排空与零句柄泄漏验证）；原版测试组分拆模块化（`server/c_suite_common_cases_test.mbt`、`c_suite_protocol_test.mbt`、`c_suite_directory_security_test.mbt`、`c_suite_network_lifecycle_test.mbt`、`c_suite_main_test.mbt`）。全量测试通过数达 **153/153 100% PASS**。已完成第一阶段本地 Git Commit（严格未 push），按用户指示就地暂停。 |

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

## 4. 下次继续任务的接续指南

当前进度已在本地提交保存，代码处于编译与测试全绿状态。

当您准备继续推进项目审查与门禁闭环时，可直接输入：

```text
/teamwork-preview 继续推进 Milestone 6 的审查、对抗测试与门禁闭环
```

调度器与审查团队将按以下顺序接续：
1. **派发审查群组**：
   - `reviewer_m6_1` / `reviewer_m6_2`：审查测试用例与原版 42 文件的语义一致性、覆盖范围及 D 规范对齐；
   - `challenger_m6_1` / `challenger_m6_2`：编写对抗测试，挑战极端慢速客户端、海量并发连接、特殊路径转义与句柄回收；
   - `auditor_m6_1`：审计 0 Warnings、许可证合规及资源安全性。
2. **门禁全票通过与终审闭环**：
   - 修复审查中发现的问题（如有）；
   - 更新 `.mbti` 与文档；
   - 执行 Milestone 6 最终本地 commit（严格禁止 push），交由 Victory Auditor 完成终审归档。

