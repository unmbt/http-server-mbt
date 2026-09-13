# ADR-02: 选择 Mbed TLS 4.2 作为底层 TLS 引擎

## 状态

**已通过 (Accepted)**

## 上下文 (Context)

`http-server-mbt` 是一个基于 MoonBit 开发的高性能、跨平台静态文件服务器。为了满足现代化生产级服务与跨语言嵌入的需求，本项目确立了以下核心架构指标：

1. **多平台支持**：原生支持 Linux (x86_64/AArch64)、macOS (Apple Silicon/Intel) 及 Windows (MSVC/MinGW)。
2. **多形态导出**：除 CLI 可执行文件外，必须能导出为标准 C-ABI 动态库（`.so`, `.dylib`, `.dll`）与静态库（`.a`, `.lib`），供 C/C++、Rust、Go、Python 等外部语言零障碍调用。
3. **极简全静态容器化**：能够在 `gcr.io/distroless/static`（无 glibc、无 shell、无动态链接器）极简容器镜像中平稳运行，要求产物必须能通过 `musl-libc` 进行 100% 纯静态链接。
4. **代码维护性与体积约束**：二进制需尽可能轻量（目标总包体控制在数兆内），FFI 交互逻辑需保持简洁，避免复杂的生命周期管理。

在 MoonBit 原生网络栈之上构建 HTTPS/TLS 能力时，我们需要在现有的底层加密与 TLS 实现中做出关键选型。

---

## 决策动因 (Decision Drivers)

* **纯 C/便携性**：易于通过 MoonBit Native C-FFI 绑定，无冗杂的次级工具链依赖。
* **跨平台编译复杂度**：在 Windows MSVC 与 Linux musl 环境下能够一键构建，不依赖复杂的环境配置。
* **API 易用性与样板代码量**：服务端初始化握手、证书加载、随机数生成等流程的代码侵入度。
* **纯静态链接与打包友好度**：在 musl 下编译为静态库归档（Archive）以及导出动态库时的符号干净度。
* **长期技术演进**：避免引入生命周期末期、含有历史债务或即将废弃的旧版 API。

---

## 备选方案评估 (Considered Options)

### 选项 1：OpenSSL 3.x

* **优势**：业界事实标准，硬件加速生态成熟，算法覆盖最全。
* **劣势**：
  * 体积庞大（静态链接产物通常增加 3MB~5MB 以上）。
  * 交叉编译与构建系统陈旧，强依赖 Perl、NASM，在 Windows 与 musl 下的静态编译链路极其脆弱。
  * 对 `musl-libc` 的全静态链接容易出现 NSS/DNS 解析相关符号的隐式依赖，不适于 Distroless Static。

### 选项 2：Rustls (通过 rustls-ffi)

* **优势**：内存安全，现代化 TLS 1.2/1.3 协议栈，性能优异。
* **劣势**：
  * 构建依赖 Rust 工具链（`cargo`, `cargo-c`），在 MoonBit + C 构建矩阵中引入了第三套重型工具链，加重 CI/CD 构建负担。
  * C-FFI 抽象层相对年轻，在 Windows MSVC 及部分特殊静态链接场景下的配置复杂度高于纯 C 方案。

### 选项 3：Mbed TLS 3.6 LTS (旧单体版本)

* **优势**：纯 C99 实现，跨平台极简，长期支持。
* **劣势**：
  * **API 繁琐**：配置 TLS 服务端时，必须手动维护 `mbedtls_entropy_context` 和 `mbedtls_ctr_drbg_context`，并显式注入随机数生成器回调（`mbedtls_ssl_conf_rng`），样板代码达数十行。
  * **历史包袱严重**：充斥大量弱安全算法（如不具备前向安全性的静态 RSA 握手套件），且底层 Legacy 加密 API 与 PSA API 双轨并行，已进入维护周期的末端。

### 选项 4：Mbed TLS 4.2 (选用方案)

