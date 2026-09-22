# ADR-02: vendored MbedTLS 配置头文件的受控改写（#undef 覆盖与 ASCII 清洗）

## 状态

**已通过 (Accepted)** — 实现于提交 `b0c1011`（T-012 Windows 分项），设计依据 [design D-08](../design.md)。

## 上下文 (Context)

按 [ADR-01](./01-choose-mbedtls-4.2-for-tls-engine.md)，TLS 引擎采用源码 vendor 的 Mbed TLS 4.2.0（含 TF-PSA-Crypto 1.2.0），引入方式为 `scripts/vendor_tls.mbtx` 可复现脚本：固定下载 URL 与 SHA-256（`2bed9d713b4668f76553b097e72b8aa30bc8f112a940d7ae228d524bbde6ffea`），提取 10 个源码子树的 `*.c`/`*.h` 及 LICENSE 到 `tls/mbedtls-4.2.0/`。

2026-09-14 的核查结论：从官方 release URL 重新下载 tarball（SHA-256 与 pin 一致）并逐文件比对，vendored 树 282 个文件中 **280 个与官方 tarball 字节级完全一致**，唯二例外是两个配置头：

* `include/mbedtls/mbedtls_config.h`
* `tf-psa-crypto/include/psa/crypto_config.h`

这两个头的特殊性在于：`mbedtls_config.h` 被**每一个** C 编译单元包含（经 `build_info.h`），`psa/crypto_config.h` 被 PSA 侧全部编译单元包含——对它们的任何修改都会放大到整个构建。本 ADR 记录这两处偏离官方 tarball 的内容、动机、备选方案与安全边界；除此之外的 vendored 文件禁止任何手改。

---

## 决策 (Decision)

两处头文件的改写全部由 `scripts/vendor_tls.mbtx` 自动施加（幂等，两次运行产物逐字节一致），共两类变换：

### 1. 文件末尾追加托管 `#undef` 覆盖块

向两个配置头**末尾**追加同一段 12 行的托管块（见脚本常量 `MBEDTLS_CONFIG_OVERRIDES`），不改动官方任何原有行。8 条 `#undef` 及其动机：

| #undef | 动机 |
|---|---|
| `MBEDTLS_NET_C` | socket 系统调用不进 C 层（D-08 边界）：TLS 经 `mbedtls_ssl_set_bio` 自定义 BIO 桥接回 MoonBit 事件循环；`net_sockets.c` 同时被排除出编译清单，且此后任何代码误 include `net_sockets.h` 会直接 `#error`，误用尽早失败 |
| `MBEDTLS_TIMING_C` | 无 DTLS，计时反 DoS 用不上；时间由事件循环统一管理 |
| `MBEDTLS_FS_IO` | 文件 I/O 全部留在 MoonBit（`@fs`），C 侧证书/私钥只走内存 buffer 解析；同时绕开 Windows 下 C 层 `fopen` 的非 ASCII 路径/宽字符问题 |
| `MBEDTLS_PSA_ITS_FILE_C` | 裁掉 PSA 内部可信存储的文件后端 |
| `MBEDTLS_PSA_CRYPTO_STORAGE_C` | 裁掉持久化密钥存储（会把密钥写盘的整条代码路径移除），桌面静态服务无此需求 |
| `MBEDTLS_MEMORY_BUFFER_ALLOC_C` | 不使用 mbedtls 自带分配器 |
| `MBEDTLS_ENTROPY_NV_SEED` | 去掉“启动时必须提供 NV 种子”的运行时前置条件 |
| `MBEDTLS_PLATFORM_NV_SEED_ALT` | 与上一条配套，移除对应平台替代实现钩子 |

需要明确的两点：

* **这是主动的架构裁剪，不是编译必需**——保持默认配置也能编译通过。裁剪的价值在于兑现 D-08 的边界承诺（C 层零 socket/文件/持久化系统调用）、不给产物带入死代码、消除运行时前置条件。
* `MBEDTLS_HAVE_TIME_DATE` **有意保留**：证书过期检查（N-12）依赖它。
* 同一段 `#undef` 块追加到 `crypto_config.h` 时，其中 `MBEDTLS_*` 宏在该文件本就未定义，`#undef` 为无害空操作；脚本对两个头施加统一变换是为保持实现简单，并为 D-08 中 “`crypto_config.h` 最小化裁剪由测试守护逐步收紧” 预留同一机制。

### 2. 非 ASCII 字符清洗为空格

对两个配置头把所有非 ASCII 字符替换为单个空格。事实核查（4.2.0 tarball）：

* `mbedtls_config.h` 仅有 **1 处**非 ASCII：第 996 行注释中的 `±`（U+00B1，会话票据时钟精度描述）；
* `psa/crypto_config.h` 当前为 **0 处**——将其纳入清洗是预防性约定（上游后续版本可能在注释中引入非 ASCII）。

机制：这两个头无 BOM，Windows 上的 MSVC/clang-cl 会按系统 ANSI 代码页（中文环境为 cp936/GBK）解读无 BOM 源文件。UTF-8 的 `±` 编码为 `0xC2 0xB1`，GBK 解码时 `0xB1` 会被当作双字节字符的尾字节与前一字节错位配对：

