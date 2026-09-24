# 仓库整理（2026-09-25）

关联 R-SDD/R-COMPAT/R-N11/R-N13、D-02/D-08/D-10/D-14/D-16/D-18、T-025/T-026/T-030/T-034。基线 `92b91f4`；状态：已完成（本地结构整理分项）。各总任务的跨平台状态保持原状。

## 交付与边界

18 个维护脚本按构建、检查、发行、维护、诊断分类；根目录 `build.mbtx` 与公开安装脚本路径保持。Actions、脚本互调、版本生成钩子和源码候选打包均同步路径；Action 版本没有变更。脚本检查递归发现源文件，排除 `_build`、`target` 和隐藏缓存目录；格式化后仍只检查 18 个维护脚本及根构建钩子。

9 份历史文档移入 `docs/archive/`，增加归档标识并修复链接；历史命令保留当时路径。当前入口见 [开发文档](README.md)、[脚本入口](../scripts/README.md)、[测试说明](../tests/README.md)。

17 个测试文件按行为重新命名；三个等价的 Content-Length HTTP 客户端实现提取到 `server/http_test_helpers_test.mbt`。独立资源探针放入 `tests/resources/`，外部消费者放入 `tests/consumers/`，sanitizer 驱动放入 `tests/native_sanitizer/`。静态 fixtures、故障种子和 C/CC/CE/N 稳定编号保留，没有删除或跳过测试。

通过 `moon info --target native` 同步 13 份接口文件，再执行 `moon fmt` 并审查差异。接口差异反映整理前源码已有行为，包括异步 `StaticEngine::open`/`close`、有界 `Response::to_bytes` 和 internal 包；此次没有修改生产 API 实现。版本、CA、许可证及 TLS vendor 生成入口同步路径；CA 再生成与已格式化输出一致。TLS 仍使用固定 4.2.0 归档，SHA-256 为 `2bed9d713b4668f76553b097e72b8aa30bc8f112a940d7ae228d524bbde6ffea`，vendor 源改动仅为两份托管配置头的生成器路径注释。

## 本机验证证据

执行日期：2026-09-25；平台：Windows 11 Pro 10.0.26200 x86_64；Moon `0.1.20260920`，moonc `v0.10.14+7d59c7ec9`，async `0.21.3`；C 工具链 MSVC `14.42.34433`、Windows SDK `10.0.22621.0`。证据对应基线 `92b91f4` 上的本次整理。下列 `target/` 日志是忽略的本地产物，结果在此记录，不作为远程 CI 证据。

| 命令（从仓库根目录执行） | 结果 / 本地日志 |
|---|---|
| `moon check --target native --deny-warn` | 通过，无警告 |
| `moon test --target native --deny-warn` | 265/265 通过，`target/layout-native-final.log` |
| `moon check core --target wasm-gc --deny-warn`、`moon test core --target wasm-gc --deny-warn` | 检查通过；28/28 通过 |
| `moon run scripts/check/check_automation.mbtx` | 根构建钩子 + 18 个维护脚本检查通过，含格式化缓存存在时的扫描 |
| `moon run scripts/check/check_moonbit_consumer.mbtx` | 干净外部 workspace 的引擎、Thin、Full 消费通过，生成源码候选包 |
| `moon run scripts/build/build_cabi.mbtx` | Thin/Full 静态和动态 C 消费共 4 项通过，导出检查通过；`target/layout-cabi.log` |
| `moon run scripts/check/check_external_consumers.mbtx` | Rust/Python 各 Thin/Full，共 4 项通过；`target/layout-external.log` |
| `moon run scripts/build/build_node.mbtx` | Node 插件构建和 ABI smoke 通过；`target/layout-node-build.log` |
| `moon run scripts/check/check_node_candidate.mbtx` | Node 22.20.0、24.9.0 各 6/6 通过；`target/layout-node22.log`、`target/layout-node24.log` |
| `moon run scripts/build/build_cli.mbtx` | Thin/Full 构建、版本/help、Thin 参数拒绝、PE 依赖清单通过；`target/layout-cli.log` |
| `moon info --target native`、`moon fmt` | 接口生成与格式审查完成，仅保留本次涉及文件的格式差异 |
| `moon run target/verify_layout.mbtx`（本次临时审计） | 264 个显式 `.mbt` 测试声明保留，另有 README 文档测试组成 265 项；42 文件迁移矩阵、CC/CE 与总任务勾选状态保持；本地链接和维护脚本引用有效 |
| `git diff --check`、`git diff --cached --check` | 通过 |

环境修正与未运行项：首次 Node 候选检查使用的 bundled Node 缺少相邻 npm-cli，改用完整的本机 Node 22/24 安装后通过；其补丁版本与 Actions 固定版本不同。CLI 首次缺少 `llvm-readobj`，将本机 LLVM 工具目录加入 PATH 后通过。Rust/Python 使用 MSVC/SDK 的 PATH/LIB 及显式 Python 路径。曾尝试直接测试版本生成脚本，Moon 报告 0 项测试，此结果不计为通过；版本生成由实际构建验证。

本次未运行 sanitizer 回放（当前 PATH 无适用 clang）、Linux/macOS Actions、Docker 或发行流程；没有声称完整 `validate_candidate` 门槛通过。相关脚本和工作流路径已更新并检查，远程平台仍需后续 CI。此次不发布、不推送。

## 路径迁移

公开产品包保持原路径；表中资源包是独立测试进程，消费者 MoonBit 模块是测试输入。

