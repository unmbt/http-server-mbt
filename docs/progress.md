# 项目阶段进度与任务接续指南

> 记录日期：2026-09-12  
> 当前状态：**Milestone 1、2、3、4、5 全部完成，门禁测试全部闭环**。  
> 编译器状态：`moon check --target native` **0 错误、0 警告**。  
> 测试状态：`moon test --target native` **116 / 116 测试全部通过**（0 失败、0 阻塞、0 句柄泄漏）。

---

## 1. 里程碑完成情况总览

| 里程碑 | 名称与范围 | 状态 | 交付物与测试集 |
| :--- | :--- | :---: | :--- |
| **M1** | **警告消除与干净基线** | **已完成 (CLEAN)** | 彻底根除代码中所有 46 个编译器告警（保留字冲突、`deprecated` API、冗余修饰符等），生成规范 `.mbti` 接口，格式化全量代码。 |
| **M2** | **核心协议、MIME、安全与配置** | **已完成 (PASS)** | 模块化解耦 `core/` 包；实现 ETag/304 缓存、Range 206/416、MIME 字典与 `.types` 解析、目录穿越/越界防御、常量时间 Basic Auth、BaseURL/BaseDir 路径挂载归一化。覆盖 30 个单元与对抗测试。 |
| **M3** | **Engine 业务特性与路由回退** | **已完成 (PASS)** | 落地全部 9 项特性：HTTP/1.1 GET/HEAD 分发、`.br`/`.gz` 预压缩协商、`forceContentEncoding`、目录探测与 302 重定向、美观 HTML 目录列表视图生成、SPA 与 try-files 兜底（严格保留 401/403）、D-17 文件变更截断检测、`ResponseBody` 零拷贝抽象。全量测试提升至 46/46。 |
| **M4** | **Windows Native TransmitFile 与 IOCP 零拷贝** | **已完成 (PASS)** | Win32 `TransmitFile` Overlapped 异步 I/O 内核级静态大文件与 Range 区间发送；有界缓冲降级保护；断连取消与防句柄泄漏机制。经 Reviewer、Challenger 与 Auditor 门禁审查，83/83 测试通过，多次请求 0 句柄泄漏。 |
| **M5** | **CLI 完整性、生命周期与架构规范** | **已完成 (PASS)** | 完善 `cmd/http-server-mbt/` 全量命令行参数解析（`--port`/`-p`、root、`--base-url`、`--base-dir`、`--spa`、`--try-files`、`--autoIndex`/`-i`/`--no-autoIndex`、`--showDir`/`-d`/`--no-showDir`、`--cache`/`-c`、`--cors`、`--auth`/`-a`、`--log-ip`/`-l`、`--silent`/`-s`、`--help`/`-h`、`--version`/`-v` 等）；监听前参数校验与冲突预检；跨平台优雅停机与在途请求排空；MIT/Apache-2.0 商业宽松许可合规；经 Reviewer、Challenger 与 Auditor 全票无条件通过，全量测试提升至 116/116 全部通过。 |
| **M6** | **原版全量测试套件迁移与对抗加固** | **待启动 (PAUSED)** | 对齐 `docs/tasks.md` 逐例迁移矩阵（C001～C042 及 CC-01～CC-28、CE-01～CE-02）；真实 HTTP 客户端集成测试；状态机故障注入与并发健壮性验证。 |

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
│   └── moon.pkg
├── cmd/http-server-mbt/                 # 命令行可执行入口
│   ├── main.mbt                         # CLI 主入口与服务生命周期调度
│   ├── cli.mbt                          # CLI 参数解析、默认值、别名与预检校验
│   ├── cli_wbtest.mbt                   # CLI 白盒单元测试 (参数矩阵、非法输入拦截等)
│   ├── cli_challenger_wbtest.mbt        # 对抗性 CLI 白盒测试 (极端边界与互斥校验)
│   └── moon.pkg
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

# 2. 执行全量单元与集成测试（实测 116/116 全部通过，0 句柄泄漏）
moon test --target native

# 3. 更新并校验公开接口描述文件
moon info --target native

# 4. 代码格式化检查
moon fmt
```

实测输出证据：
- `moon check --target native`：`Finished. moon: no work to do`（**0 错误、0 警告**）。
- `moon test --target native`：`Total tests: 116, passed: 116, failed: 0`。
- Win32 TransmitFile 内核零拷贝验证：`server/transmit_file_windows.c` 与 `server/transmit_file.mbt` 经普通文件、大文件、Range 切片传输真实验证，Overlapped 异步 I/O 无阻塞。
- 句柄泄漏排查验证：`server_test.mbt`、`server_challenger_test.mbt` 与 `server_challenger_m4_2_test.mbt` 经重复请求、慢速读取、并发及异常断连压测，`GetProcessHandleCount` 差异为 0，实现 0 handle leak。
- CLI 参数解析与生命周期验证：`cmd/http-server-mbt/cli.mbt`、`cli_wbtest.mbt`、`cli_challenger_wbtest.mbt` 与 `server/server_challenger_m5_lifecycle_test.mbt` 全面验证 `--port`, root, `--base-url`, `--base-dir`, `--spa`, `--try-files`, `--autoIndex`, `--showDir`, `--cache`, `--cors`, `--auth`, `--silent`, `--log-ip` 等参数解析、监听前非法参数拦截及优雅信号停机与在途请求排空。
- 开源许可合规审计：代码与依赖仅使用 MIT、Apache-2.0、BSD-3-Clause 等宽松商业协议，经法务审计（Auditor）确认 100% CLEAN。

---

## 4. 下次继续任务的接续指南

当您准备继续推进项目时，可直接运行：

```text
/teamwork-preview 继续推进 Milestone 6（原版全量测试套件迁移与对抗加固）及后续任务
```

调度器与 Worker 将按以下顺序自动无缝接续：
1. **启动 Milestone 6**：
   - 对照 `docs/tasks.md` 中的 C001~C042 及 CC/CE 测试用例表，补充端到端真实 HTTP 测试用例与状态机故障注入测试；
   - 建立 Actions 三平台基础矩阵（T-032），验证 Linux x86_64、macOS arm64 与 Windows x86_64 跨平台兼容性；
   - 强化状态机异常注入（T-034），覆盖连接短写、异常断连与并发竞争。

