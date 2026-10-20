# io_uring 可行性、性能证据与 benchmark 目录建议

日期：2026-10-17。源码基线：`8b95fe2`，模块 `unmbt/http-server-mbt@0.3.4`，依赖 `moonbitlang/async@0.21.3`。本文是调研与实施建议，不是后端实现、性能测量或支持承诺。

追踪：R-N04 / D-05 / T-023 / N-07；现有运行时与传输涉及 T-016/T-017，文件一致性与取消涉及 D-17/D-18、N-20/N-21。性能讨论遵循 R-N03 / D-09：T-024 与 P 编号继续保持历史撤出状态，不新增量化发布门槛。

## 1. 结论

1. **可以实现 Linux io_uring 实验后端，而且它已在 T-023 范围内。** 建议保持 `platform` 默认 epoll，不把实验后端直接升为默认。
2. **不能根据外部测试承诺本项目提升多少。** 已核对的网络实验既有小幅回退、个位数吞吐改善，也有针对特殊高速网络负载优化后的约 2.3 倍结果；它们不是本项目的预测区间。
3. **建议增加轻量 `benchmark/`，先测现有生产路径，再实现 io_uring 对照。** 放测试驱动、场景、结果格式和报告工具，不放另一套精简 HTTP 服务器；自动化仅用 `.mbtx`。
4. **先检查 epoll 基线自身的发送等待和工作队列成本。** 当前实现已有 `sendfile` 与冷文件工作线程隔离；不能拿它和“同步 read/write 的慢基线”混为一谈。
5. 当前工作区已落地 benchmark 基线和 liburing 2.9 的 Linux C 桥，但**完整网络 io_uring 仍未接入公共 Server/Plain transport**。本轮只把 `io_uring-file` 作为显式混合实验入口；未把 `io_uring` 网络参数伪装成可用，也未恢复 T-024。

## 2. 当前源码实际是什么

本节依据当前源码，而非早期平台基线文档中的文件名或历史测试数。

| 层 | 当前实现与接入影响 |
|---|---|
| 网络事件 | 本地依赖的 `src/internal/event_loop/epoll.c` 使用 epoll，注册 `EPOLLET`；CLI 已增加 `--io-backend`，但完整 `io_uring` 网络后端在启动预检阶段明确拒绝，避免标签与实际路径不一致。 |
| Full 服务 | [server/server.mbt](../server/server.mbt) 中的 `with_server_at_with_connector` 直接构造 `@socket.TcpServer`；`Acceptor` 接收具体 `@socket.Tcp`，不是独立的通用 listener 抽象。 |
| Thin 服务 | [server/plain/plain.mbt](../server/plain/plain.mbt) 同样直接依赖 `TcpServer`/`Tcp`，不能只改 Full 而把 Thin 留在另一条传输契约上。 |
| 文件系统 | [internal/native/native.c](../internal/native/native.c) 的有界 C 工作队列执行 open、stat、目录枚举与 sendfile；Linux `io_uring-file` 将有界文件 read 操作提交到 C-owned ring，其完成仍通过 [Runtime](../internal/native/native.mbt) 的 pipe 通知合法 MoonBit owner。 |
| 文件正文 | [Response::send_to](../engine_resources.mbt) 调用 `file.send`；Linux 的 `hs_send` 使用带显式偏移的 `sendfile`，并在传输前后检查文件状态。 |
| 预算 | [RuntimeLimits](../core/runtime_limits.mbt) 默认 4 个文件 worker、256 个排队操作、64 KiB 正文块，且具有连接和内存预算。公平比较必须保持这些预算可比。 |

当前明文文件路径可以概括为：

```text
async Tcp/epoll → HTTP framing/静态引擎
              → C 工作队列 → sendfile + 文件状态检查
              ← pipe 完成通知 ← C worker
```

### 先处理的基线疑点

