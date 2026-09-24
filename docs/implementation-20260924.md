# 七项实施与证据（2026-09-24）

关联 T-005/T-007/T-012～T-018/T-021/T-022/T-025～T-028/T-030/T-032～T-035。实现中；以下记录不构成总任务完成。

基线：提交 `2ba8a47`，Windows x86_64，Moon 0.1.20260920、moonc 0.10.14、async 0.21.3；`moon check --target native` 0 错误 506 警告；`moon test --target native` 240/240。工作区开始时干净。

用户确认：允许下一次次版本 MoonBit 源码不兼容迁移；Full 内嵌 Mozilla CA，显式 CA 替换；本轮不实施 C/Node 异步嵌入、io_uring、wasm-gc 引擎，不发布 registry。远程 Actions 结果、完整发行和范围外任务须分别记录。

实施顺序：规范状态 → 安全句柄及生命周期 → 有界资源/目录/传输 → TLS/WebSocket → 打包/消费/故障回放 → 本机与远程证据。

## 本机分项记录（尚未形成候选提交）

所有结果来自 Windows x86_64、基线 `2ba8a47` 上的未提交工作树；不是该基线提交的测试结果。Moon 0.1.20260920、moonc v0.10.14+7d59c7ec9、async 0.21.3。Actions run/job：尚未执行；表中结果不替代三平台门槛。

| 任务/能力 | 命令和实际结果 | 限制 |
|---|---|---|
| T-005/T-033 回归建立 | 旧实现的 N-20 If-Range、截断用例 2/2 失败；新实现 2/2 通过 | Windows |
| T-005/T-015/T-018 文件 lease、关闭、目录流 | `moon test --target native` 在共享 framing/目录客户端迁移后 246/246 通过 | 后续新增测试和修改需最终复验 |
| T-015/T-033 生命周期/修改 | `moon test --target native engine_lifecycle_test.mbt` 5/5；`engine_links_test.mbt` 1/1 | 替换、删除、同长度/增长/截断、最终 EOF、根内/外 junction、回退隔离 |
| T-004 framing | `moon test --target native internal/framing` 2/2 | 定长/chunk trailer/pipeline、TE/CL、重复长度、报头限额 |
| T-012/T-014 WebSocket | `moon test --target native full/websocket_matrix_test.mbt` 1 个参数矩阵通过（四种明文/TLS 组合） | 显式本地 CA、子协议、控制/分片/二进制字节、预读保留；长消息/停机继续补测 |
| T-034 C 资源排空 | `moon run scripts/check_native_sanitizers.mbtx` Windows Clang 22 ASan 通过；种子 `0x2442cafe`，128 轮，1764 接纳、284 拒绝、874 取消 | 实际调度决定计数；Windows 不支持 LeakSanitizer；Unix ASan/UBSan 尚未执行 |
| T-020/T-027 C ABI | `moon run scripts/build_cabi.mbtx` Thin/Full 静态/动态 C 消费者共 4 项通过，DLL 仅 5 项 hs_* 导出 | MSVC 14.44.35207、Windows SDK 10.0.22621；仅完整服务器旧接口，真实请求/其他宿主继续补测 |

原 C ABI 脚本收集共享构建目录中残留对象，已改为 `target/cabi-build` 独立目录；缺失/失败的符号剥离现在直接报错。曾观察到重复定义及导出 290 项的失败，两者均由实际链接/导出检查检出，修复后上述 4 项通过。

此次 DLL 结果：Thin 1,451,520 bytes，SHA-256 `173a9f399974d4b61221d9cc0c7617d9796dc5fb124df369bc21a33461070396`；Full 3,470,336 bytes，SHA-256 `007fb3aae50bb3a00f4b0100dae8583f3853abe7b27a56377a69e55bf60919e2`。这是中间工作树产物，后续源码变化后须重建，不用于发行。

新增 N-22 追踪共享 framing/WebSocket 字节流；N-23 追踪资源预算。既有 N-21 继续追踪生命周期/故障不变量，不重排原编号。

## 待验收