| 原路径 | 当前路径 |
|---|---|
| `scripts/build_cabi.mbtx` | `scripts/build/build_cabi.mbtx` |
| `scripts/build_cli.mbtx` | `scripts/build/build_cli.mbtx` |
| `scripts/build_docker.mbtx` | `scripts/build/build_docker.mbtx` |
| `scripts/build_node.mbtx` | `scripts/build/build_node.mbtx` |
| `scripts/check_automation.mbtx` | `scripts/check/check_automation.mbtx` |
| `scripts/check_external_consumers.mbtx` | `scripts/check/check_external_consumers.mbtx` |
| `scripts/check_moonbit_consumer.mbtx` | `scripts/check/check_moonbit_consumer.mbtx` |
| `scripts/check_native_sanitizers.mbtx` | `scripts/check/check_native_sanitizers.mbtx` |
| `scripts/check_node_candidate.mbtx` | `scripts/check/check_node_candidate.mbtx` |
| `scripts/validate_candidate.mbtx` | `scripts/check/validate_candidate.mbtx` |
| `scripts/candidate_manifest.mbtx` | `scripts/release/candidate_manifest.mbtx` |
| `scripts/release_gate.mbtx` | `scripts/release/release_gate.mbtx` |
| `scripts/verify_candidates.mbtx` | `scripts/release/verify_candidates.mbtx` |
| `scripts/embed_ca.mbtx` | `scripts/maintenance/embed_ca.mbtx` |
| `scripts/gen_version.mbtx` | `scripts/maintenance/gen_version.mbtx` |
| `scripts/stage_licenses.mbtx` | `scripts/maintenance/stage_licenses.mbtx` |
| `scripts/vendor_tls.mbtx` | `scripts/maintenance/vendor_tls.mbtx` |
| `scripts/diagnose_server.mbtx` | `scripts/diagnostics/diagnose_server.mbtx` |
| `PROJECT.md` | `docs/archive/PROJECT.md` |
| `TEST_INFRA.md` | `docs/archive/TEST_INFRA.md` |
| `ORIGINAL_REQUEST.md` | `docs/archive/ORIGINAL_REQUEST.md` |
| `docs/progress.md` | `docs/archive/progress.md` |
| `docs/windows-baseline.md` | `docs/archive/windows-baseline.md` |
| `docs/linux-baseline.md` | `docs/archive/linux-baseline.md` |
| `docs/macos-baseline.md` | `docs/archive/macos-baseline.md` |
| `docs/cli-thin-full-and-cabi-handover.md` | `docs/archive/cli-thin-full-and-cabi-handover.md` |
| `docs/implementation-20260924.md` | `docs/archive/implementation-20260924.md` |
| `engine_challenger_m3_2_stress_test.mbt` | `engine_protocol_matrix_test.mbt` |
| `engine_security_directory_adversarial_test.mbt` | `engine_directory_security_test.mbt` |
| `core/routing_config_adversarial_test.mbt` | `core/routing_config_test.mbt` |
| `core/security_auth_range_adversarial_test.mbt` | `core/security_auth_range_test.mbt` |
| `cmd/common/cli_challenger_wbtest.mbt` | `cmd/common/cli_validation_wbtest.mbt` |
| `full/full_challenger_m1_2_test.mbt` | `full/tls_configuration_test.mbt` |
| `server/server_challenger_test.mbt` | `server/transfer_stress_test.mbt` |
| `server/server_challenger_m1_test.mbt` | `server/transport_lifecycle_test.mbt` |
| `server/server_challenger_m1_2_test.mbt` | `server/preflight_test.mbt` |
| `server/server_challenger_m4_2_test.mbt` | `server/transfer_http_semantics_test.mbt` |
| `server/server_challenger_m5_lifecycle_test.mbt` | `server/shutdown_drain_test.mbt` |
| `server/server_challenger_m6_test.mbt` | `server/protocol_stress_test.mbt` |
| `server/server_challenger_m6_edge_test.mbt` | `server/cancellation_range_stress_test.mbt` |
| `server/server_test.mbt` | `server/static_http_test.mbt` |
| `server/server_acceptor_test.mbt` | `server/acceptor_test.mbt` |
| `server/server_e2e_client_test.mbt` | `server/http_client_test.mbt` |
| `server/server_fault_injection_test.mbt` | `server/fault_injection_test.mbt` |
| `internal/resource_tests/` | `tests/resources/budget/` |
| `tests/preflight_handles/` | `tests/resources/preflight/` |
| `testdata/c_consumer/` | `tests/consumers/c/` |
| `testdata/rust_consumer/` | `tests/consumers/rust/` |
| `testdata/python_consumer/` | `tests/consumers/python/` |
| `testdata/moonbit_consumer/` | `tests/consumers/moonbit/` |
| `testdata/native_sanitizer/main.c` | `tests/native_sanitizer/main.c` |
| `npm/test/index.test.js` | `tests/consumers/node/index.test.cjs` |

## 退出日常入口的历史脚本

以下脚本可用 `git show 92b91f4:scripts/<文件名>` 查阅。前 19 项是一次性改写器；`windows_baseline.mbtx` 仅打印提示，不构成基线验证。未将历史脚本当作待执行任务。

- `correct_task_status.mbtx`
- `extend_c_consumers.mbtx`
- `extract_shared_cli.mbtx`
- `finish_resource_wiring.mbtx`
- `fix_accept_drain.mbtx`
- `fix_native_options.mbtx`
- `fix_owned_errors.mbtx`
- `fix_server_lifecycle.mbtx`
- `fix_shared_admission.mbtx`
- `harden_build_inventory.mbtx`
- `isolate_cabi_build.mbtx`
- `migrate_listing_stream.mbtx`
- `migrate_owned_engine.mbtx`
- `migrate_toolchain_warnings.mbtx`
- `pin_automation_imports.mbtx`
- `relocate_native_flags.mbtx`
- `remove_path_transfer.mbtx`
- `share_native_executor.mbtx`
- `unify_http_framing.mbtx`
- `windows_baseline.mbtx`
