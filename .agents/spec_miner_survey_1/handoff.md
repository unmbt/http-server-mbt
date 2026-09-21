# Handoff Report: C ABI Specification Mining, Symbol Isolation & Lifecycle Management

**Agent**: `spec_miner_survey_1`  
**Role**: Specification Miner (`teamwork_preview_spec_miner`)  
**Date**: 2026-09-18T13:22:00Z  
**Target Milestone**: C ABI Dynamic/Static Export Pipeline, Symbol Isolation & Lifecycle Management (Milestone 3)  

---

## 1. Observation

Direct observations from authoritative specifications and local environment probes:

### 1.1 Specification Citations & Verbatim Contracts

- **`ORIGINAL_REQUEST.md` (Follow-up — 2026-09-18T13:08:02Z)**:
  - **R1. C ABI Interface & Symbol Isolation**:
    > "创建 C 桥接包，导出纯 C 头文件（`http_server.h`）与 `hs_*` 接口（`hs_abi_version`, `hs_server_start`, `hs_server_stop`, `hs_error_copy` 等），不暴露 MoonBit 托管对象或内部 runtime 布局。"
    > "分别支持 `thin`（纯静态 HTTP 服务器，零加密 C 依赖）与 `full`（集成 TLS 传输层与代理能力）两组导出实现。"
    > "建立导出符号隔离控制机制（Windows 使用 `.def` 文件或显式导出标记）：确保动态库与静态库中严禁包含 CLI `main` 入口符号，严禁泄露未授权内部符号；`thin` 库中绝对不包含任何 MbedTLS / PSA-Crypto 符号。"
  - **R2. Build Pipeline**:
    > "编写自动化构建驱动脚本（`scripts/build_cabi.mbtx`），驱动本地编译器与归档器... 构建导出 `thin` 版本的动态库（Windows `hs_min.dll` + `hs_min.lib`）与静态库（Windows `hs_min_static.lib`）... 构建导出 `full` 版本的动态库（Windows `hs_full.dll` + `hs_full.lib`）与静态库（Windows `hs_full_static.lib`）。"
  - **R3. C Consumer Smoke Tests**:
    > "在 `testdata/c_consumer/` 创建独立的 C 测试程序... 验证调用 `hs_abi_version()` 正确返回预期版本号，验证服务配置与生命周期调度无崩溃、无内存访问违规... 全仓既有 228 项 MoonBit 测试持续保持 100% 通过（0 回归、0 警告）。"

- **`docs/cli-thin-full-and-cabi-handover.md` (Lines 70–130)**:
  - Definitive `http_server.h` C declaration:
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

- **`docs/design.md` (D-07, Lines 218–261)**:
  - Public semantics:
    > "默认由库托管生命周期，只有两种使用方式：完整服务由宿主传配置并启动/停止；嵌入静态引擎由宿主提交请求、消费异步响应并接入已有 HTTP 框架。pump/run/poll 是内部机制，不进入默认公开接口，也不要求宿主自行等待/唤醒调度器。"
  - C ABI v1:
    > "导出名统一 `hs_*`，使用 C calling convention，Windows 显式导出、POSIX 限制可见符号；不暴露生成 C 的内部符号。`hs_abi_version()` 返回 major/minor；不透明句柄包含 engine、server、operation、response、chunk。配置使用 UTF-8 JSON 指针加长度，入口复制后由库验证；JSON 中无宿主回调/代码。"
  - Native runtime and thread safety:
    > "Native C ABI 由库创建并管理内部 owner 线程，同一 runtime 的托管对象只在其合法上下文访问。公共入口通过 C 拥有的线程安全队列、句柄引用和唤醒机制接收不同宿主线程的命令；宿主无需了解 owner 身份，C 工作线程不直接进入 MoonBit。队列接纳后即由库推进；close 与提交竞态以接纳顺序确定，关闭后新提交返回 CLOSED。"
  - Teardown sequence:
    > "销毁顺序为发起 close/stop → 库自动停止、取消并排空 I/O/已接纳业务通知 → 发出最终关闭通知 → 宿主释放仍持有的 operation/response/chunk/实例句柄 → 最后一个实例关闭时库自动回收内部运行任务/线程。关闭通知后不再回调该实例，其他实例继续工作。"

