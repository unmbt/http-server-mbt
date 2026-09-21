# DISPATCH — challenger_audit_1

## Objective
作为独立对抗挑战与健壮性验证员（Independent Robustness & Challenger Verifier），对 `http-server-mbt` 项目进行高强度的边界条件、异常输入、状态机重入安全、导出符号纯净度及 CLI 选项校验测试（R2），用实际执行证据验证系统健壮性与稳定性。

## Working Directory
`E:/project/moonbit/unmbt/http-server-mbt/.agents/challenger_audit_1`

## References
- 权威用户需求: `E:/project/moonbit/unmbt/http-server-mbt/ORIGINAL_REQUEST.md` (必须先阅读)
- 规格设计与契约: `docs/design.md` (D-07, D-08, D-11), `docs/tasks.md` (T-020, T-027)
- 产物目录: `target/cabi/` (`hs_min.dll`, `hs_min.lib`, `hs_min_static.lib`, `hs_full.dll`, `hs_full.lib`, `hs_full_static.lib`)
- 消费者测试源码: `testdata/c_consumer/`
- 构建驱动: `scripts/build_cabi.mbtx`

## Detailed Tasks

### 1. C ABI 异常输入与边界健壮性测试
- 编写并执行针对 `target/cabi/` 动静态库的健壮性测试用例：
  - NULL 指针输入：NULL config, NULL err_buf, NULL out_server, NULL server handle。
  - 空字符串、超长字符串、畸形/非合法 JSON 输入。
  - 极端网络参数：非法端口（-1, 0, 65536, 99999, 溢出大整数）、不可达绑定地址、不存在的静态根目录。
  - TLS 组合负面测试（针对 full）：有 cert 缺 key、有 key 缺 cert、证书路径不存在、损坏证书/私钥，验证在监听前拦截并安全返回错误码。
- 验证所有异常输入均返回对应错误码（如 `HS_ERR_INVALID_ARG` 或 `HS_ERR_CONFIG`），0 崩溃、0 段错误（segfault）、0 panic。

### 2. 生命周期与状态机重入测试
- 针对 server 实例测试非正常调用序列：
  - 重复启动（double start）
  - 重复停止（double stop）
  - 未启动即销毁（destroy without start）
  - 停止后重复销毁（double destroy）
  - 对已销毁句柄操作
- 验证在任何调用顺序下，接口不崩溃，无悬挂指针野指针访问。

### 3. 符号隔离与纯净度审计 (dumpbin)
- 使用 `dumpbin /EXPORTS` 检查 `target/cabi/hs_min.dll` 与 `target/cabi/hs_full.dll`：
  - 确认严格仅导出 5 个公共 `hs_*` 符号（`hs_abi_version`, `hs_server_start`, `hs_server_stop`, `hs_server_destroy`, `hs_error_copy`）。
  - 严禁包含 `main` 入口符号，严禁包含任何 MoonBit 编译器运行时内部符号（如 `moonbit_*`）。
- 使用 `dumpbin /SYMBOLS` 审计 `target/cabi/hs_min_static.lib`：
  - 确认绝对不含任何 `mbedtls_*` 或 `psa_*` 符号。

### 4. CLI 不支持选项拦截与退出码测试
- 执行 CLI 负面测试（可直接运行二进制或 `moon run cmd/http-server-mbt-thin -- ...`）：
  - 传入 `--cert test.crt`、`--key test.key`、`--proxy http://127.0.0.1:3000`、`-P http://...`、`--proxy-all`、`--proxy-config` 等 thin 构建不支持的高级参数。
  - 确认进程严格以退出码 1 退出。
  - 确认 stderr 输出清晰可操作指引（包含 "not supported in thin build" 等）。
  - 确认系统上无残留端口监听。

## Deliverables
1. 在 `.agents/challenger_audit_1/challenger_report.md` 输出详尽的健壮性与边界测试实测记录（含命令、输入、输出、退出码）。
2. 在 `.agents/challenger_audit_1/handoff.md` 输出 Handoff 报告，给出明确裁决（`APPROVE` 或 `REQUEST_CHANGES`）。
3. 完成后通过 `send_message` 向 Orchestrator 汇报完成。

## 2026-09-19T03:36:00Z
You are challenger_audit_1, an Independent Robustness and Boundary Challenger.
Your working directory is: E:/project/moonbit/unmbt/http-server-mbt/.agents/challenger_audit_1/
Your parent orchestrator conversation ID is: 9ceae8d4-617a-4975-b88f-862fef2841c5 (recipient: "parent").

MANDATORY FIRST STEP:
Read the authoritative user request at:
E:/project/moonbit/unmbt/http-server-mbt/ORIGINAL_REQUEST.md
and read your detailed dispatch assignment at:
E:/project/moonbit/unmbt/http-server-mbt/.agents/challenger_audit_1/DISPATCH.md

Your mission (R2):
1. C ABI edge cases: Verify NULL inputs (NULL config, NULL err_buf, NULL out_server, NULL server handle), empty/malformed JSON strings, extreme ports (-1, 0, 65536, 99999), invalid bind addresses, invalid roots, negative TLS combinations (cert without key, key without cert, missing files, corrupted certs). Verify safe error codes, 0 crashes, 0 segfaults, 0 panics.
2. State machine re-entry & lifecycle: Verify double start, double stop, destroy without start, double destroy, operations on destroyed handles.
3. Symbol isolation audit via dumpbin: Run dumpbin /EXPORTS on target/cabi/hs_min.dll and hs_full.dll (verify only 5 hs_* symbols, no main, no runtime symbols). Run dumpbin /SYMBOLS on target/cabi/hs_min_static.lib (verify zero mbedtls_* / psa_* symbols).
4. CLI rejection testing: Test http-server-mbt-thin with unsupported options (--cert, --key, --proxy, -P, --proxy-all, --proxy-config). Verify exit code 1, actionable stderr, and zero lingering ports.

You may write C test programs or scripts to execute these test cases and gather empirical evidence.

Output requirements:
- Write comprehensive findings with actual execution logs and outputs to E:/project/moonbit/unmbt/http-server-mbt/.agents/challenger_audit_1/challenger_report.md
- Write your handoff report to E:/project/moonbit/unmbt/http-server-mbt/.agents/challenger_audit_1/handoff.md with a clear verdict (APPROVE or REQUEST_CHANGES).
- Use send_message to report your completion and verdict to parent.

