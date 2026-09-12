# macOS baseline evidence

本轮实现针对 macOS arm64/x86_64 Native（kqueue + Darwin sendfile），保留固定原版仓库
`http-party/http-server` 提交 `0d3b7bb5b6e8a59fd450ae2dca65870009cfcd8b`（14.1.2）。
参考目录 `http-server/` 未修改。

本轮开发环境为 Linux x86_64（Fedora 44，Moon `0.1.20260904`、clang `22.1.8`），
本机无 macOS 硬件与 SDK：Darwin C 代码的首次编译与全量测试已在 GitHub Actions
macos-latest（arm64）runner 上完成并通过，runner 实测工具链与 OS/CPU 版本待补录
（D-16 要求记录实际 OS/CPU，列为 T-032 收口项）。依赖 `moonbitlang/async@0.21.3`。

## 可行性结论与架构依据

**macOS 兼容可行，且事件循环零工作量。** 事件循环不在本仓库：
`moonbitlang/async@0.21.3` 的 native-stub 自带 kqueue 后端
（`src/internal/event_loop/kqueue.c`，`#if defined(__MACH__) || defined(BSD)` 守卫），
socket（TCP_NODELAY/SO_REUSEADDR）、fs、HTTP 解析、WebSocket 层全部跨平台复用。
本仓库唯一的平台相关代码仍是 TransmitFile/sendfile 零拷贝层，本轮补齐第三块：

- `server/transmit_file_windows.c`：真实实现包在 `#ifdef _WIN32` 内；
- `server/transmit_file_linux.c`：`#ifdef __linux__` 真实实现，其他 Unix 优雅降级占位；
- `server/transmit_file_darwin.c`（本轮新增）：`#ifdef __APPLE__` 真实实现；
- native-stub 列表在每个平台编译全部三个 .c 文件，门控互补，每平台恰好一份
  `http_server_tf_*` 符号定义（新增 `transmit_file_linux.c` 顶部
  `#elif defined(__APPLE__)` 空分支防止符号重复）。

平台条件编译遵循 async 先例：MoonBit 侧只用 `platform="windows"` /
`not(platform="windows")` 两分，OS 细节全部在 C 层区分。本轮 MoonBit 侧零改动，
`.mbti` 零差异——非 Windows 的 extern 声明（`#cfg(all(not(platform="windows"),
any(target="native", target="llvm")))`）在 macOS native 上直接绑定同名符号。

Darwin sendfile 与 Linux 的语义差异（D-05 平台表 macOS 行："错误和实际已发送字节
同时检查，短写推进偏移；不套用 Linux 调用签名"）：

| 差异点 | Linux | macOS (Darwin) |
|---|---|---|
| 头文件与签名 | `<sys/sendfile.h>`，`sendfile(out, in, &off, count)` 返回 `ssize_t` | `<sys/socket.h>`，`sendfile(fd, s, offset, &len, hdtr, flags)` 返回 `int` |
| 字节数 | 显式 in-out 偏移指针 + 返回值 | `off_t *len` 为 value-result：入参为发送量，返回后为实际发送量 |
| 短写/非阻塞 | 返回实际发送字节数，EAGAIN 时为 -1 | 部分发送以 -1/EAGAIN 报告，`*len` 已回写实际发送量 |
| EINTR | 语义同上 | EINTR 可能发生在发送任何数据前（`*len == 0` 不代表 EOF） |
| mtime 字段 | `st.st_mtim` | `st.st_mtimespec`（`st_mtim` 不存在） |
| 预取 | `posix_fadvise(POSIX_FADV_WILLNEED)` | `fcntl(F_RDADVISE, &radvisory)`（`posix_fadvise` 不存在） |
| 句柄计数 | 扫描 `/proc/self/fd` | `proc_pidinfo(PROC_PIDLISTFDS)`（`<libproc.h>`） |

## 探针证据（本轮特殊性，2026-09-13）

本轮与 Linux/Windows 基线的根本差异：**实现平台与验证平台分离**。Darwin 分支
在本机不可编译（Linux 无 macOS SDK/头文件），故：

