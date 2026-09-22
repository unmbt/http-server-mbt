# Thin / Full 架构审计与优化

日期：2026-09-23。关联 R-N17、D-20、T-035；HTTPS upstream 复用 T-013 / N-12，WebSocket 复用 T-014。本文记录本次源码及 Windows Native release 实测，不能替代三平台发行验收。

## 六项发现与处理方案

| 编号 | 问题与证据 | 影响 | 优化与验收 |
|---|---|---|---|
| A-01 | Thin 虽不导入本项目 tls，却经 server → async/http、websocket → async/tls 带入 Schannel；基线 PE 导入 Secur32.dll、CRYPT32.dll | 参数禁用没有形成完整编译依赖边界 | Thin 使用独立明文入口；共享 HTTP framing、静态引擎及内核传输；审计生成 C 与 PE/ELF/Mach-O 依赖，禁止 MbedTLS/PSA/async TLS 混入 |
| A-02 | proxy_http_request 解析 https URL 后仍直接 Tcp::connect_to_host | HTTPS upstream 没有真正执行 TLS | 注入 UpstreamConnector；HTTPS 执行 MbedTLS 握手、SNI、CA 与主机名校验；错误返回 502，监听前预检配置；N-12 真实 TCP 回归 |
| A-03 | 入站 MbedTLS、HTTP upstream 明文和 WebSocket 系统 TLS 三条路径不一致；当前 `async/websocket` 的 `wss` 仍由依赖包管理 | 多套 TLS 依赖及不同证书/错误策略，妨碍 Linux 静态分发 | 本轮统一入站与 HTTP/HTTPS upstream 的连接器；WebSocket TLS 仍列为 T-014/T-035 未完成项，统一前不宣称共享 MbedTLS |
| A-04 | TLS vendor 构建清单包含 109 个 C 文件，含调试、PKCS#7、证书/CSR 写入等服务器不使用的模块 | 增加构建及产物成本；源文件数不等于链接后的体积 | 由 `vendor_tls.mbtx` 关闭并排除 9 个不使用模块，保留证书解析/校验、加密私钥及 TLS 1.2/1.3；不任意删密码套件；裁剪后重跑 TLS 与 upstream 预检测试 |
| A-05 | Full/Thin 重复 CLI parser、banner、颜色、IP 枚举、版本生成与 main | 修复容易只落到一个档位，源码难维护 | 已新增无 Full/TLS 依赖的 `cmd/common` 并抽取 `first_value`、整数、端口、缓存和 Basic Auth 原语；两个入口保留本地包装以兼容现有白盒测试。banner、颜色、IP 枚举、完整命令规格和 main 仍待后续迁移与依赖审计 |
| A-06 | README 固定旧测试数与“零加密 C 依赖”，旧文档将本机分项标成整体完成；缺少持续产物审计 | 对交付范围和缩减效果的描述无法复核 | 已更新当前 Windows 证据和限制；后续用 `.mbtx` 审计接入 CLI CI，测试数以实际执行为准 |

## 基线与判断

修改前 Windows release：Full **4,106,752 bytes（3.92 MiB）**，Thin **2,806,784 bytes（2.68 MiB）**。Thin 减少 **31.65%**，说明裁去 MbedTLS 已生效，但还没有实现完整的 TLS 依赖隔离。原始测试基线 235/235 通过。

D-15 不设置 CLI / 镜像硬性体积目标。本次衡量相同工具链、平台与 release 配置下的实际大小及依赖变化；不压缩 exe 掩盖依赖，不将 archive 大小等同于最终可执行体积。Windows 系统 DLL（包括 runtime 的 bcrypt.dll 随机数依赖）不等于内置 TLS 功能。

## 验证记录

本次 Windows x86_64 / Moon 0.1.20260904 验证：`moon check --target native` 通过（存在历史告警），`moon test --target native` **240/240** 通过；Full release `3,884,544` bytes，SHA-256 `79721784E4D9D012B04A908CB4C168353E89802A8F78081CE8495ACB0C3BD1D7`；Thin release `1,602,560` bytes，SHA-256 `F21871E7432B5E0F678305663BBF89FCD790E1B8C3029A20E4654BABA0E7F9D0`。Thin PE 字符串审计未发现 `Secur32.dll`、`CRYPT32.dll`、`mbedtls_`、`psa_`、`async_tls` 或 `schannel`，仍发现通用 runtime 的 `bcrypt.dll` 字符串；Full PE 保留 `mbedtls_`/`schannel` 能力。文档不宣称“零系统加密库”。

相对本次修改前基线（Full `4,106,752`、Thin `2,806,784` bytes），当前 Thin 缩小约 **42.90%**，Full 缩小约 **5.41%**；本轮裁剪前 Full 为 `4,129,280` bytes，裁剪后再减少约 **5.93%**。Thin 相对 Full 减少 **58.75%**，已达到“按功能减少产物”的架构预期，但体积变化只作趋势证据，不构成 D-15 的硬性门槛。三平台 Actions、C ABI、ASan/UBSan、真实 HTTPS upstream E2E 和 WebSocket `wss` 统一仍待 T-035/T-032/T-012 分项完成。
