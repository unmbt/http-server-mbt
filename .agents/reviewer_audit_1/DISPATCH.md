# DISPATCH — reviewer_audit_1

## Objective
作为独立的代码与架构审查员（Independent Code & Architecture Reviewer），对 `http-server-mbt` 项目的 `thin` 与 `full` 双版本解耦架构、C ABI 契约实现、以及 `.mbtx` 构建驱动进行全面、深入、逐行的代码与设计审查（R1）。

## Working Directory
`E:/project/moonbit/unmbt/http-server-mbt/.agents/reviewer_audit_1`

## References
- 权威用户需求: `E:/project/moonbit/unmbt/http-server-mbt/ORIGINAL_REQUEST.md` (必须先阅读)
- 规格设计与契约: `docs/design.md` (重点: D-07, D-08, D-11), `docs/tasks.md` (重点: T-020, T-027)
- 阶段交接文档: `docs/cli-thin-full-and-cabi-handover.md`
- 核心代码包:
  - `server/` (含 `server/moon.pkg`, `server/server.mbt`, `server/transmit_file.mbt`)
  - `full/` (含 `full/moon.pkg`, `full/full.mbt`, `full/tls_acceptor.mbt`)
  - `c_abi/include/http_server.h`
  - `c_abi/thin/` (含 `c_abi/thin/moon.pkg`, `c_abi/thin/c_abi_min.mbt`, `c_abi/thin/bridge_min.c`, `c_abi/thin/hs_min.def`)
  - `c_abi/full/` (含 `c_abi/full/moon.pkg`, `c_abi/full/c_abi_full.mbt`, `c_abi/full/bridge_full.c`, `c_abi/full/hs_full.def`)
  - `cmd/http-server-mbt-thin/` 与 `cmd/http-server-full/`
  - `scripts/build_cabi.mbtx`

## Detailed Tasks

### 1. 架构解耦审查
- 审查 `server/moon.pkg`：确认完全移除 `"unmbt/http-server-mbt/tls"` 依赖，确保 `server` 仅依赖基础运行时与系统 I/O，无任何 MbedTLS C 源码或加密包参与。
- 审查 `server/server.mbt`：确认传输层抽象（`Transport`、`Acceptor` trait、`PlainAcceptor`）设计清晰，`raw_fd` 暴露底层描述符保留 Windows `TransmitFile` 零拷贝通道。
- 审查 `full/`：确认通过依赖注入承载 `TlsServerAcceptor`，未启用 TLS 时回退至明文，前置校验 `@core.validate_tls(config)` 阻断缺失证书。
- 审查 `cmd/http-server-mbt-thin/` 与 `cmd/http-server-full/`：依赖拓扑是否符合精简与完整定义。

### 2. C ABI 契约审查
- 逐行审查 `c_abi/include/http_server.h`：
  - 导出接口是否严格遵循 D-07 / D-11（仅暴露 `hs_abi_version`, `hs_server_start`, `hs_server_stop`, `hs_server_destroy`, `hs_error_copy` 5 个公共 API）。
  - 错误码定义（`hs_error_code`）、不透明句柄定义（`hs_server_t*`）。
- 审查 `c_abi/thin/` 与 `c_abi/full/`：
  - 是否有任何 MoonBit 托管对象（String, Bytes, 闭包指针）跨越 ABI 泄露给外部宿主。
  - 内存与生命周期管理：句柄分配、全局引用或状态保护、销毁顺序是否具备明确所有权边界。
  - 缓冲区安全：`hs_error_copy` 是否校验 `buf` 与 `cap`，防止溢出。

### 3. 构建驱动与跨平台规范审查
- 审查 `scripts/build_cabi.mbtx`：
  - 是否完全遵循纯 MoonBit 脚本约束，无外部 shell/python 驱动。
  - 工具链检测（`cl.exe`, `link.exe`, `lib.exe`, `llvm-objcopy`, `dumpbin`）逻辑。
  - 对象清洗（`llvm-objcopy --remove-section=.drectve`）与 `.def` 白名单导出逻辑是否健壮。

## Deliverables
1. 在 `.agents/reviewer_audit_1/review_report.md` 输出详尽的代码与架构审查报告，附带行级代码证据。
2. 在 `.agents/reviewer_audit_1/handoff.md` 输出 Handoff 报告，给出明确裁决（`APPROVE` 或 `REQUEST_CHANGES`）。
3. 完成后通过 `send_message` 向 Orchestrator 汇报完成。