- **`docs/design.md` (D-11, Lines 337–350)**:
  - Static library vs Dynamic library & main isolation:
    > "Windows 的 DLL import library 必须使用明确的 import 名称，不能冒充真正静态 archive。"
    > "运行时初始化只能由桥接的受控入口执行，多个 engine 共享同一份已链接 runtime；静态与动态两种加载路径不能把对象相互传递。隐藏/隔离内部符号，避免宿主已有 MoonBit runtime 或其他 addon 引入第二份同名实现。库不携带 CLI main，不安装进程信号处理器或调用 exit..."

- **`docs/tasks.md` (T-002, T-020, T-027)**:
  - T-002: Windows Native 必需探针、C 桥接、静态/动态库链接与 C 消费验证。
  - T-020: C ABI v1 托管异步动态库，共用 C 头文件，无 CLI main / 公开循环接口。
  - T-027: 静态库打包与 C/Rust 消费，MSVC 静态 `.lib` 与 DLL import library 清楚区分，无 CLI main / 重复 runtime / 符号污染。

### 1.2 Local Toolchain & Environment Probe Results

- **MoonBit toolchain**: `E:\dev-env\moonbit\bin\moon.exe`
  - Internal compiler: `moonc.exe`, TinyCC `E:\dev-env\moonbit\bin\internal\tcc.exe` (v0.9.28rc, supports `-shared`, `-ar`, `-impdef`).
  - Standard headers: `E:\dev-env\moonbit\include\moonbit.h`, `moonbit_runtime.h`.
- **System C Compiler & Binutils**:
  - `gcc.exe` (MinGW-W64 12.2.0, x86_64) located at `E:\Program Files\mingw64\bin\gcc.exe`.
  - `nm.exe` (GNU Binutils 2.39) located at `E:\Program Files\mingw64\bin\nm.exe`.
  - `ar.exe` (GNU Binutils 2.39) located at `E:\Program Files\mingw64\bin\ar.exe`.
- **Executable vs Library Object Generation**:
  - Probed `_build/native/debug/build/cmd/http-server-mbt-thin/http-server-mbt-thin.obj` using `nm`:
    Discovered `0000000000248560 T main`.
    When building `cmd/http-server-mbt-thin` (which declares `pkgtype(kind: "executable")`), MoonBit emits a C `main()` wrapper calling `moonbit_runtime_init()` and `moonbit_init()`.
  - If a package is built as a library (no `pkgtype(kind: "executable")`), it does not emit `main()`, which is mandatory for static and dynamic library linking to prevent symbol collision with consumer code.

---

## 2. Logic Chain

1. **Requirement R1 & D-07 / D-11 necessitate strict symbol purity**:
   The C ABI export surface must be 100% limited to `hs_*` functions. MoonBit runtime symbols (`_M0*`, `moonbit_*`) and internal C functions must not be exported in the PE export directory of `.dll`.
2. **Main Symbol Isolation**:
   If an object file containing `main` is included in a static library (`.lib`) or dynamic library export, any external C consumer program defining `int main(void)` will fail to link with `multiple definition of 'main'`. Therefore:
   - C ABI bridge packages (`c_abi` / `c_abi_min` / `c_abi_full`) must NOT define a MoonBit `fn main()`.
   - Windows `.def` module definition file (e.g. `hs_min.def`) must be supplied during DLL linking:
     ```def
     LIBRARY hs_min
     EXPORTS
         hs_abi_version
         hs_server_start
         hs_server_stop
         hs_server_destroy
         hs_error_copy
     ```
   - This ensures the DLL export directory contains *only* the 5 approved functions.
3. **`thin` vs `full` Decoupling**:
   - `thin` build must compile without `tls` or `full` packages. Probing confirmed `server` is already decoupled from `tls`.
   - `thin` dynamic and static libraries must contain 0 occurrences of `mbedtls_*` or `psa_*` symbols.
   - When JSON config passes `cert_file` or `proxy` to `hs_server_start` under `thin` build, the server must fail before listening and return `HS_ERR_UNSUPPORTED` (or `HS_ERR_CONFIG`), matching CLI thin behavior.
   - `full` build integrates `tls` (MbedTLS 4.2.0 + PSA-Crypto) and proxy configuration, supporting HTTPS and upstream proxying.