三平台 Actions、Linux musl/四组合镜像、完整外部消费者、长时故障探索和候选清单仍未验收。工具链告警清理、共享 CLI、打包与门槛仍在实施。T-025/T-034 及其他多平台总任务保持未勾选。C/Node 异步嵌入、io_uring、wasm-gc 引擎保留最终发行约束。

## 99ef485 后续 CI 修复（R-N13、D-08/D-11/D-15/D-16、T-020/T-022/T-025）

99ef485 之后的三平台候选工作流出现工具链及构建驱动错误。以下记录仅针对候选验证，不改变上述未完成任务的总状态。

| 提交 / Actions run | Windows x86_64 | Linux x86_64 | macOS arm64 | 汇总 |
|---|---|---|---|---|
| `8b95fe2` / [36001995029](https://github.com/unmbt/http-server-mbt/actions/runs/36001995029) | Native 263/263、wasm-gc core 28/28；sanitizer 缺 MoonBit 头路径 | Native 263/263、wasm-gc core 28/28、ASan/UBSan 回放通过；musl 归档器名错误 | Native 263/263、wasm-gc core 28/28；LLVM clang 缺 Xcode SDK | native 三项失败，gate 未运行 |
| `0da7ef6` / [36004622793](https://github.com/unmbt/http-server-mbt/actions/runs/36004622793) | sanitizer 回放通过；后续继续推进 | sanitizer 回放通过；musl 缺内核 UAPI 头 | Apple clang 编译通过；系统不支持 ASan leak 检测 | native 三项失败，gate 未运行 |
| `6a5060c` / [36008629525](https://github.com/unmbt/http-server-mbt/actions/runs/36008629525) | native job 通过 | native job 通过，含 musl 静态 CLI、四种 Linux 容器候选 | native job 通过，含 C/Rust/Python 与 Node 消费 | 三份候选 artifact 已上传；gate 对 manifest 的 `dirty` 判定失败 |
| `8355b38` / [36010910505](https://github.com/unmbt/http-server-mbt/actions/runs/36010910505) | native job 通过 | native job 通过；诊断确认未跟踪的 `llvm/` 来自 LLVM 安装 Action | native job 通过 | gate 同样拒绝脏 manifest；修复为将 LLVM 安装到 `runner.temp` |
| `2ae484d` / [36012285236](https://github.com/unmbt/http-server-mbt/actions/runs/36012285236) | [native Windows x86_64](https://github.com/unmbt/http-server-mbt/actions/runs/36012285236/job/107675763196) 通过 | [native Linux x86_64](https://github.com/unmbt/http-server-mbt/actions/runs/36012285236/job/107675763389) 通过 | [native macOS arm64](https://github.com/unmbt/http-server-mbt/actions/runs/36012285236/job/107675763396) 通过 | [candidate-gate](https://github.com/unmbt/http-server-mbt/actions/runs/36012285236/job/107678389526) 通过；同提交、三平台候选清单及逐文件 SHA-256 校验成立 |

最后一次运行的三份上传 artifact SHA-256：Linux X64 `47c3c36d11d7cdc675fa1db45114b42e5c065b4489154050eff380d89f4885b1`，Windows X64 `e5c41119cf006c5fb04891988c594a133d52002c35a3e6a592157697f16bc50c`，macOS ARM64 `09cafd328909046ac4a0d4956d79bb08f5240e86bbec1aabc1a4b2ab4d98286d`。gate 从 Actions 下载并重新核对 artifact digest，随后验证三份 manifest 的提交、平台、干净工作树、文件大小和 SHA-256。候选验证通过不等于 registry 发布、完整发行或 T-025 总任务完成。

本机 Windows，Moon 0.1.20260920：`moon run scripts/check_automation.mbtx`、`moon check --target native --deny-warn`、`git diff --check` 通过。`moon test --target native --deny-warn` 曾 261/263，两条句柄计数断言各差 1；分别重跑相关测试文件 7/7、7/7 通过。完整测试结果以同一提交的 Actions job 为准，本机波动仍须单独追踪。修复保留在草稿 PR #2；T-025 涵盖的最终发行范围尚未全部完成，不因候选 gate 通过而勾选。
