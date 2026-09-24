# 脚本入口

所有命令从仓库根目录运行；自动化使用 `.mbtx`，依赖固定 `moonbitlang/async@0.21.3`。先执行 `moon update`。当前候选验证要求 Moon `0.1.20260920`；平台工具链配置见 [Actions](../.github/workflows/cli.yml)。

| 目录 | 入口及用途 |
|---|---|
| `build/` | `build_cli.mbtx`、`build_cabi.mbtx`、`build_node.mbtx`、`build_docker.mbtx`：CLI、C 库、Node 插件、Linux 四组合容器 |
| `check/` | `validate_candidate.mbtx`：Native/核心 wasm-gc、sanitizer、构建和外部消费；`check_automation.mbtx`：递归检查全部维护脚本；`check_external_consumers.mbtx`：Rust/Python；`check_moonbit_consumer.mbtx`：独立 MoonBit 源码消费；`check_native_sanitizers.mbtx`：C 资源回放；`check_node_candidate.mbtx`：离线 npm 候选安装及生命周期 |
| `release/` | `candidate_manifest.mbtx`：候选清单；`verify_candidates.mbtx`：三平台同提交/哈希核对；`release_gate.mbtx`：远程候选 run 与完整发行依赖门槛 |
| `maintenance/` | `gen_version.mbtx`：版本源码；`embed_ca.mbtx`：固定 CA 数据嵌入；`stage_licenses.mbtx`：分发许可证；`vendor_tls.mbtx`：固定来源/哈希的 TLS vendor 再生 |
| `diagnostics/` | `diagnose_server.mbtx`：逐测试文件定位失败/超时；输出诊断，不替代验收门槛 |

```text
moon run scripts/check/check_automation.mbtx
moon run scripts/check/validate_candidate.mbtx
moon run scripts/check/check_node_candidate.mbtx
```

Node 候选检查在 `build_node` 之后分别使用 Node 22/24；Linux 另运行 `build/build_docker.mbtx`。完整远程流程由 Actions 编排，单独运行 `validate_candidate` 不代表完成所有候选门槛。发行脚本需要 workflow 提供的环境变量和候选文件，不是本地开发的一般命令。

`gen_version` 由 `cmd/common/moon.pkg` 调用，`build.mbtx` 留在根目录供模块预构建使用。维护生成器会写入对应生成文件；升级依赖/CA/TLS 数据时同步来源、许可证和设计证据。

`install.sh`、`install.ps1` 是对外安装入口，路径保持稳定。它们沿用现有实现。已完成的一次性源码迁移器及只打印提示的旧 baseline 脚本退出本目录，查阅方法见[清理记录](../docs/repository-layout-20260925.md#退出日常入口的历史脚本)。