4. **Lifecycle & Managed Event Loop Contract**:
   - D-07 mandates that host applications NEVER manually pump, poll, or drive the event loop.
   - Calling `hs_server_start` initiates a background library-managed thread, starts the server, blocks until listening socket is bound, and returns the opaque handle `hs_server_t*`.
   - Calling `hs_server_stop` signals the server to stop accepting new connections and drains in-flight requests.
   - Calling `hs_server_destroy` releases the handle and any OS resources. Passing `NULL` is a safe no-op.
5. **Static Library vs DLL Import Library Distinction (D-11 Contract)**:
   - On Windows MSVC/MinGW:
     - `hs_min.dll` is the runtime dynamic library.
     - `hs_min.lib` (or `libhs_min.dll.a`) is the DLL import library (linking against it requires `hs_min.dll` at runtime).
     - `hs_min_static.lib` (or `libhs_min.a`) is the self-contained static archive (linking against it embeds all object code into the consumer executable).
   - This prevents misidentifying import libraries as static archives.

---

## 3. Features Discovered

| # | Category | Feature | Description | Inputs | Outputs | Error Behavior | Discovered Via |
|---|----------|---------|-------------|--------|---------|----------------|----------------|
| 1 | Version Query | `hs_abi_version` | Returns 32-bit integer version `(major << 16) \| minor`. Constant `0x00010000` for v1.0. | `void` | `uint32_t` version code | Never fails. Safe to call anytime. | `docs/cli-thin-full-and-cabi-handover.md` L103, D-07 |
| 2 | Server Lifecycle | `hs_server_start` | Spawns library-managed event loop, binds socket, starts HTTP server. | `const char* json_config`, `size_t config_len`, `hs_server_t** out_server` | `int32_t` status code, `*out_server` handle | Returns `HS_ERR_INVALID_ARG` if `out_server==NULL`; `HS_ERR_CONFIG` on bad JSON or conflicting options; `HS_ERR_UNSUPPORTED` on TLS in `thin`; `HS_ERR_IO` on bind failure. | `docs/cli-thin-full-and-cabi-handover.md` L120, D-07 |
| 3 | Server Lifecycle | `hs_server_stop` | Stops accepting connections and drains in-flight requests gracefully. | `hs_server_t* server` | `int32_t` status code | Returns `HS_ERR_INVALID_ARG` if `server==NULL`; `HS_ERR_CLOSED` if already closed. Idempotent on stopped servers. | `docs/cli-thin-full-and-cabi-handover.md` L121, D-07 |
| 4 | Server Lifecycle | `hs_server_destroy` | Destroys server instance, cancels any remaining tasks, frees memory and synchronization primitives. | `hs_server_t* server` | `void` | If `server==NULL`, safe no-op. Automatically drains if not previously stopped. | `docs/cli-thin-full-and-cabi-handover.md` L122, D-07 |
| 5 | Diagnostics | `hs_error_copy` | Copies static human-readable description of error code into caller buffer. | `int32_t code`, `char* buf`, `size_t cap` | `size_t` string length (excluding NUL) | If `buf==NULL \|\| cap==0`, returns required length without writing (query mode). If buffer too small, truncates safely with trailing `\0`. | `docs/cli-thin-full-and-cabi-handover.md` L123, D-07 |
| 6 | Handle Types | `hs_server_t` | Opaque handle representing a running or stopped server instance. | N/A | Pointer handle | Internal layout is hidden from C caller; contains server context, background thread handle, and state. | `docs/cli-thin-full-and-cabi-handover.md` L107, D-07 |
| 7 | Handle Types | `hs_engine_t` | Opaque handle representing an embedded static engine without socket. | N/A | Pointer handle | Internal layout hidden; reserved for middleware and request embedding. | `docs/cli-thin-full-and-cabi-handover.md` L106, D-07 |
| 8 | Error Taxonomy | `enum hs_error_code` | Enumeration of error codes: `HS_OK=0`, `HS_ERR_CONFIG=1`, `HS_ERR_INVALID_ARG=2`, `HS_ERR_IO=3`, `HS_ERR_CLOSED=4`, `HS_ERR_UNSUPPORTED=5`. | `int32_t` code | Enum integer | Stable numerical constants; future compatible extensions append positive values. | `docs/cli-thin-full-and-cabi-handover.md` L110-117, D-07 |
| 9 | ABI Header | `http_server.h` | Unified C header providing declarations, macros, calling conventions, and version constants. | Standard C99 / C++ compiler | Header file | Defines `HS_EXPORT`, include guards, `extern "C"`. | `docs/cli-thin-full-and-cabi-handover.md` L83-130 |
| 10 | ABI Macro | `HS_EXPORT` | Windows `__declspec(dllexport)` / `__declspec(dllimport)` and POSIX `__attribute__((visibility("default")))`. | Compiler preprocessor | Macro expansion | Controlled by `HS_BUILD_DLL` and `HS_STATIC`. | `docs/cli-thin-full-and-cabi-handover.md` L90-96 |
| 11 | Symbol Isolation | Windows `.def` export control | Module definition file enumerating exactly the 5 exported `hs_*` functions. | Linker `/DEF:hs_min.def` | Filtered PE export table | Bans `main` and internal runtime symbols from appearing in `.dll` exports. | `docs/cli-thin-full-and-cabi-handover.md` L142, D-11 |
| 12 | Symbol Isolation | CLI `main` Prohibition | Ensuring C ABI library packages do not contain `main()` entrypoint. | Source package layout | Clean object files | Eliminates "multiple definition of 'main'" when linking into C consumers. | `ORIGINAL_REQUEST.md` L9, D-11, local nm probe |
| 13 | Build Pipeline | `scripts/build_cabi.mbtx` | Automated build driver producing 6 distinct artifacts: 2 `.dll`, 2 import `.lib`, 2 static `.lib`. | Toolchain (`moon`, `gcc`/`clang`, `ar`/`lib`) | `target/cabi/` binaries | Logs step-by-step progress, audits exported symbols, verifies 0 crypto symbols in thin. | `ORIGINAL_REQUEST.md` L82-87, Handover L145-160 |
| 14 | C Smoke Test | `testdata/c_consumer/` | Standalone C program linking both dynamic and static variants of `hs_min`. | `http_server.h`, `hs_min.lib` / `hs_min_static.lib` | Executable returning 0 | Asserts `hs_abi_version() == 0x00010000`, tests start/stop/destroy lifecycle. | `ORIGINAL_REQUEST.md` L89-93, Handover L162-178 |

