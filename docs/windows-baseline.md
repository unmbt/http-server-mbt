# Windows baseline evidence

本轮实现针对 Windows x86_64 Native，保留固定原版仓库 `http-party/http-server` 提交
`0d3b7bb5b6e8a59fd450ae2dca65870009cfcd8b`（14.1.2）。参考目录 `http-server/` 未修改。

工具链：Moon `0.1.20260904`、Node `v26.4.0`、npm `11.17.0`、clang `22.1.3`。
原版 checkout 没有 `node_modules`，因此 Node 测试未运行；这是基线阻塞证据，不计为通过。

已实现 Windows 可用分项：

- `core`：BaseURL 归一化、路径遍历/反斜杠/NUL 拒绝、Range 解析。
- 根静态引擎：GET/HEAD、query 剥离、默认 `.html`、MIME、404、Range 206/416、gzip/Brotli 预压缩选择、ETag/304、缓存头和有界响应读取。
- `server`：基于 `moonbitlang/async/http` 的 Windows Native listener，生命周期 `stop` 和托管 `with_server` 入口。
- CLI：基于 `moonbitlang/core/argparse` 的位置参数 root、`--port`/`PORT`、`--base-url`、帮助/版本和 Native async 主入口；参数错误在监听前报告。

验证命令（Windows PowerShell）：

```text
moon check --target native
moon test --target native
moon info --target native
moon fmt
```

结果：5 个 MoonBit 测试全部通过；Native 检查和接口生成成功。async 依赖的 Windows IOCP
源码参与构建，TransmitFile/取消状态机和文件 lease 尚未接入，故 T-031 仅完成静态引擎/HTTP
基础分项，不能宣称三平台 T-016/T-017 或完整 42 文件兼容。

Release 构建：`moon build --target native --release` 成功。可执行文件为
`_build/native/release/build/cmd/http-server-mbt/http-server-mbt.exe`，SHA-256
`3D34DB18F24959DBBE7676E9D28FC04056AA9799FE2502C7E0B9B280E814A42C`。
CLI 冒烟验证：`--help` 输出 argparse 帮助，`--version` 输出 `http-server-mbt 0.1.5`，
`--port nope` 在创建监听器前报告 `error: invalid port`。
Ctrl+C 取消服务时不再打印 `server error`；事件循环按信号路径结束进程。

未实现并显式保留：TLS、代理、WebSocket、认证、SPA/try-files、正式 C ABI、三平台 Actions、
目录渲染完整兼容、文件变更中断/重试和 TransmitFile 零拷贝传输。
