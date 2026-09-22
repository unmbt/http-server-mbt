# CLI thin/full 双版本打包完成记录与动静态库导出接续指南

> **记录时间**：2026-09-18
> **当前状态**：已完成 Milestone 1（核心包解耦）与 Milestone 2（Thin/Full 双版本 CLI 打包及全量测试保护）；在此节点主动暂停（PAUSE），以便后续无缝接续动静态库导出（Milestone 3）。

---

## 一、已完成工作内容与架构成果

### 1. 核心架构解耦（Milestone 1）
- **剥离 `server` 对 `tls` 的硬依赖**：
  - 修改 `server/moon.pkg`，完全移除 `"unmbt/http-server-mbt/tls"` 依赖，使得基础静态服务器不再引入 100 余个 MbedTLS C 源文件（bignum, aes, sha, x509, ssl_tls 等）。
  - 在 `server/server.mbt` 中定义了连接传输抽象 `Transport` 与生命周期接收接口 `Acceptor` trait，并提供了默认的明文处理实现 `PlainAcceptor`。
  - 通过 `raw_fd: @types.Fd?` 暴露底层操作系统 Socket 文件描述符，在明文连接上 100% 保留 Windows `TransmitFile`、Linux `sendfile` 内核级零拷贝通道。
- **构建 `full/` 依赖注入包**：
  - 新增 `full/` 包，导入 `server` 与 `tls`，实现 `TlsServerAcceptor`。
  - 提供 `full.with_server_at` 与 `full.with_server` 入口函数，在配置启用 TLS 时注入 `TlsServerAcceptor`，未启用时回退明文。
  - 在 `build_tls_acceptor` 前置校验 `@core.validate_tls(config)`，确保证书与密钥缺失在监听前精准报错。

### 2. 双版本 CLI 打包体系（Milestone 2）
- **精简版 CLI (`cmd/http-server-mbt-thin`)**：
  - **包路径**：`cmd/http-server-mbt-thin/`
  - **依赖特征**：仅依赖 `server`、`core` 与基础 I/O，**完全不依赖 `full` 或 `tls`**，编译产物 0 MbedTLS C 桩代码。
  - **产物体积对比**（Windows Native release）：
    - `http-server-mbt-thin.exe`：**1,602,560 bytes (当前 Windows release)**
    - `http-server-mbt.exe` (含 MbedTLS)：**3,884,544 bytes (当前 Windows release)**（Thin 相对 Full 减少约 58.75%）。
  - **严格参数拦截**（符合 D-08 / D-15 规范）：
    - 传入 `--cert`、`--key` 或 `--key-passphrase`：报错 `error: TLS is not supported in thin build; use full build`，退出码 1。
    - 传入 `-P`、`--proxy`、`--proxy-all` 或 `--proxy-config`：报错 `error: Proxy is not supported in thin build; use full build`，退出码 1。
- **完整版 CLI (`cmd/http-server-full`)**：
  - **包路径**：`cmd/http-server-full/`
  - **依赖特征**：依赖 `full`、`core`，支持完整 TLS 与 Proxy 参数。
  - **功能支持**：完整支持 HTTPS 监听（TLS 1.2/1.3 协商、加密密钥密码短语）及上游代理转发参数配置。
- **向后兼容默认 CLI (`cmd/http-server-mbt`)**：
  - 保持原有 CLI 入口完整可用，现有测试、自动化脚本与 Docker 构建无破坏。

### 3. 全量测试与质量门禁验证
- **测试通过率**：全仓 **240 / 240 测试 100% 全部通过（0 失败、0 回归、0 句柄泄漏）**。
  - `cmd/http-server-mbt-thin`：7/7 项参数解析与非法参数拦截测试通过。
  - `cmd/http-server-full`：5/5 项 TLS 与代理参数映射测试通过。
  - `server/`：95/95 项单元、集成、零拷贝与故障注入测试通过。
  - `full/`：13/13 项真实 TLS 回环、预检拦截与句柄压力测试通过。
  - 原版 42 组迁移套件（C001～C042）持续 100% PASS。