- **本地（Linux x86_64）回归**：`moon check --target native` 0 错误 0 警告；
  `moon test --target native` **169 / 169 全部通过**；`moon info --target native`
  后 `.mbti` 零差异；`moon fmt` 无实质差异。证明本轮改动（C 门控重组、moon.pkg
  native-stub 扩展）未破坏 Linux/Windows 既有行为，Linux 真实 sendfile 后端仍被
  编译选中。
- **macOS 首跑（已通过，2026-09-13）**：GitHub Actions `macos-latest`（arm64）
  runner 上 fixture 字节校验、编译、`moon test --target native` 全量通过、
  release 构建与 artifact `http-server-mbt-macos-arm64` 产出上传完成
  （feat/macos-compat 分支临时工作流验证；run 链接与工具链版本待补录）。
  预期风险项的实际表现见"已知边界"。

## 实现分项（本轮交付）

按 D-16"任务 ID + 平台 + 能力 + 证据"格式记录，总任务在 tasks.md 保持未勾选
（macOS Actions 证据未齐）：

1. **T-017 macOS 分项 — Darwin sendfile 内核零拷贝传输**：新增
   `server/transmit_file_darwin.c`（native-stub 列表注册，与 windows/linux 门控
   互补）。`open(O_RDONLY|O_CLOEXEC)` + fstat 快照 size/mtime（`st_mtimespec`）
   + 越界校验 + `fcntl(F_RDADVISE)` 预取；`step` 按 value-result `len` 语义实现：
   `*len > 0` 即推进 `current_offset` 并扣减 `remaining`（覆盖 EAGAIN/EINTR 短写，
   显式偏移保证不重发）；EINTR 且 `*len == 0` 时重试（信号可能先于任何数据到达，
   不当 EOF）；EAGAIN 且零进度返 2 让出事件循环；`EPIPE/ECONNRESET` 返 -2；
   每块前 fstat 对比 size+mtime 返 -3（D-17）；sendfile 成功但零进度（send 后
   fstat 与传输之间文件收缩）返 -3。64KB 分块与 `step` 返回值契约与
   Windows/Linux 完全一致（0 完成 / 1 推进 / 2 让出 / -1 无效 / -2 断连 /
   -3 FILE_CHANGED / -4 I/O 错误）。
2. **句柄泄漏检测**：`get_handle_count` Darwin 实现为 `proc_pidinfo(getpid(),
   PROC_PIDLISTFDS)` 两段式计数（NULL 查询所需大小 → 分配 → 实际计数）；查询
   失败返回 0，泄漏相对界限断言退化为空（与 Linux `/proc` 扫描不同，如实记录）。
3. **门控重组**：`transmit_file_linux.c` 顶部新增 `#elif defined(__APPLE__)`
   空分支（符号归 darwin.c），`<sys/sendfile.h>` 等 Linux 专属 include 保持在
   不含 Darwin 的分支内；其他 Unix 的优雅降级占位保留。
4. **MoonBit 侧零改动**：`transmit_file.mbt`、`server.mbt`、`core`、engine 均
   未修改，`.mbti` 零差异。降级路径（`send_file_region_bounded_buffer`）保持
   为 `transmit_file` 失败时的兜底。
5. **CI 接入（T-032 macOS 分项）**：ci.yml 启用 `macos-latest` 矩阵项
   （artifact `http-server-mbt-macos-arm64`，与 `scripts/install.sh` 期望名一致）。
   分支验证阶段曾以临时工作流 `macos-baseline.yml` 执行 macos-latest 首跑
   （push 分支 + workflow_dispatch 触发、平台/工具链证据记录步骤），合入 master
   时移除该临时文件，由主矩阵持续验证。无 continue-on-error（D-16 纪律）。

## 已知边界与限制（按 D-05 如实记录）

- **Darwin 代码未经本地编译**：本机无 macOS SDK，`transmit_file_darwin.c` 的
  首次编译发生在 Actions runner 并通过；结构上镜像已验证的 Linux 实现以降低
  风险。
