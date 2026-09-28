# 2026-09-28 tag 自动发布修复

关联 R-N09/R-N11/R-N13、D-08/D-14/D-16、T-025/T-028/T-030、N-18。基线提交 `619a05de639853fc655410a5b9e35dc2664e61d7`；本记录描述未提交工作区验证，不代表远程发布成功。

## 行为

`v*` push → tag/版本预检 → 复用三平台 Candidate acceptance → 清单/哈希/同 run 校验 → npm 与 Mooncakes → GitHub Release。手动选择 tag 也可启动同一路径；master 不能手动发包。发布 job 通过 needs 等待验证，不使用 continue-on-error 或无条件跳过。

按用户确认，日常版本发布移除全部 T 任务勾选与 `full_release_ready=true` 条件。Native/资源/sanitizer、Node 22/24、干净外部消费、Linux 四容器和三平台哈希门禁保留；总任务、未实现 io_uring/wasm-gc 引擎与最终重构审计继续追踪，清单的 full_release_ready=false 保留为范围说明。

发行消费原始 npm tarball 与 Linux 的 MoonBit 源码候选。npm 先三平台包后主包，发布前核对包名、版本及精确平台依赖；预发行用 next。重试只跳过 registry 中 SHA-1 相同的 tarball，网络/认证失败和内容冲突均失败。Mooncakes 独立 job 写入临时凭据、发布后清理。GitHub Release 保留安装脚本要求的六个 CLI 文件名，将 SDK/证据按平台归档，避免重复 basename 冲突。候选清单现在包含之前被宽泛 moonbit-* 过滤器遗漏的 moonbit-consumer.txt；验证拒绝清单外文件。

凭据及操作见[脚本入口](../scripts/README.md)。新增流程使用 repository secrets，不引用需人工审批的 release environment。npm Trusted Publisher 的 workflow 需为 release.yml；也支持 NPM_TOKEN。Mooncakes 使用 MOONCAKES_CREDENTIALS。

## 本机验证

Windows x86_64；Moon 0.1.20260920 (914d7da)、moonc v0.10.14+7d59c7ec9。所有测试均未调用真实 registry 发布。

| 命令 | 结果 |
|---|---|
| `actionlint 1.7.7 -shellcheck= -pyflakes= .github/workflows/release.yml .github/workflows/cli.yml` | 通过；GitHub YAML/表达式/job 依赖检查 |
| `moon test scripts/release/release_gate.mbtx --deny-warn` | 2/2；错误 ref/版本/提交、缺失发布文件拒绝；完整重构标志为 false 不阻塞日常发布 |
| `moon test scripts/release/publish_npm.mbtx --deny-warn` | 2/2；已发布同哈希跳过、404 可发布、不同哈希/401/超时/缺失元数据拒绝、包身份及依赖验证 |
| `moon test scripts/release/verify_candidates.mbtx --deny-warn` | 1/1；真实临时文件哈希检查，篡改、错提交/版本、dirty、清单外文件和缺失平台均拒绝 |
| `moon run target/release_smoke.mbtx`（本地临时驱动） | 独立临时 Git 仓库及三平台合成产物运行真实 gate：tag 预检通过、整理出 14 个附件；异源 run 与 master dispatch 拒绝。合成产物仅测试编排，不代表真实三平台构建；未调用 registry |
| `moon run scripts/check/check_automation.mbtx` | 根 build.mbtx 与 25 个维护脚本类型检查通过 |
| `moon check --target native --deny-warn` | 通过 |
| `moon test --target native --deny-warn` | 266/266；依赖 C 编译仍有既有 EINVAL 宏重定义警告 |
| `moon info --target native` | 通过，生成 .mbti 无差异 |
| `moon fmt` 及变更 .mbtx 格式化 | 已执行，恢复无关历史源码格式变化；仅保留本次脚本变更 |
| `git diff --check` | 通过 |

发布脚本回归已经接入现有三平台候选驱动。尚未执行修复提交的远程 Actions、registry 发布及发布后 registry 消费，未检查仓库 secrets/npm Trusted Publisher 设置。本地测试不能替代这些证据，T-025/T-028/T-030 总任务与自动发布远程分项保持进行中。
