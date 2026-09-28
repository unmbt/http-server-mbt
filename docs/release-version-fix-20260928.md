# 2026-09-28 发版版本一致性修复

关联 R-N02/R-N11/R-N13、D-08/D-14/D-16、T-025/T-030、N-18。本记录是 Windows 本机分项证据，不代表三平台完整发行验收。

## 原因与修复

`daec402209dcc93e32c1da66e1f4b991b40dc697`（`release: v0.4.0`）的 [Candidate acceptance #29](https://github.com/unmbt/http-server-mbt/actions/runs/36402363586) 三个 native job 失败，candidate-gate 跳过。完整远程日志需要登录，本次未取得，不能据此认定三个 job 只有同一种错误。

本机运行旧 `moon run scripts/build/build_cli.mbtx`，release 编译成功后，在原第 100 行复现 `"0.4.0" != "0.3.4"`。CLI 检查硬编码旧版本；干净 MoonBit 消费驱动及示例也残留旧依赖版本。

- [版本生成器](../scripts/maintenance/gen_version.mbtx) 复用同一 `moon.mod` 解析器。新增 `--print`、`--consumer`、`--sync`、`--check`；原构建钩子的两个路径参数保持可用。拒绝缺失、空值、无引号及重复版本行。
- `--sync` 同步 CLI 生成源码、npm 主包与三平台包、主包精确可选依赖和消费示例。先计算全部修改，再写入；已一致的内容保持不变。`--check` 发现漂移报错，绝不自动修复 CI checkout。
- CLI 的 `--version` 断言和独立消费模块依赖来自当前版本，移除生产脚本内的 `0.3.4` 常量。
- [候选验收](../scripts/check/validate_candidate.mbtx) 在构建前执行版本检查和脚本回归，现有三平台 workflow 自动覆盖。
- 候选清单增加 `version`；汇总核对当前版本，发行还要求 tag 等于 `v<version>`。同提交、哈希、原任务及 `full_release_ready` 门槛保持有效。

## 验证

环境：Windows 11 x86_64，OS 10.0.26200；Moon 0.1.20260920（914d7da），moonc v0.10.14+7d59c7ec9，moonrun 0.1.20260920。基线提交为上述 `daec402`，修复在未提交工作区执行。

| 命令/检查 | 结果 |
|---|---|
| 修复前 `moon run scripts/build/build_cli.mbtx` | 失败，精确复现 0.4.0/0.3.4 断言 |
| `moon run scripts/maintenance/gen_version.mbtx --check`（同步前） | 失败，报告消费示例仍为旧版本；文件未被改写 |
| `moon run scripts/maintenance/gen_version.mbtx --sync`，随后 `--check` | 通过；本仓库只需同步消费示例，其余元数据已为 0.4.0 |
| `moon test scripts/maintenance/gen_version.mbtx --deny-warn` | 2/2；独立夹具连续升级 0.3.4、0.4.0、1.2.3-rc.1、2.0.0，验证所有版本、npm 精确依赖、无关字段保留、幂等、只读失败及错误元数据 |
| `moon run scripts/check/check_automation.mbtx` | 根 build.mbtx 与 22 个维护脚本全部通过 |
| `moon check --target native --deny-warn` | 通过 |
| `moon test --target native --deny-warn` | 266/266；C 编译有依赖中既有 EINVAL 宏重定义警告，不是 MoonBit 警告或失败 |
| `moon run scripts/build/build_cli.mbtx` | Full/Thin release 构建、当前版本断言、help、Thin 不支持参数拒绝及 PE imports 检查通过 |
| `moon run scripts/check/check_moonbit_consumer.mbtx` | 新临时 workspace 的 engine / Thin / Full 外部消费通过，依赖当前 0.4.0 源码候选 |
| `moon info --target native` | 通过，`.mbti` 无差异 |
| `moon fmt` 与七个变更 `.mbtx` 的格式检查 | 已执行；全仓格式化产生的无关历史格式变更已恢复，仅保留本任务文件；变更脚本 `moon fmt --check` 通过 |
| `git diff --check` | 通过；C001～C042、CC/CE 迁移矩阵和稳定编号未改动 |

本机 CLI SHA-256：

- Full：`D2E38B2EBF4DCB6FFEEDE9416A3BAA1637490CE5AA08E9CCD73AEA4957CA1406`
- Thin：`3FBF4C0FB3772A0BEE3A08DD75203396CE27E56FACC0AB0BA613126EB09ED16B`

未重跑的范围：Linux/macOS、远程 Actions、Docker、完整 sanitizer/Node 22/24/C/Rust 发布消费矩阵、正式发行和 registry 发布。此次没有变更协议、Native/FFI 实现或库 API，未把脚本检查或本机成功当作这些能力的新证据。

## 后续发版

操作说明见[脚本入口](../scripts/README.md)。修改 `moon.mod` 后先同步版本、审查并提交；三平台候选通过后，使用同一提交/版本的 tag、run 和产物。当前 `v0.4.0` tag 指向旧提交，不能混用修复后的候选；本次未移动 tag、推送或发布。

同日按用户要求接入现有 `moon-bump`：日常使用 `moon-bump` 或 `moon-bump --release patch`，不再要求手工改 `moon.mod` 后另行同步。[bump.config.json](../bump.config.json) 保留 npm 清单，增加 CLI 生成版本，并把原 `moon check` execute 替换为 [prepare_release.mbtx](../scripts/maintenance/prepare_release.mbtx)。该钩子先同步派生文件，再只读检查版本并执行 Native 类型检查；检查成功后，工具才继续原有提交/tag/push。上面的手工命令保留用于排错和修复漂移。

`moon-bump 0.1.3` 集成实测（同一 Windows/Moon 环境）：

- 使用临时 `.mbtx` 驱动将当前跟踪/非忽略源码复制到独立临时目录，初始化本地 Git；实际调用 `moon-bump --release <version> --yes --no-commit --no-tag --no-push --no-git-check --no-print-commits`，只测试临时副本。
- `0.4.0 → 0.4.1 → 0.5.0-rc.1` 两次通过；工具报告替换根模块、四个 npm 清单、CLI 生成版本，并实际执行新钩子。`--check` 通过；消费示例的项目依赖对应新版本，自身仍为 `0.0.0`。
- 在临时副本注入真实 MoonBit 类型错误，再以允许 commit、禁止 tag/push 的配置运行升版；返回失败，诊断包含注入的源文件，Git 中未出现 release commit。未用空钩子替代类型检查。
- `moon run scripts/maintenance/prepare_release.mbtx` 在原工作区通过；维护脚本数量增至 23，全部类型检查通过；原版本回归仍为 2/2。
- 临时副本已清理，原工作区保持 `0.4.0`，没有实际提交、tag、推送或 registry 发布。

正式工作流仍检查 T-001～T-035（明确撤出的 T-024 除外）以及 `full_release_ready=true`。当前总任务尚未全部完成、清单仍为 false，因此修复版本回归不等于已具备完整正式发布资格，也不自动触发正式发布。