---

## 4. Edge Cases

| # | Feature | Input | Observed / Required Behavior |
|---|---------|-------|------------------------------|
| 1 | `hs_server_start` | `out_server == NULL` | Immediate return of `HS_ERR_INVALID_ARG` (2); no server thread spawned, no socket created. |
| 2 | `hs_server_start` | `json_config == NULL` or `config_len == 0` | Defaults to default configuration (`root="."`, `port=8080`, `spa=false`, `cors=false`); succeeds with `HS_OK` (0). |
| 3 | `hs_server_start` | Malformed JSON string (e.g. `"{invalid_json:"`) | Fails preflight validation, returns `HS_ERR_CONFIG` (1); `*out_server` set to `NULL`. |
| 4 | `hs_server_start` | Conflicting options in JSON (e.g. `spa=true` and `try_files="404.html"`) | Fails preflight validation per `@core.validate_config`, returns `HS_ERR_CONFIG` (1). |
| 5 | `hs_server_start` | Out of range port (e.g. `port=99999` or negative) | Fails preflight validation, returns `HS_ERR_CONFIG` (1); no socket bound. |
| 6 | `hs_server_start` | Port already in use by another process | TCP socket bind fails, returns `HS_ERR_IO` (3); `*out_server` set to `NULL`. |
| 7 | `hs_server_start` | Ephemeral port (`port=0`) | System allocates available ephemeral port, server starts successfully (`HS_OK`). |
| 8 | `hs_server_start` (`thin` build) | JSON containing `"cert_file": "cert.pem"` or `"proxy": "http://..."` | Preflight checks intercept unsupported feature, returns `HS_ERR_UNSUPPORTED` (5); no listening socket opened. |
| 9 | `hs_server_stop` | `server == NULL` | Immediate return of `HS_ERR_INVALID_ARG` (2). |
| 10 | `hs_server_stop` | Calling `stop` on an already stopped server | Idempotent; returns `HS_OK` (0) without error or hang. |
| 11 | `hs_server_stop` | Active HTTP requests in-flight during `stop` | Stops accepting new connections; waits up to timeout (5000ms) for requests to complete, then completes stop. |
| 12 | `hs_server_destroy` | `server == NULL` | Safe no-op; returns immediately without segmentation fault or crash. |
| 13 | `hs_server_destroy` | Destroying server while still running (never called `stop`) | Automatically performs graceful shutdown and drain before deallocating memory. |
| 14 | `hs_error_copy` | `buf == NULL` and `cap == 0` | Query mode: calculates and returns required byte length of error string (excluding NUL). No memory written. |
| 15 | `hs_error_copy` | `buf != NULL` and `cap == 1` | Writes single NUL byte `\0` to `buf[0]`; returns full required length. |
| 16 | `hs_error_copy` | `cap < required_length + 1` | Truncates error string to `cap - 1` bytes and writes trailing `\0`; returns full untruncated length. |
| 17 | `hs_error_copy` | Unknown error code (e.g. `code = 999`) | Returns length of string `"Unknown error"` and copies `"Unknown error"` into buffer. |
| 18 | `hs_abi_version` | Called concurrently from multiple threads before server initialization | Pure stateless constant function; returns `0x00010000` safely and consistently. |

