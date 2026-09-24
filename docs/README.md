# 开发文档

产品安装与用法见 [README](../README.md) / [中文说明](../README.zh.md)。开发从本页、[脚本入口](../scripts/README.md)和[测试说明](../tests/README.md)开始。

## 当前规范与实现

| 文档 | 用途 |
|---|---|
| [proposal](proposal.md) | 需求及兼容基线；开头的项目现状是建立规范时的历史背景 |
| [design](design.md) | 当前行为、接口、平台与资源契约，按日期修订和稳定 D 编号查阅 |
| [tasks](tasks.md) | T 编号状态、依赖、原版 42 文件及 C/CC/CE 迁移矩阵 |
| [C ABI 使用](cabi-usage-guide.md) | 已有 C 静态/动态库消费方式 |
| [下一次次版本迁移](migration-0.4.md) | 资源所有权与 MoonBit API 迁移说明 |
| [容器来源](container-provenance.md) | Docker 基础镜像与产物说明 |
| [架构审计](architecture-review.md) | Thin/Full 依赖边界与待完成项 |
| [ADR-01](adr/01-choose-mbedtls-4.2-for-tls-engine.md)、[ADR-02](adr/02-mbedtls-vendor-config-header-overrides.md) | TLS 后端选择与 vendor 配置理由 |
| [仓库整理记录](repository-layout-20260925.md) | 新旧路径、脚本退出清单、测试与接口验证 |

## 代码布局

根包是静态文件引擎；`core/` 是可移植协议与配置；`internal/native/` 是平台桥；`internal/framing/` 是 HTTP framing。`server/plain/` 承载 Thin，`server/` 与 `full/` 承载 Full 的服务/代理功能；`tls/` 包含 MbedTLS 适配及固定 vendor 源。`cmd/common/` 共享 CLI，两个 `cmd/http-server-*` 包提供命令行入口。`c_abi/` 和 `npm/` 分别提供 C 与 Node 分发接口。

包内 `*_test.mbt` / `*_wbtest.mbt` 跟随所属源码；需要单独进程的测试和外部消费程序位于 `tests/`。静态 fixtures 和故障种子位于 `testdata/`。`build.mbtx` 是模块预构建钩子，其他维护脚本按用途置于 `scripts/`。`_build/`、`target/` 和 `.mooncakes/` 是忽略的本地产物/缓存。

历史完成记录、旧里程碑指令和测试规划位于 [archive](archive/README.md)。它们保留证据及上下文；当前任务状态以 tasks 为准，不能将历史通过数当作当前提交验收。
