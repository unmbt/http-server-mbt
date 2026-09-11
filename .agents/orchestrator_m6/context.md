# Context: Milestone 6 原版全量测试套件迁移与对抗加固

## 1. 任务背景与目标
前序 Milestone 1 至 5 已全量通过，当前编译器基线为 `moon check --target native` 0 错误 0 警告，现有 116 个测试全部通过。
Milestone 6 目标：
1. 原版全量测试套件迁移 (C001～C042, CC-01～CC-28, CE-01～CE-02):
   - 对照 `docs/tasks.md` 逐例迁移矩阵，将 `http-server/test/` 核心测试逻辑移植到 MoonBit Native 测试集；
   - 覆盖条件缓存（304/ETag/IMS）、字节区间 Range（206/416）、预压缩协商（.br/.gz 候选探测）、MIME 类型识别与覆盖、目录索引与列表 HTML 渲染转义、安全策略（路径穿越防御、Basic Auth）、以及命令行配置映射；
   - 兼容 Windows 平台特性与限制（如 AD-05 Windows 特殊路径约束处理）。
2. 真实 HTTP 客户端端到端集成测试:
   - 通过真实 TCP Socket 客户端对运行中的服务发起请求与解析响应；
   - 验证 GET、HEAD、OPTIONS、keep-alive 及错误状态码交互，确保协议解析与响应调度端到端正确。
3. 状态机故障注入与异常并发对抗 (T-034):
   - 引入可重现的状态机故障注入场景：包含网络短写（Short Write）、慢速客户端读取（分段延时）、请求中途异常断连与在途取消；
   - 验证高并发请求及连接异常终止下服务器不挂起、不崩溃，且无 Socket/文件句柄泄漏（0 handle leaks）。
4. 严格执行 Git 提交与多重门禁审计流程。

## 2. 关键规范与文件参考
- `AGENTS.md`: MoonBit 项目与 Native/FFI 规则、自动化要求
- `docs/proposal.md`: R-N01 ~ R-N16 需求跟踪
- `docs/design.md`: D-01 ~ D-18 架构与设计契约（特别是 D-17 文件变更检测、D-18 状态机故障注入与模糊测试）
- `docs/tasks.md`: C001~C042 逐例测试迁移矩阵、T-034 等任务定义
- `docs/windows-baseline.md`: Windows 平台原生基线与证据记录
- `docs/progress.md`: 阶段进度与已完成测试清单
- `ORIGINAL_REQUEST.md`: 初始用户需求记录