- `hs_send` 把 `EAGAIN`、`EINTR` 映射为本轮发送 0 字节；`Response::send_to` 对 `Some(0)` 执行 `@async.sleep(1)`。D-05 要求 EAGAIN 等待可写；当前的定时重试值得单独测量并修正，不能把它导致的差异全部归因于 epoll。
- 每个正文块都会经历工作队列、文件状态检查与 owner 唤醒。它们是候选热点，**尚无 profile 证明它们是主瓶颈**；不能为跑分取消文件变更检测或资源预算。
- `--io-backend` 的配置解析和 `io_uring-file` 文件读取接线已落地；`auto` 目前保持稳定 platform 路径，完整网络 `io_uring` 仍在 T-023，显式请求会在监听前失败，不能在 benchmark 中假装已有完整后端。

## 3. 性能证据：能快多少

只采用作者实验与上游文档，不用不同 HTTP 服务器的排行榜推导后端收益。

| 一手资料 | 对照结果 | 限制 |
|---|---|---|
| gRPC Conf 2025，io_uring EventEngine，最大 QPS、62 channels、1 KB payload | QPS **+3.4%**，P50 **-32.8%**，CPU time **-10%** | 两台 100 Gb/s 机器，**仅客户端**换成 io_uring；不能当作静态 HTTP 服务端收益。[S1] |
| 同一实验，64 KB payload | QPS **-1.5%**，P50 **-10.7%**，CPU time **-12.3%** | 吞吐与 CPU/时延可以朝不同方向变化。[S1] |
| 同一实验，固定 QPS 的 Poisson 到达负载 | 1 KB 的 P50 **+6.9%**、P99.9 **+1.3%**；作者归纳为轻微回退 | 不能只挑饱和负载的优势，忽略平时延迟。[S1] |
| 2025-12-04 的 DBMS 研究，网络 shuffle 对比 epoll | 引言汇总：基础 io_uring **1.10×**，针对性优化后 **2.31×** | 六节点、400 Gb/s 网卡、调优网络栈，涉及零拷贝发送/接收和线程布局；倍率基准为未启用零拷贝的 epoll，文中另测了 epoll 零拷贝发送变体。不是普通 HTTP，更不是已有 sendfile 的本项目。[S2] |

这些结果的共同启示是：**改 API 本身未必有显著收益；减少跨线程交接、有效批处理、减少复制，以及让架构适应 completion 模型才可能产生明显收益。** liburing 作者也明确指出，仅把 epoll notifier 替换成 io_uring notifier，不能充分利用 io_uring。[S3]

### 对本项目的判断（待实验验证，不是测量结果）

| 场景 | 值得验证的收益/限制 |
|---|---|
| 热缓存小文件、高 QPS | 批量 accept/recv/send 可能降低 syscall 与调度成本；若主要时间花在 HTTP、路径解析、分配或元数据检查，收益会受限。 |
| 热缓存大文件 | 已有 sendfile，应优先比较 CPU 秒/GiB 与网络利用率；若已达到链路上限，换后端不会让链路变宽。 |
| 冷文件、多并发读取 | 可能减少现有工作队列交接或改善调度；当前已经有 worker 隔离，不能宣称首次实现磁盘异步。io_uring 本身也可能使用内核 worker，不能宣称没有线程开销。[S2] |
| TLS/动态页面 | 必须分别测量有界缓冲与加密/渲染成本，不能把明文零拷贝结果直接外推。 |
| 慢客户端/混合文件 | 重点观察背压、P99、内存、取消与公平性，而不是单纯最高 QPS。 |

**目前本项目完整 io_uring 相对 epoll 的提升百分比：未知。** `io_uring-file` 仅是混合路径，必须在结果中单独标识；既不承诺 2×，也不把“0～20%”之类未经实测的范围写成项目事实。

## 4. 怎么实现比较合理

### 4.1 建议分阶段接入，不重写业务

