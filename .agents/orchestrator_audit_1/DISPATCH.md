# DISPATCH — orchestrator_audit_1

## Objective
对已完成的 `http-server-mbt` 项目 `thin` 与 `full` 双版本 CLI 打包及 C ABI 动静态库导出流水线（Milestone 1 ~ 3，commit `9cabfb9` 与 `a5c3edf`）进行全方位、多视角的独立代码审查（Review）、对抗挑战（Adversarial Challenge）与规范合规审计（Audit），确保无内存泄漏、无符号污染、无边界未捕获崩溃，严格契约达标。

## Working Directory
`E:/project/moonbit/unmbt/http-server-mbt/.agents/orchestrator_audit_1`

## References
- 规格契约与设计文档: `docs/design.md` (D-07, D-08, D-11), `docs/tasks.md` (T-020, T-027)
- 历史交接指南: `docs/cli-thin-full-and-cabi-handover.md`
- 核心实现包: `c_abi/`, `cmd/http-server-mbt-thin/`, `cmd/http-server-full/`, `full/`, `server/`
- 构建驱动与测试: `scripts/build_cabi.mbtx`, `testdata/c_consumer/`
- 权威请求文件: `E:/project/moonbit/unmbt/http-server-mbt/ORIGINAL_REQUEST.md`

## Requirements

### R1. 多维度代码与架构独立审查（Independent Architecture & Code Review）
- **架构解耦审查**：审查 `server/` 是否彻底解耦加密 C 依赖（`server/moon.pkg` 仅依赖基础运行时与系统 I/O，无 `tls` 依赖）；审查 `full/` 是否纯粹通过依赖注入承载 TLS Acceptor。
- **C ABI 契约审查**：逐行审查 `c_abi/include/http_server.h`、`c_abi/thin/` 与 `c_abi/full/`：
  - 导出接口契约是否严格遵循 D-07 / D-11 规范（仅暴露 `hs_abi_version`, `hs_server_start`, `hs_server_stop`, `hs_server_destroy`, `hs_error_copy` 5 个公开 API）。
  - 是否有任何 MoonBit 托管对象（String, Bytes, 闭包指针）跨越 ABI 泄露给外部宿主。
  - 内存与生命周期管理：句柄分配与销毁是否具备所有权边界，错误信息拷贝是否防止缓冲区溢出。
- **构建驱动与跨平台契约**：审查 `scripts/build_cabi.mbtx` 是否完全遵循 `.mbtx` 纯 MoonBit 约束，工具链探测与对象清洗逻辑是否健壮。

### R2. 严苛对抗挑战与边界模糊测试（Adversarial Challenge & Boundary Stressing）
- **C ABI 异常与攻击面挑战**：
  - 空指针输入（NULL config / NULL err_buf）、空字符串、超长字符串、畸形非合法 JSON 格式输入。
  - 极端网络参数：非法端口（负数、0、65536、溢出数值）、不可达绑定地址、不存在的静态根目录。
  - TLS 组合攻击：指定 cert 但缺失 key、指定 key 但缺失 cert、证书文件不存在、证书与私钥内容损坏或格式错误，验证是否先于监听精准拦截并安全报错。
- **生命周期与状态机重入挑战**：
  - 服务器重复启动（double start）、重复停止（double stop）、未启动即销毁、停止后重复销毁。
  - 验证在任何非法调用顺序下，C ABI 接口均不发生段错误（Segmentation fault）、空指针解引用或不可恢复 panic。
- **符号隔离与纯净度对抗审计**：
  - 使用 `dumpbin /EXPORTS` 严格检查 `target/cabi/hs_thin.dll` 与 `target/cabi/hs_full.dll`，确认仅导出 5 个公共 `hs_*` 符号，严禁存在 CLI `main` 入口或任何 MoonBit 编译器运行时符号。
  - 使用 `dumpbin /SYMBOLS` 严格审计 `target/cabi/hs_thin_static.lib`，确认绝对不含任何 `mbedtls_*` 或 `psa_*` 符号。
- **CLI 拦截与退出码挑战**：
  - 向 `http-server-mbt-thin` 传入 `--cert`、`--key`、`--proxy` 等高级参数，确认严格退出状态码 1，标准错误输出可操作指引，且系统上无残留端口监听。

### R3. SDD 规范合规审计与全量质量门禁（SDD Audit & Regression Gate）
- **规范与任务一致性核验**：
  - 核查 `docs/proposal.md`、`docs/design.md`（D-07, D-08, D-11）与 `docs/tasks.md`（T-020, T-027），确认文档差异（AD 记录）、功能描述与 Windows 交付证据完全闭环。
- **全流程自动化验证**：
  - 重新执行 `moon run scripts/build_cabi.mbtx`，验证全部 6 项动静态库产物生成与 4 组独立 C 测试程序执行 100% PASS。
  - 重新执行全仓 `moon check --target native`，保持 0 errors, 0 warnings。
  - 重新执行全仓 `moon test --target native`，确保全部 230 项测试 100% 通过（0 失败、0 回归）。
- **产出综合审计报告**：
  - 综合审查员（Reviewer）、挑战者（Challenger）与审计员（Auditor）的独立结论，给出最终评审通过与签署决议。

## Acceptance Criteria

### 独立代码审查通过标准
- [ ] 架构审查通过：`server/` 无任何加密/MbedTLS 静态符号泄漏，双版本功能按模块清晰解耦。
- [ ] C ABI 审查通过：头文件设计与实现严格遵循 D-07 / D-11，无托管类型泄露，生命周期清晰无死锁风险。

### 对抗挑战通过标准
- [ ] C ABI 对抗测试通过：NULL、非法 JSON、极端端口、非法 TLS 路径输入均安全返回对应错误码，0 崩溃、0 段错误。
- [ ] 状态机重入测试通过：多次 start/stop/destroy 调用具备幂等性与防护，无悬挂指针。
- [ ] 符号隔离审计通过：动态库导出符号严格仅为 5 个 `hs_*`，无 `main` 符号；`thin` 静态库零 MbedTLS 符号。
- [ ] CLI 对抗测试通过：`http-server-mbt-thin` 遇到不支持选项严格退出码 1 且无监听。

### SDD 审计与全仓门禁标准
- [ ] `docs/design.md` 与 `docs/tasks.md` 规范与状态记录 100% 准确反应该实现与交付证据。
- [ ] `scripts/build_cabi.mbtx` 端到端执行通过，4 个独立 C 消费者测试 100% PASS。
- [ ] `moon check --target native` 保持 0 errors, 0 warnings。
- [ ] `moon test --target native` 230/230 测试 100% PASS。

## Constraints & Execution Protocol
1. **多角色独立性铁律**：审查员（Reviewer）、挑战者（Challenger）与审计员（Auditor）必须为互相独立的 subagent 实例，杜绝自审自查。
2. **纯净度与无推送**：严禁执行 `git push`！如需修复代码或更新文档，在验证完全通过后在本地进行 `git add` 与 `git commit`。
3. **工作区目录规范**：子智能体目录置于 `.agents/<role>_<name>_<N>/`，仅用于元数据与报告，源码、测试与构建脚本放于项目正规目录。
4. **状态与汇报**：定期更新 `progress.md` 与 `BRIEFING.md`。任务全部达标后向 Sentinel 提交最终交付报告（含证据命令、产物路径与各角色结论）。
