# 实验性 io_uring 后端

本项目的 Native 默认后端仍由 `--io-backend platform` 选择：Linux 使用
epoll/sendfile，Windows 使用 IOCP/TransmitFile，macOS 使用
kqueue/sendfile。io_uring 是 Linux 专用实验路径，当前只把
`IORING_OP_READ` 用于文件读取，文件发送仍从有界 `File::read` 回退，不把普通
socket `send` 标作零拷贝。

## 选择后端

```text
http-server-mbt ./public --io-backend platform
http-server-mbt ./public --io-backend auto
http-server-mbt ./public --io-backend io_uring
```

`platform` 是默认值。`auto` 在 Native 启动时探测 `io_uring_setup` 和
`IORING_OP_READ`；探测失败（包括 `ENOSYS`、`EPERM`、不支持的 opcode 或
受限 sandbox）就回退到该平台的稳定后端。显式 `io_uring` 只在 Linux 且探测
成功时接受，其他平台或受限环境会在创建监听 socket 前失败。运行中的单次
I/O 失败不会悄悄切换后端并重发数据。

Linux 5.1 及更高版本才提供 io_uring 系统调用；更旧内核可以继续使用
`platform`/`auto`，但 `auto` 会稳定地回退。

C ABI 的 JSON 配置和 Node.js `createServer`/`createEngine` 也使用同一个
`io_backend` 字段及选择规则；例如 `{"io_backend":"auto"}`。显式后端在
当前平台或内核不可用时返回 `HS_ERR_UNSUPPORTED`（Node.js 中为
`HS_UNSUPPORTED`；同步 `createServer` 包装器会抛出带同一诊断的
`SERVER_START_ERROR`），不会创建监听器或引擎。

实验通过 Linux syscall ABI 直接调用，不链接 liburing。构建仍需要目标 Linux
工具链提供 `<linux/io_uring.h>`；这只是编译期 UAPI 头文件要求，不是运行时
库依赖。默认三平台构建不会因为该实验链接 liburing。当前桥接为每个有界
读取建立临时 ring、提交一个请求并同步等待 CQE；尚未共享 ring，也没有把
`IORING_OP_ASYNC_CANCEL` 接入在途取消，因此这部分仍属于实验完成条件。

## 能力探针与验证

MoonBit 根包提供两个 Native 查询：

```moonbit
@root.io_uring_available()      // setup + IORING_OP_READ
@root.io_uring_capabilities()   // bit 0 setup, 1 READ, 2 SEND, 3 ASYNC_CANCEL
```

能力位保留部分探测结果，因此 `available=false` 时能力值不一定为零；至少
`setup` 或 `READ` 缺失即可使实验不可用。`benchmarks/` 可重复执行相同的
StaticEngine 规划和有界读取：

```text
moon run benchmarks --target native --release -- --root testdata/public --path /hello.txt --io-backend auto --iterations 10000
```

输出同时记录请求的 `backend` 和实际选择的 `backend_selected`，只用于记录本机路径、字节数和耗时。它不是跨机器性能结论，也不是发布
门槛。候选 CI 会在每个平台执行 auto 冒烟，并在能力可用时执行显式后端；受限
Linux runner 会验证显式选择在引擎和监听器创建前失败。

当前仍待补齐 Linux 可用内核上的取消/故障注入、三平台 Actions 证据和 sanitizer
报告，详见 [任务清单](tasks.md) 的 T-023/T-036/T-037。