- **静态检查与代码风格**：
  - `moon check --target native`：**0 错误；该历史记录未统计当前告警**。
  - `moon info --target native`：生成规范 `.mbti` 接口描述。
  - `moon fmt`：全仓格式化对齐。

---

## 二、反向代理（Proxy）架构接口当前就绪状态

1. **核心配置模型（`core/config.mbt`）**：
   - 字段已完备：
     ```moonbit
     proxy : String?              // 上游代理 URL（例如 "http://127.0.0.1:3000"）
     proxy_all : String?          // 全量代理（直通，绕过本地静态文件探测）
     proxy_options : Map[String, String] // 上游代理选项（如 secure: "false"）
     websocket : Bool             // WebSocket 代理升级开关
     ```
   - 互斥规则已由 `@core.validate_config` 守护：`--spa` / `--try-files` 与代理配置互斥，`proxy_all` 必须配合 `proxy` 使用，非法 scheme 自动拦截。
2. **状态机与调度槽位**：
   - 规范设计流转：`Resolving`（本地静态探测）→ `Proxying`（命中代理兜底或 proxy-all 直通）→ `Idle` / `Closing`。
   - `server/server.mbt` 中 `dispatch_engine_request` 在返回 `Next` 时已预留代理转发 Hook 点。

---

## 三、动静态库导出（Milestone 3）接续实施指南

### 1. 目标产物定义
依据设计规范 D-07（托管异步 C ABI）与 D-11（静态库打包与消费），需构建两组库产物：
1. **`thin` 动静态库**：
   - 动态库：Windows `hs_thin.dll`（配套 import library `hs_thin.lib`）/ Linux `libhs_thin.so` / macOS `libhs_thin.dylib`
   - 静态库：Windows `hs_thin_static.lib` / Linux `libhs_thin.a` / macOS `libhs_thin.a`
   - **核心约束**：完全不包含任何 MbedTLS / TF-PSA-Crypto 符号与对象，极致轻量。
2. **`full` 动静态库**：
   - 动态库：Windows `hs_full.dll`（配套 `hs_full.lib`）/ Linux `libhs_full.so` / macOS `libhs_full.dylib`
   - 静态库：Windows `hs_full_static.lib` / Linux `libhs_full.a` / macOS `libhs_full.a`
   - 包含 TLS 引擎（MbedTLS）与后续 Proxy 上游客户端网络栈。

### 2. C ABI 头文件与统一命名空间（`hs_*`）
在 `c_abi/include/http_server.h` 中导出纯 C 接口：
```c
#ifndef HTTP_SERVER_H
#define HTTP_SERVER_H

#include <stdint.h>
#include <stddef.h>

#if defined(_WIN32) && defined(HS_BUILD_DLL)
  #define HS_EXPORT __declspec(dllexport)
#elif defined(_WIN32)
  #define HS_EXPORT __declspec(dllimport)
#else
  #define HS_EXPORT __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

// ABI 版本号 (例如 0x00010000 表示 v1.0)
HS_EXPORT uint32_t hs_abi_version(void);

// 不透明句柄
typedef struct hs_engine hs_engine_t;
typedef struct hs_server hs_server_t;

// 错误码定义
enum hs_error_code {
    HS_OK = 0,
    HS_ERR_CONFIG = 1,
    HS_ERR_INVALID_ARG = 2,
    HS_ERR_IO = 3,
    HS_ERR_CLOSED = 4,
    HS_ERR_UNSUPPORTED = 5
};

// 引擎与服务器托管接口 (声明式 JSON 配置)
HS_EXPORT int32_t hs_server_start(const char* json_config, size_t config_len, hs_server_t** out_server);
HS_EXPORT int32_t hs_server_stop(hs_server_t* server);
HS_EXPORT void hs_server_destroy(hs_server_t* server);
HS_EXPORT size_t hs_error_copy(int32_t code, char* buf, size_t cap);

#ifdef __cplusplus
}
#endif

#endif // HTTP_SERVER_H
```