- **背压/在途窗口测试的平台差异**：流式测试的 8MB 文件大小是按 Linux
  内核缓冲（tcp_wmem 自动调优约 2.6MB）标定的；macOS socket 缓冲默认值不同，
  `server_challenger_m5_lifecycle_test` / `server_challenger_m6_edge_test` /
  `server_fault_injection_test` 的在途窗口断言在 macOS 上可能不可观测（测试
  瞬时完成）或表现不同；首跑全量通过、断言未做平台改动，macOS 缓冲默认值下
  的窗口表现细节待后续补充观察。
- **SO_REUSEADDR 语义差异**：async 库文档明示 macOS 上 SO_REUSEADDR 允许两个
  活动 socket 绑定同一端口（与 Node/libuv 默认一致，正是对齐目标）；
  `server_challenger_m5_lifecycle_test` 的顺序重绑（port 29496）首跑通过，
  语义差异记录在案。
- **APFS 文件名归一化**：`testdata/public/中文` 等非 ASCII 文件名测试在 APFS
  （NFD 归一化文件系统）上存在理论分歧面；首跑已通过，未观察到归一化分歧，
  理论面保留记录。
- **句柄计数可退化**：`proc_pidinfo` 查询失败时返回 0，对应泄漏断言空转；
  不假称与 Linux `/proc/self/fd` 计数同等可靠。
- **冷文件 sendfile 阻塞**：与 Linux 相同，sendfile 在事件循环线程同步执行，
  已用 `F_RDADVISE` 预取缓解；有界原生工作队列（D-05 L194）属 T-016 后续交付。
- **CLI 进程级信号处理**：与 Linux 相同为默认处置退出，库级优雅排空随
  T-016 macOS 分项跟进。
- **TLS 与动态内容**：走有界缓冲路径，不宣称内核零拷贝（无 kTLS，D-05 L199）。
- **工具链未固定**：`hustcer/setup-moonbit@v1` 本轮未 pin 版本（与现有
  Linux/Windows 绿基线保持一致，降低首跑变量）；固定工具链为 T-032 收口项。
- **不在本轮范围**：静态 TLS（T-012）、独立二进制分发（T-022）、io_uring
  （T-023，Linux 专属）、Docker 镜像（D-15，Linux amd64 专属）、Mooncakes 包
  （T-030）、故障注入 macOS Actions 回放（T-034）。

## 验证命令（macOS zsh/bash）

```bash
moon check --target native
moon test --target native
moon info --target native
moon fmt
```

实测结果（macOS Actions 首跑，2026-09-13）：

- `moon check`（编译含 `transmit_file_darwin.c`）与 `moon test --target native`：
  全量通过，含零拷贝门禁（`server_challenger_test.mbt` 直接 `transmit_file`
  返回 0，证明实际路径为 Darwin sendfile 非降级）。
- release 构建与 artifact `http-server-mbt-macos-arm64` 产出上传完成；
  CLI 可执行性冒烟待补。
- run 链接、runner 工具链与 OS/CPU 版本待补录（T-032 收口项）。
- ASan/UBSan：未运行——moon 工具链未暴露 sanitizer 编译/链接开关（与
  Linux/Windows 基线一致），句柄泄漏由相对界限断言覆盖（macOS 上为
  `proc_pidinfo` 计数）。

本地（Linux x86_64）回归实测（2026-09-13）：`moon check` 0 错误 0 警告；
`moon test --target native` 169/169；`moon info` `.mbti` 零差异；`moon fmt`
无实质差异。

## 平台支持与后续接续说明

当前基线记录 macOS Native 的实现接入与 Actions 首跑验证结果（已通过）。Windows 已在
`windows-baseline.md` 完成全量闭环，Linux 已在 `linux-baseline.md` 完成本机
闭环。后续按 D-16 与 T-032 在 GitHub Actions 三平台矩阵下持续验证；三平台
共同验收未完成前，tasks.md 对应总任务不勾选，macOS 分项的 run 链接与工具链
证据补录后再更新状态。
