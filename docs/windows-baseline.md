# Windows baseline evidence

本轮实现针对 Windows x86_64 Native，保留固定原版仓库 `http-party/http-server` 提交
`0d3b7bb5b6e8a59fd450ae2dca65870009cfcd8b`（14.1.2）。参考目录 `http-server/` 未修改。

工具链：Moon `0.1.20260904`、Node `v26.4.0`、npm `11.17.0`、clang `22.1.3`。

## 已实现并完成验证的分项（Milestone 1 ~ 3）

1. **编译器警告消除（Milestone 1 达成）**：
   - 全面根除原有 46 个编译器 Warning（消除 `deprecated`、保留字 `method`/`use` 冲突、冗余 `pub` 修饰符、未构造变体等）。
   - `moon check --target native` 达到 **0 错误、0 警告** 纯净状态。
2. **核心协议与模块解耦（Milestone 2 达成）**：
   - `core/cache.mbt`：强/弱 ETag、`If-None-Match`、`If-Modified-Since`、`Cache-Control` 计算与 304 Not Modified 响应。
   - `core/range.mbt`：206 Partial Content、416 Range Not Satisfiable、`Content-Range` 响应头生成。
   - `core/mime.mbt`：标准 MIME 映射表、自定义 MIME 与动态 `.types` 文件解析器、默认扩展名映射。
   - `core/security.mbt`：目录穿越防御（`..`、反斜杠、NUL 拦截与跨盘符越界检测）、常量时间 HTTP Basic Auth。
   - `core/routing.mbt`：BaseURL / BaseDir 路径挂载前缀归一化及互斥规则校验。
3. **Engine 业务特性与高级路由（Milestone 3 达成）**：
   - GET / HEAD 完整分发调度与 HEAD 响应体空抑制。
   - 预压缩协商：Brotli (`.br`) 优先、gzip (`.gz` 带 `0x1F 0x8B` 魔数检测)、`forceContentEncoding` 强制头输出。
   - 目录索引探测与 302 Found 重定向（保留原始 Query）。
   - HTML 目录列表视图生成：$O(N)$ 伴生文件去重匹配、$O(N \log N)$ 排序、HTML 与 URL 转义、dotfile 隐藏文件过滤、图标与文件大小展示。
   - SPA 路由兜底（`--spa` 回退至根 `index.html`）与自定义单文件回退（`--try-files <file>`）。
   - 回退安全隔离：SPA / try-files 回退严格保留 401（未授权）与 403（禁止越界），不掩盖安全错误。
   - D-17 在途文件变更（FILE_CHANGED）截断检测与安全终止。
   - `ResponseBody` 抽象为 `Empty`、`Bytes(Bytes)` 与 `FileRegion(path, offset, length)`。

## 验证命令（Windows PowerShell）

```powershell
moon check --target native
moon test --target native
moon info --target native
moon fmt
```

实测结果（Milestone 6 完成闭环基线）：
- `moon check --target native`：**0 错误、0 警告**。
- `moon test --target native`：**169 / 169 测试全部通过**（0 失败、0 挂起、0 句柄泄漏）。
- 各模块 `.mbti` 接口文件已规范更新，代码保持 `moon fmt` 格式化规范。

## Windows 本机里程碑完成情况（Milestone 1 ~ 6 全部完成）

- **Milestone 1**（已完成）：46 处编译器警告消除，规范 `.mbti` 生成。
- **Milestone 2**（已完成）：解耦 `core/` 包，支持 ETag/304、Range 206/416、MIME 字典及安全路径。
- **Milestone 3**（已完成）：静态文件引擎与路由分发、预压缩协商、HTML 目录列表及 SPA 优雅回退。
- **Milestone 4**（已完成）：Windows 原生 `TransmitFile` Overlapped 异步 I/O 内核级零拷贝传输、有界缓冲降级与断连防句柄泄漏（83/83 测试通过）。
- **Milestone 5**（已完成）：CLI 完整参数解析（`--autoIndex`, `--showDir`, `--cache`, `--cors`, `--auth`, `--spa`, `--try-files` 等）与前置拦截报错，优雅退出与商业宽松协议合规审计（116/116 测试通过）。
- **Milestone 6**（已完成）：原版 C001~C042 及 CC/CE 测试套件 Windows 全量迁移、真实 TCP Socket E2E 测试集、T-034 状态机故障注入与边缘对抗加固（169/169 测试全通过，0 挂起，0 句柄泄漏，多角色独立审查全票无条件 APPROVED / PASSED (CLEAN)）。

## 平台支持与后续接续说明

当前基线聚焦于 **Windows x86_64 Native** 的全量功能与测试闭环验证（M1~M6 全部达成并通过独立第三方 Victory Audit 终审）。**Linux 与 macOS 版本为待完成状态（Pending / In Progress）**，后续将按规划（D-16 与 T-032）在 Milestone 7 接入 GitHub Actions 三平台持续集成矩阵与平台原生零拷贝调用（Linux `io_uring`/`sendfile` + `epoll`，macOS `kqueue` + `sendfile`）。


