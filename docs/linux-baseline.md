# Linux baseline evidence

本轮实现针对 Linux x86_64 Native，保留固定原版仓库 `http-party/http-server` 提交
`0d3b7bb5b6e8a59fd450ae2dca65870009cfcd8b`（14.1.2）。参考目录 `http-server/` 未修改。

工具链：Moon `0.1.20260904`、clang `22.1.8`（Fedora 44，x86_64-redhat-linux-gnu）、
依赖 `moonbitlang/async@0.21.3`。

## 可行性结论与架构依据

**Linux 兼容可行，且平台铺垫已就绪。** 事件循环不在本仓库：
`moonbitlang/async@0.21.3` 在 Linux native 后端自带 epoll 事件循环
（`src/internal/event_loop/epoll.c` + `event_loop_unix.mbt`），socket、fs、HTTP
解析、WebSocket 层全部跨平台复用。本仓库唯一的平台相关代码是 TransmitFile
零拷贝层：

- `server/transmit_file_windows.c`：真实实现包在 `#ifdef _WIN32` 内；
- `server/transmit_file.mbt`：Windows 用 `#cfg(platform="windows")` extern 声明，
  非 Windows 为返回失败码的占位；
- 占位失败时 `server/server.mbt` 自动降级到 64KB 有界缓冲发送路径（D-05 降级要求）。

平台条件编译遵循 async 先例：MoonBit 侧只用 `platform="windows"` /
`not(platform="windows")` 两分，OS 细节在 C 层用 `#ifdef __linux__` /
`#elif defined(__APPLE__)` 区分。`@types.Fd` 在 Linux native 上为
`pub type Fd = Int`（系统文件描述符）。

## 探针证据（实现前基线，2026-09-12）

验证命令与结果：

- `moon check --target native`：**0 错误、0 警告**。
- `moon test --target native`：**165 / 169 通过**，4 个失败（见下表，全部可解释）。

| # | 测试 | 现象 | 归因 |
|---|---|---|---|
| 1 | `server_challenger_test.mbt:69` 零拷贝直接验证 | `-1 != 0` | 预期内：Linux 占位 `transmit_file` 恒返回 -1，正是零拷贝门禁 |
| 2 | `server_challenger_m6_edge_test.mbt:94` 流式负载取消/排空 | `0 != 3` | 在途窗口不可观测（见下） |
| 3 | `server_challenger_m5_lifecycle_test.mbt:279` 监听 socket 释放后立即重绑 | `Address already in use` | Linux SO_REUSEADDR 语义与 Windows 不同，重绑需可重用地址 |
| 4 | `server_challenger_m5_lifecycle_test.mbt:89` stop_and_drain 排空在途请求 | `false` is not true | 在途窗口不可观测（见下） |

**在途窗口不可观测的实证结论**（限速 curl + `ss` 探针）：Linux 内核会先把响应整体吸收进
socket 缓冲——客户端接收缓冲（tcp_rmem 初始 128KB）加服务端发送缓冲（tcp_wmem 自动调优，
本机实测扩张至约 2.6MB）——因此几百 KB 量级的响应在服务端"瞬间完成"，`active_request_count`
在 5ms 轮询间隔内已归零；Windows 上 TransmitFile 的分块在途挂起使服务端随客户端节奏推进，
窗口自然可见。这不是服务端缺陷（发送节奏与字节完整性均正确），而是测试同步前提的平台差异，
修复方式是把相关流式测试文件加大到超过内核缓冲上限（8MB），使响应必然经历
"灌满缓冲 → 被慢读客户端反压节流"两个阶段，在途窗口变为数百毫秒量级。

CLI 冒烟（`_build/native/debug/build/cmd/http-server-mbt/http-server-mbt.exe
-s -p 18234 testdata/public`）：

- `GET /hello.txt` → `200 OK`，`Content-Length: 14`，响应体恰为 14 字节
  `hello moonbit`，`ETag: W/"14-..."`、`Last-Modified`、`Accept-Ranges` 正确；
- `GET /hello.txt` + `Range: bytes=0-4` → `206 Partial Content`，
  `Content-Range: bytes 0-4/14`，响应体 `hello`；
- `SIGTERM` → 进程立即终止（exit 143）。注意：CLI 进程级信号处理在 Linux 上
  为默认处置，库级 `stop_and_drain` 的排空能力见上表 #4，二者均记录于缺口。

## 实现分项（本轮交付）

按 D-16"任务 ID + 平台 + 能力 + 证据"格式记录，总任务在 tasks.md 保持未勾选
（三平台 Actions 证据未齐）：

1. **T-017 Linux 分项 — sendfile 内核零拷贝传输**：新增
   `server/transmit_file_linux.c`（`native-stub` 列表注册，与
   `transmit_file_windows.c` 门控互补，每平台恰好一份 `http_server_tf_*`
   符号定义）。Linux 分支实现 `open(O_RDONLY|O_CLOEXEC)` + fstat 快照
   size/mtime + 越界校验；`sendfile(out_fd, in_fd, &off, count)` 使用显式
   偏移（独立于共享文件位置，D-05 平台表）；open 时
   `posix_fadvise(WILLNEED)` 预取缓解冷文件阻塞。`step` 返回值契约与
   Windows 完全一致（0 完成 / 1 推进 / 2 让出 / -1 无效 / -2 断连 /
   -3 FILE_CHANGED / -4 I/O 错误）：EINTR 同步重试、EAGAIN 返 2 让出
   事件循环、每块前 fstat 对比 size+mtime 返 -3（D-17）。路径由 MoonBit
   侧 `@utf8.encode` 转为 UTF-8 `Bytes` 传入（`#borrow`，运行时保证
   null 结尾）。非 Linux 的非 Windows 平台保留通用占位（macOS 优雅降级）。
