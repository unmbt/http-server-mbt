# Milestone 6 执行计划：原版全量测试套件迁移、真实 HTTP 客户端 E2E 与状态机故障注入对抗加固

## 一、目标与验收标准
1. **原版全量测试套件迁移 (C001～C042, CC-01～CC-28, CE-01～CE-02)**:
   - 对照 `docs/tasks.md` 逐例迁移矩阵，将原版 `http-server/test/` 核心测试逻辑移植到 MoonBit Native 测试集；
   - 覆盖条件缓存（304/ETag/IMS）、字节区间 Range（206/416）、预压缩协商（.br/.gz 候选探测）、MIME 类型识别与覆盖、目录索引与列表 HTML 渲染转义、安全策略（路径穿越防御、Basic Auth）、以及命令行配置映射；
   - 兼容 Windows 平台特性与限制（如 AD-05 Windows 特殊路径约束处理）。
2. **真实 HTTP 客户端端到端集成测试**:
   - 通过真实 TCP Socket 客户端对运行中的服务发起请求与解析响应；
   - 验证 GET、HEAD、OPTIONS、keep-alive 及错误状态码交互，确保协议解析与响应调度端到端正确。
3. **状态机故障注入与异常并发对抗 (T-034)**:
   - 引入可重现的状态机故障注入场景：包含网络短写（Short Write）、慢速客户端读取（分段延时）、请求中途异常断连与在途取消；
   - 验证高并发请求及连接异常终止下服务器不挂起、不崩溃，且无 Socket/文件句柄泄漏（0 handle leaks）。
4. **Git 与门禁合规**:
   - 代码完成后执行 `git add -A` 并提交本地 commit（例如 `feat: 实现 Milestone 6 原版测试迁移与故障注入测试`），严禁 push；
   - 经 Reviewers、Challengers、Forensic Auditor 独立严格门禁；
   - 更新 `.mbti`、运行 `moon fmt`、同步更新 `docs/tasks.md` 与 `docs/progress.md`，完成最终本地 commit（严禁 push），编写 `handoff.md` 汇报。
5. **质量门禁**:
   - `moon check --target native` 持续 0 错误、0 警告；
   - `moon test --target native` 100% 全部通过。

---

## 二、阶段分解与调度计划

### Phase 1: Survey & Architecture Analysis (探索与调研)
- **Explorer 1 (`explorer_m6_1`)**:
  - 调研 `docs/tasks.md` 逐例迁移矩阵（C001~C042、CC-01~CC-28、CE-01~CE-02）及 `http-server/test/` 原版用例实现；
  - 评估现有 MoonBit 测试覆盖度与待补充用例清单。
- **Explorer 2 (`explorer_m6_2`)**:
  - 调研真实 TCP Socket 客户端 E2E 测试方案；
  - 分析在 MoonBit Native / Async 环境下如何构造非阻塞/异步真实 TCP 客户端，覆盖 GET、HEAD、OPTIONS、keep-alive 及各类状态码。
- **Explorer 3 (`explorer_m6_3`)**:
  - 调研 D-18 / T-034 状态机故障注入与异常并发对抗方案；
  - 针对网络短写、慢速分段读取、中途异常断连、在途取消设计可重现的注入机制与 Windows `GetProcessHandleCount` 0 泄漏检测。

### Phase 2: Worker Implementation (代码实现与本地测试)
- **Worker (`worker_m6`)**:
  - 根据 Explorer 调研方案，落地原版全量测试集迁移；
  - 落地真实 TCP Socket 客户端 E2E 测试；
  - 落地状态机故障注入与并发对抗测试；
  - 运行 `moon check --target native` 确保 0 警告 0 错误；
  - 运行 `moon test --target native` 确保所有新老测试 100% 通过且 0 句柄泄漏。

### Phase 3: Intermediate Git Commit Gate (本地提交与暂停门禁)
- Worker 执行 `git add -A` 并提交：`feat: 实现 Milestone 6 原版测试迁移与故障注入测试`，严禁 push。
- **【核心暂停点】**：commit 成功后立即暂停推进，向 Sentinel 及用户汇报完成状态、commit 哈希与变更详情。严禁自动派发 Reviewer、Challenger 及 Auditor，等待用户明确指令！

### Phase 4: Multi-Agent Review & Challenge Gate (待用户批准后启动)
- **Reviewer 1 (`reviewer_m6_1`)**: 全量迁移用例覆盖度、行为契约与 Windows AD-05 约束审查。
- **Reviewer 2 (`reviewer_m6_2`)**: E2E 真实客户端与状态机故障注入架构、Socket/文件句柄生命周期审查。
- **Challenger 1 (`challenger_m6_1`)**: 对抗性检验真实 TCP 客户端边界、畸形请求、协议异常。
- **Challenger 2 (`challenger_m6_2`)**: 对抗性压力测试故障注入、突发断连、并发竞争与句柄泄漏。

### Phase 5: Forensic Integrity Audit Gate (法务与完整性审计)
- **Auditor (`auditor_m6_1`)**: 独立审计所有新增测试真实性，杜绝硬编码断言、伪造故障注入，核验 0 句柄泄漏证据及开源协议合规性。

### Phase 6: Final Documentation & Local Commit Closure (收尾与交付)
- Worker 执行 `moon info --target native`，`moon fmt`，同步更新 `docs/tasks.md` 与 `docs/progress.md`；
- 执行最终本地 commit（严禁 push）；
- Orchestrator 编写 `handoff.md`，向 parent/sentinel 汇报交付。