1. **基线与 capability probe。** 已在 C 桥中验证 ring setup、必需 opcode、read/accept/recv/send/timeout/cancel 的探测入口；仍需通过 N-07 的实际 Linux 生命周期和 HTTP 共同案例。内核版本与 opcode probe 都不能单独证明某种 flag 或组合可用。正式实现复用 T-023，不新建重复后端任务。
2. **文件侧混合实验。** 在 `internal/native` 引入 Linux ring/operation 实现，保持 C 持有 job、文件句柄与缓冲，MoonBit owner 消费批量完成。可先复用现有唤醒机制；明确记录 pipe/eventfd/线程桥接成本。此时网络若仍为 epoll，必须标为“epoll + io_uring 文件 I/O”，**不是 T-023 完整交付，也不是纯网络后端 A/B**。
3. **完整传输接入。** 抽出内部 listener/connection/file-transfer 边界，消除服务主循环与具体 `@socket.Tcp` 的强耦合，Thin/Full 复用；补齐 accept、recv/send、文件读取、计时、取消。现有公共 `Acceptor`/`Transport` 签名是否受影响，应先在 D-05/D-07/D-20 记录兼容方案。
4. **逐项优化。** 先做普通 SQE/CQE 批处理；multishot、buffer ring、registered buffers、SEND_ZC 各自增加生命周期测试和独立对照，不一次打开所有选项。SQPOLL 留作独立实验，不能通过多占一个 CPU 获得不公平的“单核”结果。

建议使用固定版本的 liburing C 桥，避免自行维护 mmap ring、内存序与系统调用 ABI；引入时记录来源、哈希、许可证、musl/静态归档/PIC/传递链接要求。这里尚未选择具体版本或证明其打包链路。不修改 `.mooncakes/`；若必须改依赖运行时，使用正式上游变更或有来源记录的维护方案。

### 4.2 sendfile、splice 与 SEND_ZC 必须分开

- **保留 sendfile**：是当前明文静态文件的有效对照。即使网络侧换 io_uring，也可以先保留该文件传输策略，报告真实混合路径。
- **io_uring splice**：可探索 file → pipe → socket，须管理 pipe、部分传输、背压、取消和两个阶段的实际字节数；不是天然比一次 sendfile 更快。[S4]
- **read + SEND_ZC**：SEND_ZC 发送的是用户缓冲，不等价于文件到 socket 的 sendfile。文件读入缓冲的成本、内存固定和通知成本仍要计算；不是“所有路径零拷贝”。[S5]
- D-17 的已打开文件 lease、修改检测、FILE_CHANGED 中断与取消排空保持不变；不能预提交无界的大量文件分段，导致检测到修改后仍大量发送旧队列内容。

### 4.3 正确性与部署风险

- `user_data` 使用稳定 operation ID/generation。内核可能在 FFI 返回后继续访问缓冲，禁止把跨调用指针当成 `#borrow` 临时借用；等待终结事件后才释放。
- cancel 自身完成不意味着可以不看原操作状态；处理取消与原完成竞争，尤其是 `-EALREADY`、`-ENOENT`。[S6]
- multishot 一次提交可产生多条 CQE，必须观察 `IORING_CQE_F_MORE`；“恰好一次最终业务完成”不等于“恰好一条 CQE”。[S7]
- SEND_ZC 若发送 CQE 带 `F_MORE`，必须等后续 `F_NOTIF` 才能复用内存；无后续通知的情况也按 flags 分支处理。[S5]
- ring 满、CQ 压力、缓冲耗尽、短写、文件变更、迟到完成、fd 复用、关闭竞态都纳入 D-18；ASan/UBSan、断连/取消/泄漏测试不能由吞吐结果替代。
- 必须保留 D-05 的启动探测与 fallback：`platform` 不改变默认；`auto` 在未编入/禁止/能力缺失时回 epoll；显式 `io_uring` 在监听前失败；在途操作不无声切换并重发。
- Linux 的 `io_uring_disabled` 和容器 seccomp 是独立限制。sysctl 为 0 不等于容器允许相关 syscall；不能建议通过 privileged 或关闭 seccomp 作为默认部署方式。[S8][S9]