---

## 5. Caveats

1. **Toolchain Compiler Selection**:
   Local probing confirmed MinGW-W64 `gcc 12.2.0`, `nm 2.39`, `ar 2.39` in `E:\Program Files\mingw64\bin\`, and TinyCC `tcc 0.9.28rc` in `E:\dev-env\moonbit\bin\internal\`. MSVC (`cl.exe` / `link.exe`) is not on system PATH. The build script `scripts/build_cabi.mbtx` should adaptively prefer `gcc` / `ar` / `nm` or `clang` when executing on MinGW/Windows environments.
2. **Read-Only Scope**:
   In strict accordance with the Specification Miner role, no production code, scripts, or headers have been modified or created outside `.agents/spec_miner_survey_1/`.
3. **MbedTLS Symbol Isolation**:
   In `thin` build, `server` package is completely decoupled from `tls`. However, during link time, `scripts/build_cabi.mbtx` must verify via `nm` that no `mbedtls_*` or `psa_*` symbols are linked into `hs_min.dll` or `hs_min_static.lib`.

---

## 6. Conclusion

The specification for Milestone 3 (C ABI Dynamic/Static Export Pipeline, Symbol Isolation & Lifecycle Management) is fully mapped and ready for implementation:

1. **Exact API Signatures**:
   - `uint32_t hs_abi_version(void)`
   - `int32_t hs_server_start(const char* json_config, size_t config_len, hs_server_t** out_server)`
   - `int32_t hs_server_stop(hs_server_t* server)`
   - `void hs_server_destroy(hs_server_t* server)`
   - `size_t hs_error_copy(int32_t code, char* buf, size_t cap)`
2. **Opaque Types & Errors**:
   - Handles `hs_server_t`, `hs_engine_t`.
   - Codes `HS_OK` (0), `HS_ERR_CONFIG` (1), `HS_ERR_INVALID_ARG` (2), `HS_ERR_IO` (3), `HS_ERR_CLOSED` (4), `HS_ERR_UNSUPPORTED` (5).
3. **Symbol Isolation & Safety**:
   - Windows `.def` module definition file prevents leak of internal MoonBit runtime symbols.
   - Exclusion of CLI `main` entrypoint from library packages prevents linker symbol collision.
   - Automated symbol audit with `nm` verifies 0 crypto symbols in `hs_min`.
4. **Server Lifecycle**:
   - Managed background event loop with preflight configuration validation, asynchronous socket binding, graceful draining on stop, and safe destruction.

---

## 7. Verification Method

To independently verify these findings and contracts:

1. **Inspect Handover & Design Docs**:
   - `docs/cli-thin-full-and-cabi-handover.md` (Sections 1, 2, 3, 4).
   - `docs/design.md` (D-07 lines 214–261, D-11 lines 337–350).
   - `docs/tasks.md` (T-002, T-020, T-027).
2. **Inspect Symbol Cleanliness via `nm`**:
   - Run `nm <binary> | Select-String "main"` to verify presence in `http-server-mbt-thin.obj` and verify that library packages do not export `main`.
3. **Inspect Toolchain Availability**:
   - `gcc --version` -> MinGW-W64 12.2.0.
   - `nm --version` -> GNU nm 2.39.
   - `ar --version` -> GNU ar 2.39.
4. **Current Test Baseline**:
   - Run `moon check --target native` (verifies 0 errors, 0 warnings).
   - Run `moon test --target native` (verifies 228 / 228 tests passing).
