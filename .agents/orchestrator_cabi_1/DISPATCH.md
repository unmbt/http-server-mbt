# DISPATCH

## 2026-09-18T13:11:07Z
Task Assignment: Project Orchestrator — C ABI Export Pipeline (thin & full)

Objectives:
基于已完成的架构解耦与 CLI 双版本打包基础（详见 docs/cli-thin-full-and-cabi-handover.md），在 MoonBit 项目 http-server-mbt 中设计并实现 thin 与 full 双版本 C ABI 动静态库导出流水线，包括纯净 hs_* 符号导出控制、.mbtx 驱动的动静态库构建脚本、以及独立的 C 语言消费程序验证。

Key Requirements:
1. R1. C ABI 桥接层与符号纯洁性（C ABI Interface & Symbol Isolation）:
   - 依据 D-07 与 D-11 的 hs_* 规范：创建 C 桥接包，导出纯 C 头文件（http_server.h）与 hs_* 接口（hs_abi_version, hs_server_start, hs_server_stop, hs_error_copy 等），不暴露 MoonBit 托管对象或内部 runtime 布局。
   - 分别支持 thin（纯静态 HTTP 服务器，零加密 C 依赖）与 full（集成 TLS 传输层与代理能力）两组导出实现。
   - 建立导出符号隔离控制机制（Windows 使用 .def 文件或显式导出标记）：确保动态库与静态库中严禁包含 CLI main 入口符号，严禁泄露未授权内部符号；thin 库中绝对不包含任何 MbedTLS / PSA-Crypto 符号。

2. R2. 纯 .mbtx 驱动的动静态库构建流水线（Build Pipeline）:
   - 编写自动化构建驱动脚本（scripts/build_cabi.mbtx），驱动本地编译器与归档器（如 clang / cl / lib.exe / llvm-ar）。
   - 自动化完成 MoonBit 对象文件编译生成与中间目录解析。
   - 构建导出 thin 版本的动态库（Windows hs_min.dll + hs_min.lib）与静态库（Windows hs_min_static.lib）。
   - 构建导出 full 版本的动态库（Windows hs_full.dll + hs_full.lib）与静态库（Windows hs_full_static.lib）。
   - 产物输出至固定发行目录（如 target/cabi/），并提供清晰的构建日志与产物清单。

3. R3. 独立 C 语言消费者编译与运行验证（C Consumer Smoke Tests）:
   - 在 testdata/c_consumer/ 创建独立的 C 测试程序。
   - 编写独立的 C 代码，分别通过动态链接（引用 hs_min.lib / 加载 hs_min.dll）与静态链接（引用 hs_min_static.lib）进行编译。
   - 在 Windows 本机执行 C 测试程序，验证调用 hs_abi_version() 正确返回预期版本号，验证服务配置与生命周期调度无崩溃、无内存访问违规。
   - 确保全仓既有 228 项 MoonBit 测试持续保持 100% 通过（0 回归、0 警告）。