## 5. 是否增加 benchmark 目录

**建议增加，但先做小而可复现的测量工具，不恢复原性能承诺。** 本次用户请求是研究是否增加，以下结构尚未创建：

```text
benchmark/
  README.md                   # 范围、命令、指标口径、已知限制
  scenarios/                  # 场景配置；不用 P 编号
  fixtures.mbtx               # 确定性生成文件、记录种子/哈希
  run.mbtx                    # 构建/启动同一生产 CLI、调用负载工具、采集
  report.mbtx                 # 汇总原始数据，输出表格和重复实验分布
  schema/                     # 结果和环境信息 schema
target/benchmark/             # 生成文件、大日志和原始结果，不进入源码发布包
```

只使用 `.mbtx` 编写生成、编排、解析和报告逻辑；外部负载工具可以由 `.mbtx` 直接调用并固定版本。初版不必编写新的压测客户端，更不能复制一份只会返回固定 200 的服务器作为本项目代表。

### 最小实验矩阵

- **配置轴**：当前 epoll 基线 → 经定位改进后的 epoll → io_uring 混合路径 → 完整 io_uring。每项记录提交；网络和文件传输策略分别标注，不能用“auto”掩盖实际后端。
- **主场景**：1 KiB、64 KiB、1 MiB、64 MiB 静态文件；GET/HEAD/Range；keep-alive 为主并单列连接 churn；并发可从 1/32/256 开始，按机器能力扩展。这些是实验参数，不是产品容量门槛。
- **扩展场景**：固定种子的多文件混合、热/冷缓存、TLS、目录页、慢客户端及大/小文件混合。先做少量代表场景，不一次扩成昂贵的全组合。
- **指标**：有效 QPS、有效字节吞吐、P50/P95/P99、错误/超时、CPU 秒/请求与 CPU 秒/GiB、RSS、线程/句柄、上下文切换；syscall/profile 诊断另跑，避免 tracing 扰动主结果。

### 公平性和可复现要求

1. 同一 release 构建方式、CPU/核预算、内存和队列限额、响应语义、日志设置、TLS/压缩配置；SQPOLL 与 io-wq 的 CPU 单独记录并计入总成本。
2. 不为基准禁用鉴权、路径安全、D-17 文件检查或资源预算。不同档位/配置分别报告，不混成一个吞吐数。
3. 客户端和服务端优先分机器；本机冒烟时至少分配不同 CPU 并记录限制，检查客户端是否已饱和。loopback 数字只证明本机路径，不能外推网卡或广域网。
4. 同时报饱和吞吐和固定到达率延迟，避免闭环压测掩盖过载排队；固定到达率工具须记录计划/实际发送率及遗漏请求的处理。
5. 分开定义热/冷缓存；`O_DIRECT` 是不同 I/O 策略，不等于生产的冷页缓存场景。不自动清全局 page cache 或更改系统配置，冷缓存方法要显式、安全、可复现。
6. 预热后多轮运行、交替/随机化后端顺序，记录种子、每轮值与离散度，不只报最好的一轮；只有差异超过噪声且正确性通过，才解释为有效改善。
7. 记录 OS/CPU/kernel、文件系统、存储、NIC、编译器/MoonBit/liburing 版本、Git 提交/dirty 状态、产物 SHA-256、实际后端/opcodes/flags、worker/CPU 预算、负载工具版本及完整参数。能力缺失记为不可测，不记 0 或通过。
8. benchmark 的数据/驱动不进入默认应用构建、Mooncakes 包或发行镜像；实施时验证包资源清单。正确性检查继续走既有三平台 Actions，性能比较使用固定 Linux 机器或自托管 runner；共享 runner 仅作可运行性冒烟，不设百分比发布门槛。

