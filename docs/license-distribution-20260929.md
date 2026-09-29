# 2026-09-29 第三方许可分发补齐

关联 R-SDD/R-COMPAT/R-N02/R-N11/R-N13、D-08/D-14～D-16、T-001/T-025/T-026/T-030、N-18。本次保留 MIT 元数据，不升级依赖、不改变 ABI/协议或重新发布已有版本。42 个原版测试文件的迁移范围不变。

## 交付

- 根目录 [第三方声明](../THIRD_PARTY_NOTICES.md) 说明许可边界，明确 MbedTLS/TF-PSA 选择 Apache-2.0。
- [固定来源](../third_party/PROVENANCE.md) 和原版 MIT 版权纳入正式仓库；HTTP-server-MIT.txt 的 Git blob 为 `e73eb6840bbc2f9a03570acf8621575fa696b00d`，与固定原版 LICENSE 一致。
- 构建读取实际 MoonBit core LICENSE/NOTICE、runtime 版权、libbacktrace 声明，记录工具链版本和 runtime/simdutf 对象 SHA-256。Linux 同时收集实际 Debian musl copyright 和版本。simdutf 许可文本固定于 v7.3.5，不能据此认定工具链对象就是该版本；对象上游版本仍未独立确认，用工具链与对象哈希标识。
- MPL 包内直接提供 cacert.pem、ca_bundle.mbt 和生成器，配套许可和来源；不依赖接收方日后下载某个浮动网页。
- npm 主包/当前平台包、CLI/SDK 及候选归档带入许可；源码候选保留第三方材料与生成器；新增 CLI 完整归档和裸程序配套许可归档，旧可执行文件名保持兼容。
- 四镜像复制许可目录，实际启动的镜像通过 docker cp 取回许可复验。Docker 构建上下文允许候选许可目录，其他 target 内容继续忽略。
- N-18 包内检查拒绝缺失/空白许可证、缺失 MPL 源码；真实 tarball 中的项目许可、原版版权及 MPL 源码与当前输入逐字节核对。候选汇总/发行复验与已有 SHA-256 清单门槛衔接。

## 验证

Windows x86_64，Moon 0.1.20260920，moonc v0.10.14+7d59c7ec9。修复前运行 `moon run scripts/check/check_licenses.mbtx --bundle npm/http-server/licenses` 失败，报告缺少 THIRD_PARTY_NOTICES.md，证明旧包不满足新检查。

本机结果（在基线提交 `4d2c6e09b29c0849ae7310b42123f3d29bf6f50f` 的工作树修改上执行，不冒充已提交/发布产物）：

| 命令/范围 | 结果 |
|---|---|
| `moon check --target native` | 通过 |
| `moon test scripts/maintenance/stage_licenses.mbtx --target native --deny-warn` | 2/2，包含首次创建嵌套目录和重复运行 |
| `moon test scripts/check/check_licenses.mbtx --target native --deny-warn` | 1/1，逐一删除/清空 core NOTICE、MPL 源码、原版 MIT 均拒绝 |
| `moon test scripts/release/release_gate.mbtx --deny-warn` | 2/2 |
| `moon test scripts/release/verify_candidates.mbtx --deny-warn` | 1/1 |
| `moon run scripts/check/check_automation.mbtx` | 根 build.mbtx 与 26 个维护脚本检查通过 |
| `moon run scripts/maintenance/stage_licenses.mbtx` 及 `check_licenses --bundle` | 候选目录及 npm 主包/Windows 包通过 |
| `fnm exec --using 22.21.1 moon run scripts/check/check_node_candidate.mbtx` | 两个真实 tarball 的许可检查、离线安装、6/6 同步消费、6/6 异步 Node 测试通过；复用已有 addon，未改 Native 源码 |
| `moon run scripts/check/check_moonbit_consumer.mbtx` | 独立 workspace 的 engine/Thin/Full 消费和源码许可清单通过 |
| `moon -C <外部候选目录> package --list` | 生成本地 Mooncakes zip；清单包含第三方材料、MPL 文本/数据/源码/生成器；源码候选去掉测试后出现 12 项已有 unused_package 警告，0 错误；没有 registry 发布 |
| `tar -czf ... -C target/candidate/cli <Windows CLI> licenses`；SDK 目录同样打包；`check_licenses --archive` | CLI 与 SDK 实际归档的许可/MPL 源码通过 |
| `moon info --target native`、`moon fmt`、显式脚本格式化、`git diff --check` | 通过；无 .mbti 变化；全仓 formatter 产生的无关源码排版已撤销，只保留本次脚本格式化 |

新增 Native 脚本测试编译时出现依赖 async 的 C4005 EINVAL 宏重定义警告，测试结果通过；未修改依赖缓存或隐藏警告。没有协议/FFI 实现修改，因此未重复完整 Native/ASan 行为矩阵。

本机打包检查产物 SHA-256（仅记录本次验证，非发布资产）：

| 产物（相对 target/） | SHA-256 |
|---|---|
| cli-full-windows-amd64-license-check.tar.gz | `2db82a820fad83733a64dfd458171757dd142eb7906dabd0111d5958d9daa50b` |
| cabi-windows-amd64-license-check.tar.gz | `f74dcc31e0d154b028a1e5d58950f6b381b7204b5cd824710913971bb50704dd` |
| candidate/node/unmbt-http-server-mbt-0.4.2.tgz | `3d1cfb4490b60c5558946b51a8ac02ecc3863eb80161537edcdbfc99bd3d8eba` |
| candidate/node/unmbt-http-server-mbt-win32-x64-msvc-0.4.2.tgz | `b777e7ab47255e47e8f03b7daf64b8cd123c1f5859b86098d4aa1543bab5d236` |
| candidate/moonbit-source.tar.gz | `2abdc723f971eec5bf1345eff03237115f95b2e1b250bfdb08aecc3c74da7e68` |

Linux/macOS 远程 Actions、四种 Docker 镜像和实际 registry 发布不在本次本机结果中；本机没有 Docker 可执行程序。不将这些未运行项记录为通过，不勾选跨平台总任务。现有安装脚本仍下载兼容的裸程序；完整许可归档随 GitHub Release 一起提供，README 明确要求转发裸程序时同时提供它。