* **优势**：
  * **架构解耦**：底层彻底拆分为 **TF-PSA-Crypto**，Mbed TLS 仅保留 X.509 证书体系和 (D)TLS 协议状态机，职责高度清晰。
  * **彻底消除 RNG 样板代码**：全面内生化 PSA 随机数体系，移除了 `mbedtls_ssl_conf_rng()` 等繁琐接口，服务端初始化仅需单次调用 `psa_crypto_init()`。
  * **原生安全防御**：全面剔除旧时代的不安全套件（如无前向保密的纯 RSA 密钥交换），默认配置即符合高安全基线。
  * **单一构建规范**：彻底废弃散乱的 Make/Visual Studio 工程，统一使用现代 CMake 构建体系，与 MoonBit 的顶层 CMake 编排天然契合。
  * **全静态链接与 Distroless 完美兼容**：依赖干净，只链接系统标准库，在 Alpine musl 下编译为 `lib*.a` 的过程极度平滑。

---

## 架构决策 (Decision Outcome)

我们决定**选择 Mbed TLS 4.2 作为 `http-server-mbt` 的核心底层 TLS 引擎**。

### 关键落地设计

1. **源码集成模式**：
   * 将 Mbed TLS 4.2 作为 Git Submodule 引入（需使用 `--recursive` 同步附带的 `tf-psa-crypto` 模块）。
   * 项目顶层 CMake 直接将其作为子目录包含，全局开启 `-DCMAKE_POSITION_INDEPENDENT_CODE=ON` 以同时支撑静态库与共享库的链接需求。
2. **抽象隔离层 (`native/tls_adapter.c`)**：
   * 基于 4.2 极简 API 构建 C 适配器，对外仅暴露 `TlsContext` 与 `TlsSession` 两个不透明句柄。
   * 全局生命周期仅在首次加载时触发 `psa_crypto_init()`，完全规避 3.x 时代的 Entropy/DRBG 手工调度逻辑。
3. **统一 Stream Trait**：
   * 在 MoonBit 语言侧，通过统一的 `Stream` 抽象抹平 Plain TCP 与 TLS 连接，使上层 HTTP/1.1 解析器、静态路由、Range/ETag 处理逻辑与安全传输层彻底解耦。

---

## 影响与推论 (Consequences)

### 正向影响 (Positive Consequences)

* **代码复杂度降低 ~40%**：移除了大量的上下文初始化、熵池挂载与随机数参数传递，C 适配层总代码量缩减至百行级别。
* **零运行时依赖（Distroless 友好）**：通过 Alpine 镜像中的 `musl-gcc` 与 `cmake` 可生成 100% 独立的静态二进制，产物体积仅增加几百 KB，完美运行于 `gcr.io/distroless/static-debian12`。
* **C-ABI 库导出干净**：静态导出（`.a`/`.lib`）通过 CMake 自动化打包归并，动态导出（`.so`/`.dylib`/`.dll`）不暴露冗余的密码学符号。
* **面向未来的技术栈**：全面拥抱 Arm PSA Cryptography 标准，未来若需硬件级安全存储或安全芯片加速，无需重构 TLS 业务逻辑。

### 负向影响与妥协 (Negative Consequences & Mitigations)

* **依赖拉取需递归 Submodule**：
  * *问题*：Mbed TLS 4.x 依赖独立的 `tf-psa-crypto`，若用户 `git clone` 漏加 `--recursive` 会导致编译失败。
  * *对策*：在顶层 `CMakeLists.txt` 中增加子模块完整性校验，未拉取时给出清晰的错误拦截指引或通过 `FetchContent` 自动补全。
* **删除了遗留密码学套件**：
  * *问题*：4.2 不再支持老旧客户端（如非常古老的不支持 ECDHE 的爬虫或客户端）。
  * *对策*：作为现代化 HTTP 静态服务器，强制要求现代 TLS 1.2+ 和前向安全性（PFS）是符合当前互联网安全演进规范的合理权衡。
* **社区网络教程存在滞后性**：
  * *问题*：网络上大量针对 Mbed TLS 的教程仍停留在 2.x/3.x 的旧 API。
  * *对策*：在本项目内部将 `tls_adapter.c` 视作自闭环模块，保持完整自解释的注释，隔离对外扩散的技术认知成本。