2. **句柄泄漏检测激活**：`get_handle_count` Linux 实现为扫描
   `/proc/self/fd` 计数，激活既有约 6 处相对界限断言（Windows 上为
   `GetProcessHandleCount`）。
3. **MoonBit 侧接线**：`transmit_file.mbt` 非 Windows 占位改为 extern
   声明；Windows 分支零改动。为满足 `moon info` 的全后端接口求值，extern 以
   `#cfg(all(not(platform="windows"), any(target="native", target="llvm")))` 门控，
   并为其他目标（如 wasm）保留同签名纯 MoonBit 占位分支（与 cmd 包既有模式一致）。
4. **`reuse_addr=true`**：`with_server_at` 创建 `TcpServer` 时显式启用 SO_REUSEADDR，
   对齐原版 http-server（Node/libuv）在 Unix 上的默认行为；Windows 忽略该参数，
   修复监听 socket 释放后 TIME_WAIT 立即重绑（探针表 #3）。
5. **流式测试的 Linux 适配**：`server_challenger_m5_lifecycle_test.mbt`、
   `server_challenger_m6_edge_test.mbt`、`server_fault_injection_test.mbt` 中的
   流式传输文件由 256KB/512KB/1MB 统一调整为 8MB（原因见上"在途窗口"结论）；
   全部断言与不变量未改动，Windows 上 TransmitFile 反压语义下行为不变。

## 已知边界与限制（按 D-05 如实记录）

- **冷文件 sendfile 阻塞**：sendfile 在事件循环线程上同步执行，冷缓存时
  首次调用可能阻塞在内核缺页。已用 `posix_fadvise(WILLNEED)` 预取缓解；
  完整的有界原生工作队列隔离（D-05 L194"工作线程只操作 C 拥有的数据"）
  属 T-016 后续交付，本机测试均为热缓存小文件。
- **EAGAIN 重试为事件循环 tick 驱动**：socket 写满时 `step` 返 2，由
  `@async.pause()` 让出一轮事件循环后重试（每轮 64KB），与 Windows 上
  IO_PENDING 轮询 `GetOverlappedResult` 的形状完全一致；该期间事件循环
  以零超时轮转（async 的 `get_next_timeout` 对 run_later 就绪任务返 0）。
  就绪驱动的 EPOLLOUT 注册属 async 运行时范畴，作为 T-016 后续记录。
- **有界缓冲降级路径的 FILE_CHANGED 检测**：引擎 FileLease（mtime/size
  校验）覆盖降级路径；零拷贝路径由 sendfile 状态机每块前 fstat 检测。
  由故障注入测试覆盖验证。
- **SIGTERM 进程级行为**：CLI 在 Linux 上随信号默认处置终止，未接入库级
  优雅排空（与 D-05 L202"SIGTERM 只发停止信号"的目标尚有差距），随
  T-016/T-011 的 Linux 分项继续跟进。
- **不在本轮范围**：macOS 真实实现（kqueue + Darwin sendfile，保留占位
  降级）、io_uring 实验后端（T-023）、musl 完全静态链接（T-022，D-08
  要求无 PT_INTERP/DT_NEEDED）、静态 TLS（T-012）、Docker 镜像（D-15）、
  Mooncakes 包（T-030）。

## 验证命令（Linux bash）

```bash
moon check --target native
moon test --target native
moon info --target native
moon fmt
```

实测结果（实现后终稿，2026-09-12）：

- `moon check --target native`：**0 错误、0 警告**。
- `moon test --target native`：**169 / 169 全部通过**（连续三轮稳定），与 Windows 基线持平；
  含零拷贝门禁转绿（直接 `transmit_file` 返回 0，证明实际路径为 sendfile 非降级）。
- `moon info --target native`：通过，`.mbti` 零差异（公共 API 无变化）。
- `moon fmt`：通过，无实质格式差异。
- CLI 冒烟（实现后二进制）：4MB 文件经 sendfile 多块路径 200 OK，
  4194304 字节实测 2.6ms、字节一致；Range `bytes=1000000-1000999` → 206
  且偏移字节精确；keep-alive 双请求 200/200；SIGTERM 立即退出。
- ASan/UBSan：**未运行**——moon 工具链未暴露 sanitizer 编译/链接开关；
  句柄泄漏由 `/proc/self/fd` 相对界限断言实测覆盖（约 6 处），可在 T-002
  后续外部 C 消费链路或 CI 中补充替代内存检查。

## 平台支持与后续接续说明

当前基线聚焦于 **Linux x86_64 Native** 的功能闭环与零拷贝传输本机验证。
macOS（kqueue + Darwin sendfile）为待完成状态，Windows 已在
`windows-baseline.md` 完成全量闭环。后续按 D-16 与 T-032 接入 GitHub
Actions 三平台持续集成矩阵；三平台共同验收未完成前，tasks.md 对应总任务
不勾选。
