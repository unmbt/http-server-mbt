<!-- CODEGRAPH_START -->
## CodeGraph

In repositories indexed by CodeGraph (a `.codegraph/` directory exists at the repo root), reach for it BEFORE grep/find or reading files when you need to understand or locate code:

- **MCP tool** (when available): `codegraph_explore` answers most code questions in one call — the relevant symbols' verbatim source plus the call paths between them, including dynamic-dispatch hops grep can't follow. Name a file or symbol in the query to read its current line-numbered source. If it's listed but deferred, load it by name via tool search.
- **Shell** (always works): `codegraph explore "<symbol names or question>"` prints the same output.

If there is no `.codegraph/` directory, skip CodeGraph entirely — indexing is the user's decision.
<!-- CODEGRAPH_END -->

# Project Agents.md Guide

This is a [MoonBit](https://docs.moonbitlang.com) project.

You can browse and install extra skills here:
<https://github.com/moonbitlang/skills>

## SDD workflow

本项目采用规范驱动开发。开始任务前阅读 [proposal](docs/proposal.md)、[design](docs/design.md) 和 [tasks](docs/tasks.md)，确认涉及的需求 ID、设计章节、测试案例及依赖任务。规范基线建立于 2026-09-09，当前修订为 2026-09-10 的版本 4；规范存在不代表实现完成。

1. **需求与行为契约**：在 proposal 中记录需求、兼容目标及可测量验收条件。已有用户指令和确认持续有效，不为每个常规步骤重复请求批准。
2. **设计**：公开接口、默认值、配置组合、路由顺序、ABI、资源生命周期或平台承诺发生变化时，先同步 design 中对应 D 编号，记录理由和受影响案例，不能通过改测试暗中改变契约。
3. **任务**：在 tasks 中建立/更新 T 编号、依赖、交付物、验收标准及状态；复用已有任务，避免重复路线。不得删除失败或难以实现的需求以获得通过率。
4. **实现与测试**：每次变更关联 R/D/T 编号；回归缺陷先建立可失败的案例，新公开 API 增加黑盒测试和文档示例。按任务范围修改，保持包职责及 Native 边界清晰。
5. **验证证据**：记录执行命令、工具链、平台、结果及失败/未运行原因。只有交付物与验收条件均满足才能勾选任务；编译成功和文档写完不能代替行为验证。

原版兼容基线是 `http-party/http-server` 提交 `0d3b7bb5b6e8a59fd450ae2dca65870009cfcd8b`。本地 `http-server/` 为被忽略的参考仓库，不修改它来让测试通过；fixtures 和许可证固定按 T-001 执行。原版源码/断言优先于参考分析，已确认的新行为以 design 的差异记录为准。迁移矩阵中的平台跳过必须说明原因，不能静默减少分母。

R 编号属于需求，D 编号属于设计，T 编号属于任务；C 编号属于原版迁移案例，CC/CE 属于共享 fixtures，N 编号属于新增测试，P 编号只保留原性能计划的历史追踪。编号发布后不重新排序或复用；用户确认撤出的项注明范围和日期，移除其当前依赖/门槛，不冒充已完成。

任务状态只使用 `未开始`、`进行中`、`阻塞`、`已完成`。前三者保持 `- [ ]`；已完成使用 `- [x]` 并附证据。阻塞时记录缺失条件及仍可独立推进的工作，不以占位实现或未运行测试冒充完成。新的产品取舍超出已确认范围时才向用户澄清。

开发按 D-16 先在 Windows 本机跑固定原版基线，再完成 T-031 的 IOCP/TransmitFile 静态传输，随后由 T-032 建立 GitHub Actions 三平台基础矩阵，T-025 完成全功能测试/打包/发行门槛。多平台任务允许以“任务 ID + 平台 + 能力 + 证据”交付分项并推进依赖工作，不必等待无关平台、TLS 或 ABI 实验；总任务仍须全部验收后勾选。Windows 起步不缩减 Linux/macOS 的最终支持，也不另建性能演示服务器。

保证高性能，先完成单进程高效 I/O；多核可以作所有权隔离的实验，不作为首轮前置条件。版本 4 已撤出量化性能目标、P 计划和 T-024 的专项基准交付；当前只按高效设计及功能/资源正确性验收，不追加未确认的指标端点或基准门槛。

## Native / FFI rules

- 执行前加载 `moonbit-agent-guide`；Native FFI/C ABI 任务另须阅读 `moonbit-c-binding` 技能，遵循所有权、C 桥接、回调和 AddressSanitizer 检查要求。以本地工具链/API 查询核实语法，使用当前 `moon.mod` / `moon.pkg` 格式。
- MoonBit 负责协议与业务，C 负责系统调用和 ABI 桥接。跨调用存储的指针不能声明为仅调用期借用；文件、socket、异步操作和缓冲必须有明确所有者及取消后释放时点。
- 不将 MoonBit 字符串、托管对象布局或异常直接暴露给 C ABI；遵循 design 的版本、UTF-8、线程和错误码约定。
- 三平台共同验收；Linux 完全静态与 macOS/Windows 系统库依赖分别描述。TLS/动态输出/宿主不支持的场景使用有界缓冲，不假称全路径零拷贝。
- 不手改 `.mooncakes/` 或生成产物；依赖/工具链版本与许可证变动需同步设计、任务和验证证据。
- 静态库、动态库与 Node-API 插件复用同一 C ABI。先执行 T-002 的工具链可行性验证，不把 Native 的源码导出声明当作已支持可链接库产物；静态库须标明 target、CRT、PIC、runtime 和传递依赖。
- 默认由库托管事件循环：宿主只配置启动/停止完整服务，或提交请求并将异步正文接到已有框架；公开 pump/run/poll 下沉内部，文件读取、通知、取消和关闭排空由库负责。正常异步等待结果不等于要求宿主驱动循环。
- C ABI 的 owner/通知线程由库管理，公共入口以 C 拥有的队列接收并发命令；MoonBit 直接消费使用其合法异步上下文，禁止跨 runtime 迁移托管对象。Node 只映射库异步结果并遵循 napi_env 清理，不另建引擎轮询线程；Bun/Deno 支持须另有验证。
- Mooncakes 公共包可以直接作为 MoonBit 静态文件库引入，不依赖 CLI、npm 或预编译 C 库。包名、公开类型归属、目标后端和发布资源遵循 D-14，并用独立消费模块验证。
- Native 生产后端与 wasm-gc 实验核心分开声明。共享逻辑不得导入 Native-only I/O 或包含可达的未实现 abort；wasm-gc 适配器自动提交宿主完成事件，应用无需手动调度，宿主 I/O 不意味着具有 Native 零拷贝能力。
- 下载遵循 D-17：绑定已打开文件，检测原地修改/截断即终止响应并自动取消排空；FILE_CHANGED 不当成正常 EOF，支持自动重试的客户端必须丢弃旧响应并从偏移 0 重试，不拼接不同版本。写入者无需协调下载，服务不主动阻止写入，也不要求旧版本保留/发布快照；记录检测能力边界。

## Automation and verification

- Agent 编写的自动化逻辑只使用 `.mbtx`。shell 可直接运行 `rg`、`git`、`moon`、编译器等命令，不在 shell/Python/JavaScript 中另写自动化循环、解析器或构建驱动。现有安装脚本不因本规范而自动重写；Python/C 嵌入产品示例不属于自动化驱动。
- 优先 `moon ide doc` / `outline` / `peek-def` / `find-references` 进行 API 探索；无 CodeGraph 时文本/文件搜索使用 `rg`。
- MoonBit 代码变更运行 `moon check --target native` 和相应的 `moon test --target native`，最终运行 `moon info --target native`，再运行 `moon fmt`，审查 `.mbti` 和格式差异；格式化有实质改动时重跑相关检查。在 PowerShell 中可分别执行，无需依赖 `&&`。
- `pkg.generated.mbti` 必须由 `moon info` 生成，禁止手动编辑。快照更新只用于预期输出变更，并审查差异，不能覆盖失败断言以掩盖回归。
- FFI/传输任务补充适用的 ASan/UBSan、取消/断连/泄漏测试；发布任务验证 ELF/Mach-O/PE 依赖、干净环境启动与容器行为。仅测试本次变更相关风险，不机械重复已通过检查。
- 状态机必须具备 D-18 的故障注入与模糊测试：协议随机分片、短写、文件变更、取消晚完成、句柄复用和关闭/回调竞态，保存种子/事件序列与最小复现，三平台 Actions 回放语料。拒绝接纳无回调、接纳后恰好一次最终完成和关闭后无业务回调须明确验证。
- 纯文档修改核对相对链接、稳定编号、42 文件迁移覆盖及跨文件契约，不运行会改写接口或源码的 `moon info` / `moon fmt`，不把“无源码可运行”记录为测试通过。
- 库/包变更补充外部 C/Rust 静态链接、Node 生命周期及 Mooncakes 干净消费验证；可移植核心另运行明确范围的 wasm-gc 检查/测试，不强迫 Native-only 包执行所有后端。模块元数据支持范围不能比实际包能力更宽；候选包验证、registry 发布和发布后拉取是不同证据。
- 三平台兼容性、原生传输、资源检查、测试、打包和库/宿主消费必须接入 GitHub Actions；最终完成证据包含实际 OS/CPU、提交、run/job 链接及产物哈希。初期本机验证可先推进，三平台工作流缺失或必需检查失败时不得宣称完整交付。
- Docker 遵循 D-15：min/full 对应精简/完整 CLI，默认 Distroless static nonroot 并保留 scratch 变体；固定基础层 digest，四种组合在 Linux Actions runner 验证。产物/依赖清单分别记录，容器测试不代替 Windows/macOS Native 验收。
- GitHub Actions YAML 与 Dockerfile 允许作为声明文件；其中的自动化循环、解析及构建/测试驱动逻辑仍使用 `.mbtx`，与 Windows 本机复用。验证 job 上传候选产物，发行 job 按同一提交的必需检查门槛发布；不能用无条件跳过、continue-on-error 或空测试伪造通过。

## Project Structure

- MoonBit packages are organized per directory; each directory contains a
  `moon.pkg` file listing its dependencies. Each package has its files and
  blackbox test files (ending in `_test.mbt`) and whitebox test files (ending in
  `_wbtest.mbt`).

- In the toplevel directory, there is a `moon.mod` file listing module
  metadata.

## Coding convention

- MoonBit code is organized in block style, each block is separated by `///|`,
  the order of each block is irrelevant. In some refactorings, you can process
  block by block independently.

- Try to keep deprecated blocks in file called `deprecated.mbt` in each
  directory.

## Tooling

- `moon fmt` is used to format your code properly.

- `moon ide` provides project navigation helpers like `peek-def`, `outline`, and
  `find-references`. See $moonbit-agent-guide for details.

- `moon info` is used to update the generated interface of the package, each
  package has a generated interface file `.mbti`, it is a brief formal
  description of the package. If nothing in `.mbti` changes, this means your
  change does not bring the visible changes to the external package users, it is
  typically a safe refactoring.

- For MoonBit code changes, finish with `moon info --target native`, then
  `moon fmt`, and review the `.mbti` diff. Use separate commands in PowerShell;
  documentation-only changes follow the exemption above. Check the portable
  core separately with its supported target when changing wasm-gc behavior.

- Run `moon test` to check tests pass. MoonBit supports snapshot testing; when
  changes affect outputs, run `moon test --update` to refresh snapshots.

- Prefer `assert_eq` or `assert_true(pattern is Pattern(...))` for results that
  are stable or very unlikely to change. For snapshot tests that record
  structured debugging output, derive `Debug` and use `debug_inspect`, rather
  than deriving `Show` for debugging. For solid, well-defined results (e.g.
  scientific computations), prefer assertion tests. You can use
  `moon coverage analyze > uncovered.log` to see which parts of your code are
  not covered by tests.
