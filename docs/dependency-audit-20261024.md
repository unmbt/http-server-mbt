# wasm-gc / io_uring 依赖与许可审计（2026-10-24）

本审计覆盖 Node WasmGC 提交 `8fb666c19165f28f5a1dfc6b4138dd234c7ed49a`
及 io_uring 提交 `1621f4d2ab88e3d23deac07d302cffeba1fe6e0e`、
`fc36f85c9f5529813f9857cd2f15179a18f6773e`。结论是：没有引入新的第三方
包、vendor 源码、静态库或动态库，也没有新增需要随服务端产物携带的 CA
证书。新增的是宿主/操作系统能力，下面记录其边界和现有许可材料。

| 功能 | 实际输入 | 运行时/链接依赖 | 许可与分发结论 |
| --- | --- | --- | --- |
| Node WasmGC | `wasm` 包中的 `moonbitlang/core/json`、`moonbitlang/core/string` 和本仓库 `internal/static_plan`；Node 宿主使用 `node:fs/promises`、`node:http`、`node:stream`、`node:url`、`node:path`、`node:events`、`node:zlib` | 需要支持 WasmGC 的 Node 22.21.1 或 24.10.0；这些是用户提供的外部宿主，项目不打包 Node、V8、libuv 或 npm 依赖 | MoonBit core 的 `LICENSE`/`NOTICE` 随 `target/wasm/licenses/` 分发；项目 MIT 与本说明一并分发。若接收方另行分发 Node，须遵守 Node 自身的许可和 notice。 |
| Linux io_uring | `internal/native/native.c` 直接使用 `<linux/io_uring.h>`、`io_uring_setup`、`io_uring_enter` 和 `io_uring_register` | Linux 内核提供的 syscall/UAPI；Linux 5.1+ 才可能可用，受 `ENOSYS`、`EPERM`、opcode 或 sandbox 限制时按设计回退/失败；不链接 `liburing` | 没有新增第三方库许可文本。UAPI 头文件是目标 Linux 工具链/系统提供的编译期输入，不作为运行时文件复制；默认三平台构建不产生 `liburing` 传递依赖。 |
| Native benchmark | `benchmarks/clock.c` 使用 Windows `QueryPerformanceCounter` 或 POSIX `clock_gettime(CLOCK_MONOTONIC)` | Windows/POSIX 系统 API；仅用于观测型 benchmark，不进入服务端库或 Wasm 产物 | 无新增第三方材料；系统 API 的许可由操作系统/SDK 承担。 |

`moonbitlang/async@0.21.3` 仍是根模块既有的 Native 和 `.mbtx` 构建脚本依赖，
不是上述提交新增的依赖；`wasm/moon.pkg` 不导入它，Wasm 运行时也不链接
Native async、TLS、Mbed TLS、Mozilla CA bundle 或 Node-API addon。

Wasm 可搬移目录现在包含：

- `LICENSE`：本项目 MIT；
- `licenses/THIRD_PARTY_NOTICES.md`：项目级第三方边界声明；
- `licenses/WasmGC-DEPENDENCIES.md`：本审计的分发副本；
- `licenses/MoonBit-core-LICENSE.txt` 与 `licenses/MoonBit-core-NOTICE.txt`：实际工具链 core 材料。

这组文件描述的是当前 Wasm 形态实际使用的材料，不把 Full Native 的 TLS/CA
许可误写成 Wasm 的链接依赖。io_uring 的完整能力、Linux 可用内核和三平台
Actions 运行结果仍由 T-023/T-037 负责，依赖审计本身不替代这些运行验收。