### 建议优先级

**轻量 benchmark 基线 → profile 与修正 epoll 明显等待问题 → io_uring capability/生命周期探针 → 混合文件侧 → 完整 T-023 → 按数据挑选优化。**

若生产代表负载只呈现噪声级收益或 CPU/尾延迟回退，保持 epoll 默认、io_uring 实验可选；这不等于撤销已有 R-N04/T-023 的功能交付要求。若要改为默认后端或引入性能完成门槛，则另行更新需求、设计并确认产品取舍。

## 6. 本轮验证与未验证范围

- 源码与接口检查：`git rev-parse --short HEAD`、`moon version`、`moon ide outline server`、`moon ide outline internal/native/native.mbt`，并核对本地依赖的 socket `.mbti`、epoll C 实现及上述项目源码。未改依赖缓存。
- 环境只读检查：`uname -srmo` 返回 Linux `7.2.4-200.fc44.x86_64` / x86_64；`moon version` 为 `0.1.20260920 (914d7da 2026-09-20)`；`cat /proc/sys/kernel/io_uring_disabled` 为 `0`。这不证明 ring setup、opcode 或 seccomp 实际可用。
- 文档检查：执行 `git diff --check`；核对新增本地链接和 D/T/N 关联；保留原 C001～C042 迁移矩阵及 T-024 撤出状态，未改变任务依赖和默认后端。
- 未执行：io_uring syscall/传输探针、HTTP 性能测试、ASan/UBSan、Actions、打包或发布；没有本项目的 io_uring 实测收益。
- 本轮已运行 benchmark script tests、Linux fixture 生成、两轮 smoke baseline 及 report；未运行完整 benchmark 矩阵，也未把 smoke 数字当作性能门槛或 io_uring 提升证据。

## 7. 一手资料

访问日期均为 2026-10-17；上游 master 文档是访问时的 API 参考，不是已锁定的构建依赖。

- [S1：gRPC Conf 2025 — Experiences with integration of io_uring into gRPC-C++](https://static.sched.com/hosted_files/grpcconf2025/ac/gRPC%20Conf%202025_%20Experiences%20with%20integration%20of%20io_uring%20into%20gRPC-C%2B%2B.pdf)，第 11～14 页的环境、固定 QPS 和最大 QPS 结果。
- [S2：io_uring for High-Performance DBMSs: When and How to Use It，arXiv v1，2025-12-04](https://arxiv.org/html/2512.04859v1)，引言与第 4 节网络 shuffle；研究结果不作为本项目支持或性能承诺。
- [S3：Jens Axboe / liburing — io_uring and networking in 2023](https://github.com/axboe/liburing/wiki/io_uring-and-networking-in-2023)，网络模型、批处理与 multishot。
- [S4：liburing — io_uring_prep_splice](https://raw.githubusercontent.com/axboe/liburing/master/man/io_uring_prep_splice.3)。
- [S5：liburing — io_uring_prep_send_zc](https://raw.githubusercontent.com/axboe/liburing/master/man/io_uring_prep_send_zc.3)。
- [S6：liburing — io_uring_prep_cancel](https://raw.githubusercontent.com/axboe/liburing/master/man/io_uring_prep_cancel.3)。
- [S7：liburing — io_uring_prep_recv](https://raw.githubusercontent.com/axboe/liburing/master/man/io_uring_prep_recv.3)。
- [S8：Linux Kernel — io_uring_disabled / io_uring_group](https://docs.kernel.org/admin-guide/sysctl/kernel.html#io-uring-disabled)。
- [S9：Docker — Seccomp security profiles](https://docs.docker.com/engine/security/seccomp/)，说明 syscall allowlist 可独立拒绝操作；本文不把某一 Docker 默认配置推广为所有容器行为。