### 3. MoonBit C 桥接包设计（`c_abi` 包）
在项目中建立 `c_abi/` 包（或拆分为 `c_abi_min` 与 `c_abi_full`）：
- **`c_abi/abi.mbt`**：
  ```moonbit
  #cfg(any(target="native", target="llvm"))
  pub fn hs_abi_version() -> UInt = "hs_abi_version"
  ```
- **`c_abi/bridge.c`**：
  实现 C ABI 与 MoonBit 内部 `server` / `full` 的参数转换与调度，使用全局线程安全互斥锁与引用计数。
- **符号隔离控制**：
  - Windows：使用模块定义文件 `.def`（例如 `hs_thin.def`），显式列出需要导出的 `hs_*` 函数列表，杜绝导出 MoonBit 内部运行时符号或 `main`。
  - POSIX：使用 `-Wl,--version-script` 或 `-fvisibility=hidden`。

### 4. 自动化构建驱动脚本（`scripts/build_cabi.mbtx`）
编写 MoonBit 驱动脚本 `scripts/build_cabi.mbtx`，执行以下流程：
1. **编译阶段**：
   - 分别调用 `moon build c_abi_min --target native` 与 `moon build c_abi_full --target native`，在 `_build/native/` 下生成各子包的 `.obj` 对象文件。
2. **动静态库链接与归档**：
   - **动态库生成**：
     - Windows MSVC 环境：调用 `link.exe /DLL /DEF:hs_thin.def ... /OUT:target/hs_thin.dll /IMPLIB:target/hs_thin.lib`
     - Clang 环境：调用 `clang -shared -o target/hs_thin.dll -Wl,--out-implib,target/hs_thin.lib ...`
   - **静态库归档**：
     - Windows MSVC：调用 `lib.exe /OUT:target/hs_thin_static.lib ...`
     - POSIX / MinGW：调用 `llvm-ar rcs target/libhs_thin.a ...`
3. **符号纯洁性校验（Symbol Audit）**：
   - 检查 `hs_thin` 动态/静态库中：
     - 包含且仅包含以 `hs_` 开头的导出符号；
     - 绝对不包含 `mbedtls_*`、`psa_*` 符号；
     - 绝对不包含可执行文件的 `main` 入口符号。

### 5. 最小 C 调用验证用例（Smoke Test）
在 `testdata/c_consumer/` 创建测试程序：
- `test_min_cabi.c`：
  ```c
  #include "http_server.h"
  #include <assert.h>
  #include <stdio.h>

  int main(void) {
      uint32_t ver = hs_abi_version();
      printf("hs_abi_version: 0x%08X\n", ver);
      assert(ver > 0);
      return 0;
  }
  ```
- 分别链接动态库与静态库运行测试，验证加载、符号解析与返回值的正确性。

---

## 四、后续工作接续检查清单

当准备启动动静态库导出时，可直接按以下步骤执行：
1. [ ] 创建 `c_abi/` 目录与 `moon.pkg`，定义 `hs_*` 接口的 MoonBit 声明与 C 桩函数桥接。
2. [ ] 编写 `scripts/build_cabi.mbtx` 脚本，自动化打包 Windows `.dll` / `.lib` 与静态 `.lib`。
3. [ ] 验证 `thin` 产物无 MbedTLS 符号污染，验证 `full` 产物包含完整 TLS 导出能力。
4. [ ] 编写 `testdata/c_consumer/` 最小 C 验证程序，并在 Windows 本机编译运行验证。
5. [ ] 更新 `docs/design.md` D-11 与 `docs/tasks.md` T-020/T-027 交付证据。
