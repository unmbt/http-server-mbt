# 可复现性能基线

本目录是 R-N18 / T-036 的可选测量工具，不是生产服务器，也不恢复已经撤出的 T-024/P 性能门槛。它只启动真实的 release CLI，使用真实 HTTP 路径，并将生成物和原始结果写入 `target/benchmark/`。

## 当前范围

首批实验只覆盖 Linux loopback、明文静态文件、热缓存、闭环 ApacheBench 请求：

- 1 KiB、64 KiB、1 MiB、64 MiB 文件；
- GET 负载，keep-alive 为默认，`--connection-close` 可单独测连接 churn；
- 并发 1、32、256；每个场景默认 3 轮；
- 每轮开始前校验 GET 字节、HEAD 的 `Content-Length` 和 `Range: 17-80` 的 206 字节；
- 记录 QPS、吞吐、P50/P95/P99、失败数、非 2xx 数、服务端 CPU ticks、RSS、构建哈希和环境信息。

这些结果只描述当前机器、当前提交和当前传输路径。loopback、闭环负载和共享 CPU 不能外推到独立客户端、固定到达率、冷缓存、TLS 或生产网络。

## 使用

先检查工具：`moon`、`curl`、`ab`、`sha256sum`、`getconf`、`lscpu`。生成确定性 fixture：

```text
moon run benchmark/fixtures.mbtx
```

运行 Linux 冒烟（约两个文件、两个并发级别，每个组合 128 请求）：

```text
moon run benchmark/run.mbtx -- --label epoll-smoke --smoke --backend platform
```

完整基线需要较长时间，并使用真实 release 构建：

```text
moon run benchmark/run.mbtx -- --label epoll-baseline --backend platform
```

`--binary PATH` 可复用已经审查过的 release CLI；`--backend epoll` 只用于显式记录选择。`io_uring` 和 `io_uring-file` 只有在对应后端通过共同正确性验证后才能比较；脚本不会把失败、不同传输策略或不存在的结果转换成提升。

汇总至少两次同场景测量：

```text
moon run benchmark/report.mbtx -- target/benchmark/epoll-baseline-1 target/benchmark/epoll-baseline-2
```

报告按 `bytes/concurrency` 分组，输出每组的中位 QPS、QPS 最小/最大值、每轮 P99 中位数和 CPU seconds/request。它不会自动计算或宣称 io_uring speedup；比较前必须确认 manifest 中的提交、dirty 状态、二进制哈希、后端请求、keep-alive、CPU 预算和场景一致。

## 目录和结果

| 路径 | 作用 |
|---|---|
| `fixtures.mbtx` | 按 64 KiB 分块生成确定性文件和 SHA-256 manifest |
| `scenarios/static.json` | 文件大小、并发、轮数和持续时间 |
| `run.mbtx` | 生成/复用 CLI、启动服务、做 GET/HEAD/Range 预检、运行负载并保存原始输出 |
| `report.mbtx` | 拒绝不完整或失败结果，汇总重复运行 |
| `target/benchmark/<label>/manifest.json` | OS/kernel/CPU/toolchain/commit/dirty/产物哈希/参数/限制 |
| `target/benchmark/<label>/r*.txt` | 每次 ApacheBench 原始 stdout/stderr |

`target/benchmark/` 中的内容是可复查证据，不进入源码发布包。不要手工编辑 `results.json` 或 `manifest.json` 来绕过失败检查。

## 约束

- 负载驱动、fixture 生成、解析和报告逻辑使用 `.mbtx`；不在 shell/Python/JavaScript 中增加自动化循环。
- 不关闭路径安全、文件变更检测、资源预算或背压；不编写另一套 benchmark 专用 HTTP server。
- `--server-cpu`、`--client-cpu` 可把进程绑到不同 CPU；如果不提供，manifest 会保留空值，结果不应被当成隔离 CPU 证据。
- `server_cpu_seconds` 只读取服务进程 `/proc/<pid>/stat`。它不包含 io-wq、SQPOLL 或其他外部 worker，manifest 会保留这一限制。
- smoke 只验证工具链和结果闭环，不是性能证据；正式比较至少重复两轮并交替场景顺序。