* 轻则触发 C4819 警告，且在**每个包含该头的编译单元**各报一次（`mbedtls_config.h` 被全部 TU 包含，即数百条噪音警告）；
* 重则 GBK 双字节吞掉注释终止符 `*/` 或换行，把注释后的真实代码“吃”进注释，造成真实语法/语义破坏（cp936 环境下 UTF-8 注释的经典问题）。

清洗只作用于注释字符，**语义零变化**。

---

## 备选方案评估 (Considered Options)

### 选项 1：完全不改两个头，按默认配置编译

* **劣势**：违背 D-08 已确认的边界承诺（C 层不引入 socket/文件/持久化系统调用）；产物携带死代码；引入 NV seed 等运行时前置条件。不采纳。

### 选项 2：`MBEDTLS_CONFIG_FILE` 指向自定义配置头（官方推荐定制方式）

* 变体 A（自定义头 `#include` 官方头再 `#undef`）：官方 `mbedtls_config.h` 仍被每个编译单元包含，`±` 注释照样触发 C4819，**ASCII 清洗仍然必需**，等于白增一层间接。
* 变体 B（自定义头完整复制官方默认配置，约 38KB）：官方头不再参与编译，清洗确实可省，但偏离面从“末尾 12 行追加”扩大为一份 38KB 派生文件，每次上游升级都需全量重新比对，可审计性显著变差。
* **结论**：均不采纳。变体 B 可在未来 `crypto_config.h` 裁剪幅度很大时再评估。

### 选项 3：以 `/utf-8` 编译选项替代 ASCII 清洗

* **劣势**：`/utf-8` 仅对 MSVC/clang-cl 有效，gcc/clang 不认识该 flag，需按平台/编译器条件化 cc-flags；且把源码编码假设从文件属性转移到构建配置，任何绕过 moon 构建直接用 C 编译器编译 vendored 源码的场景都会踩回同一问题。不采纳（可作为未来重构选项）。

### 选项 4：为两个头添加 UTF-8 BOM

* **劣势**：同样是修改文件字节，且 BOM 在部分非 MSVC 工具链/预处理场景下行为不一致，问题只是换了一种形态。不采纳。

### 选项 5（选用）：默认配置 + 末尾追加托管 `#undef` 块 + 注释 ASCII 清洗

* **优势**：偏离面最小且形态固定（12 行尾部追加 + 注释内字符替换）；全部收敛在 vendor 脚本内，可复现、幂等；对三平台 × MSVC/clang-cl/gcc/clang 全部无歧义。

---

## 影响与推论 (Consequences)

### 正向影响 (Positive Consequences)

* **可复现**：`moon run scripts/vendor_tls.mbtx`（可传入本地 tarball）一键重建，输出逐字节稳定。
* **审计友好**：vendored 树与上游的差异面被永久限制在这两个头，且差异形态声明式固定；对官方源码做安全 diff 时一眼可尽。
* **边界保证**：所有 C 编译单元不引用 socket/文件/持久化系统调用，产物不含对应死代码。

### 负向影响与妥协 (Negative Consequences & Mitigations)

* **vendored 树不再与上游逐字节全同**：
  * *对策*：比对上游必须经过脚本变换重建（或重跑脚本后比对）；本文“决策”一节即完整声明了变换规则，可独立复现。
* **升级 MbedTLS 版本时需重新审查**：
  * *对策*：升级流程就是重跑 `vendor_tls.mbtx` + 审查托管块中每条 `#undef` 是否仍然适用 + 重新执行逐文件一致性核查。
* **`crypto_config.h` 当前清洗为空操作**：
  * *对策*：保留为预防性约定，随上游版本演进自动生效，无需额外维护。

---

## 验证证据 (2026-09-14)

* 从 `https://github.com/Mbed-TLS/mbedtls/releases/download/mbedtls-4.2.0/mbedtls-4.2.0.tar.bz2` 重新下载，SHA-256 为 `2bed9d713b4668f76553b097e72b8aa30bc8f112a940d7ae228d524bbde6ffea`，与脚本 pin 及 D-08 记录一致。
* 逐文件字节比对：vendored 282 个文件中 280 个与 tarball 完全一致；两个配置头的差异与本文声明的变换（ASCII 清洗 + 追加托管块）逐字节重建吻合。
* 完备性：tarball 10 个拷贝子树内 280 个 `*.c`/`*.h` 文件在 vendored 树中无缺失、无多余。初始清单（109 项）与 “vendored `*.c` − `library/net_sockets.c` + `tls_bridge.c`” 完全一致；2026-09-23 起由 T-035 的裁剪规则额外排除未使用调试、PKCS#7、CSR/证书生成和 SSL cache/cookie 源，当前生成清单为 100 项，来源与排除项均由 `scripts/vendor_tls.mbtx` 再生。

## 相关

* [ADR-01: 选择 Mbed TLS 4.2 作为底层 TLS 引擎](./01-choose-mbedtls-4.2-for-tls-engine.md)
* [design D-08 构建、TLS 与分发](../design.md)
* [scripts/vendor_tls.mbtx](../../scripts/vendor_tls.mbtx)
