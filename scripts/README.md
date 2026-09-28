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

日常发版沿用根目录的 [moon-bump 配置](../bump.config.json)（本机验证版本 0.1.3）：

```text
moon-bump
# 或明确选择版本：
moon-bump --release patch
```

`moon-bump` 先更新根 `moon.mod`、CLI 生成版本和四个 npm 清单（包括主包内的平台依赖），再通过 `execute` 调用 `prepare_release.mbtx` 同步派生文件、检查版本一致性并执行 `moon check --target native --deny-warn`。钩子失败会阻止提交/tag/push；成功后由工具继续提交、打 tag 和推送，无需另跑手工同步。现有 `all: true` 配合默认干净工作区检查，将钩子生成的文件纳入同一 release 提交。

只在本地预览替换、不提交/tag/push，可运行 `moon-bump --release patch --no-commit --no-push`。版本修改仍会写入工作区。手工修复版本漂移时可单独运行：

```text
moon run scripts/maintenance/gen_version.mbtx --sync
moon run scripts/maintenance/gen_version.mbtx --check
moon test scripts/maintenance/gen_version.mbtx --deny-warn
```

`--sync` 是发版钩子使用的同步/修复入口；`--check` 只读检查，已加入候选验收入口，在构建前拒绝版本漂移。CLI 版本断言和干净消费从 `moon.mod` 动态读取；`--print moon.mod` 输出纯版本，`--consumer moon.mod` 输出对应消费模块元数据。消费示例自身的 `0.0.0` 不升级，只同步其项目依赖。升级回归使用独立临时夹具，不改工作区版本。

候选验收成功后，`Release verified candidates` 仍需手动提供同一提交的 `candidate_run`、完整 `commit` 和已有 `v<version>` tag；版本、提交、三平台清单及哈希都必须一致。现有完整发行任务和 `full_release_ready` 门槛同样适用。版本同步通过只证明版本一致，不能代替完整发布资格；已有 tag 指向旧提交时，不得把它与修复提交的候选混用。

`install.sh`、`install.ps1` 是对外安装入口，路径保持稳定。它们沿用现有实现。已完成的一次性源码迁移器及只打印提示的旧 baseline 脚本退出本目录，查阅方法见[清理记录](../docs/repository-layout-20260925.md#退出日常入口的历史脚本)。
