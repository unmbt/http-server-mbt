# 测试布局与运行

原版兼容范围及稳定编号见 [tasks](../docs/tasks.md)，行为契约见 [design](../docs/design.md)。原有 265 项 Native 测试在本次路径整理中保留；包内测试名称的阶段前缀改为行为描述，断言和 C/N 编号保持。

| 位置 | 内容与隔离边界 |
|---|---|
| 各源码包的 `*_test.mbt` | 包的黑盒测试；同包辅助函数放专门的测试文件 |
| 各源码包的 `*_wbtest.mbt` | 需要访问内部实现的白盒测试，保持在原包 |
| `resources/budget/` | 共享资源预算探针，独立 Native 测试进程 |
| `resources/preflight/` | 预检句柄探针，独立进程且包内串行，零净增长容差 |
| `consumers/c/` | Thin/Full 静态和动态 C 消费程序 |
| `consumers/rust/`、`consumers/python/` | Rust 静态链接与 Python 动态库消费 |
| `consumers/moonbit/` | 独立 MoonBit 模块模板，由检查脚本复制到干净 workspace |
| `consumers/node/` | Node 生命周期测试，离线候选安装后以包名消费 |
| `native_sanitizer/` | C 资源故障回放程序，语料在 `testdata/native_sanitizer/` |
| `../testdata/` | 静态 HTTP fixtures、证书、压缩文件、故障种子，保持字节稳定 |

从仓库根目录执行：

```text
moon check --target native --deny-warn
moon test --target native --deny-warn
moon test --target native server/preflight_test.mbt
moon test --target native tests/resources/preflight
moon test core --target wasm-gc --deny-warn
```

`moon test` 自动发现两个资源测试包；`consumers/moonbit` 是嵌套模块，不计入主模块单元测试。C/Rust/Python/Node 和 sanitizer 由 [scripts/check](../scripts/README.md) 的驱动执行，不能把主模块测试通过解释为这些消费者也已验证。

`server/http_test_helpers_test.mbt` 共享 Content-Length 客户端，供静态 HTTP、acceptor、transport 与代理用例调用。协议分片、chunked 和故障客户端保留专用读写行为，不能为减少代码行数而改变测试刺激。`c_suite_*` 保留原版兼容测试分组，历史文件路径对应关系见[迁移表](../docs/repository-layout-20260925.md#路径迁移)。

句柄计数和共享预算会受到同进程其他测试影响，需要独立包/进程时显式隔离；一般黑盒测试留在源码包即可。禁止通过扩大容差、跳过断言或重跑直至成功来代替缺陷修复。
