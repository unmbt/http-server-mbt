# http-server-mbt C ABI 动静态库多语言集成指南

`http-server-mbt` 基于 MoonBit 语言构建，底层依托高性能事件循环与零拷贝内核通道（Windows `TransmitFile`、Linux `sendfile`、macOS Darwin `sendfile`）。依据架构规范 **D-07**（托管异步 C ABI）与 **D-11**（静态库打包与消费），项目通过标准 C ABI（`c_abi/include/http_server.h`）对外导出原生动态库与静态库，可直接嵌入 **C/C++、Rust、Python、Go、Node.js、C#** 等任意主流编程语言的宿主应用中。

---

## 1. 产物规范与双版本体系

项目提供 **`min`** 与 **`full`** 两种功能档位：

| 构建版本 | 特性与依赖特征 | 典型适用场景 |
|---|---|---|
| **`min`** | 纯静态 HTTP 文件服务；**零加密依赖、0 MbedTLS C 桩代码**；动态库 ~1.3 MB，静态库 ~4.4 MB | 内嵌静态资源服务、本地开发调试、资源受限的容器环境 |
| **`full`** | 完整 HTTPS（TLS 1.2/1.3，内嵌 MbedTLS 4.2.0）与反向代理（Proxy / Proxy-All） | 生产级 HTTPS 文件站、前端 SPA 网关、API 静态混合代理 |

### 各平台产物清单

| 平台 | 动态库 | 导入库 (Import Lib) | 静态库 (Static Archive) | C 头文件 |
|---|---|---|---|---|
| **Windows (x86_64)** | `hs_min.dll`<br>`hs_full.dll` | `hs_min.lib`<br>`hs_full.lib` | `hs_min_static.lib`<br>`hs_full_static.lib` | `include/http_server.h` |
| **Linux (x86_64)** | `libhs_min.so`<br>`libhs_full.so` | *(不需要)* | `libhs_min.a`<br>`libhs_full.a` | `include/http_server.h` |
| **macOS (arm64)** | `libhs_min.dylib`<br>`libhs_full.dylib` | *(不需要)* | `libhs_min.a`<br>`libhs_full.a` | `include/http_server.h` |

> [!NOTE]
> **符号隔离与安全性保障**：
> 动态库严格通过符号隔离机制（Windows `.def` 白名单过滤、Linux GNU ELF `version-script`、macOS `exported_symbols_list`），**只导出 5 个公共 `hs_*` API**，绝对不泄露 MoonBit 内部运行时函数，杜绝任何 `main` 符号冲突。

---

## 2. C ABI 接口与生命周期契约

头文件位于 `c_abi/include/http_server.h`，定义了简洁清晰的纯 C 接口：

```c
#ifndef HTTP_SERVER_H
#define HTTP_SERVER_H

#include <stdint.h>
#include <stddef.h>

#if defined(_WIN32)
  #if defined(HS_BUILD_DLL)
    #define HS_EXPORT __declspec(dllexport)
  #elif defined(HS_STATIC)
    #define HS_EXPORT
  #else
    #define HS_EXPORT __declspec(dllimport)
  #endif
#else
  #define HS_EXPORT __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

/* 1. ABI 版本检查: 返回 0x00010000 (v1.0) */
HS_EXPORT uint32_t hs_abi_version(void);

/* 不透明服务器句柄 */
typedef struct hs_server hs_server_t;

/* 错误码枚举 */
enum hs_error_code {
    HS_OK = 0,               /* 成功 */
    HS_ERR_CONFIG = 1,       /* 配置解析失败或参数冲突 */
    HS_ERR_INVALID_ARG = 2,  /* 传入空指针或非法长度 */
    HS_ERR_IO = 3,           /* 套接字绑定或网络 I/O 异常 */
    HS_ERR_CLOSED = 4,       /* 服务已停止关闭 */
    HS_ERR_UNSUPPORTED = 5   /* min 版本使用了 TLS 等不支持特性 */
};

/* 2. 启动服务 (声明式 JSON 配置) */
HS_EXPORT int32_t hs_server_start(const char* json_config, size_t config_len, hs_server_t** out_server);

/* 3. 停止服务 (幂等操作，排空在途连接) */
HS_EXPORT int32_t hs_server_stop(hs_server_t* server);

/* 4. 销毁实例句柄 (释放上下文与关联内存) */
HS_EXPORT void hs_server_destroy(hs_server_t* server);

/* 5. 获取错误诊断详情 (拷贝到调用者提供的 buffer) */
HS_EXPORT size_t hs_error_copy(int32_t code, char* buf, size_t cap);

#ifdef __cplusplus
}
#endif

#endif /* HTTP_SERVER_H */
```

### JSON 配置字段参考

`hs_server_start` 接受 UTF-8 编码的 JSON 字符串配置：

```json
{
  "port": 8080,
  "root": "./public",
  "silent": false,
  "cors": true,
  "spa": true,
  "cache_seconds": 3600,
  "cert_file": "server.crt",
  "key_file": "server.key",
  "key_passphrase": "secret",
  "proxy": "http://127.0.0.1:3000"
}
```

- `port`: 监听端口（`0` 表示系统自动分配空闲端口）。
- `root`: 静态资源根目录。
- `silent`: 是否静默运行（抑制控制台日志）。
- `cors`: 开启 CORS 头支持。
- `spa`: 开启单页应用回退（404 时自动返回 `index.html`）。
- `cert_file` / `key_file`: HTTPS 证书与私钥路径（仅 `full` 版本支持）。
- `proxy`: 反向代理上游服务地址（仅 `full` 版本支持）。

---

## 3. 各语言调用实战

### 3.1 C / C++

#### 动态链接使用示例

```c
// main.c
#include <stdio.h>
#include <string.h>
#include <assert.h>
#include "http_server.h"

int main(void) {
    printf("http-server-mbt ABI Version: 0x%08X\n", hs_abi_version());

    const char* config = "{\"port\": 8080, \"root\": \".\", \"silent\": false}";
    hs_server_t* server = NULL;

    int32_t rc = hs_server_start(config, strlen(config), &server);
    if (rc != HS_OK) {
        char err[128];
        hs_error_copy(rc, err, sizeof(err));
        fprintf(stderr, "Failed to start server: %s (code: %d)\n", err, rc);
        return 1;
    }

    printf("Server started successfully on port 8080. Press ENTER to stop...\n");
    getchar();

    hs_server_stop(server);
    hs_server_destroy(server);
    printf("Server stopped and destroyed cleanly.\n");
    return 0;
}
```

**编译与链接命令**：
- **Linux (GCC / Clang)**:
  ```bash
  clang main.c -Iinclude -Llib -lhs_min -Wl,-rpath,'$ORIGIN/lib' -o server_demo
  ./server_demo
  ```
- **macOS (Clang)**:
  ```bash
  clang main.c -Iinclude -Llib -lhs_min -Wl,-rpath,'@executable_path/lib' -o server_demo
  ./server_demo
  ```
- **Windows (MSVC)**:
  ```cmd
  cl.exe /Iinclude main.c /link /LIBPATH:lib hs_min.lib /OUT:server_demo.exe
  server_demo.exe
  ```

#### 静态链接说明

静态链接时，必须在引入头文件前定义 `#define HS_STATIC`，并链接底层操作系统依赖库：

- **Linux**:
  ```bash
  clang -DHS_STATIC main.c -Iinclude lib/libhs_min.a -lpthread -lm -ldl -o server_demo_static
  ```
- **macOS**:
  ```bash
  clang -DHS_STATIC main.c -Iinclude lib/libhs_min.a -lpthread -lm -o server_demo_static
  ```
- **Windows (MSVC)**:
  ```cmd
  cl.exe /DHS_STATIC /Iinclude main.c /link /LIBPATH:lib hs_min_static.lib kernel32.lib libcmt.lib crypt32.lib secur32.lib iphlpapi.lib ws2_32.lib mswsock.lib userenv.lib advapi32.lib synchronization.lib dbghelp.lib bcrypt.lib shell32.lib /NODEFAULTLIB:msvcrt.lib /OUT:server_demo_static.exe
  ```

---

### 3.2 Rust

在 Rust 中，可以使用 FFI 安全封装 `hs_*` 接口，并借助 RAII（`Drop` trait）确保服务资源在生命周期结束时自动安全排空与回收。

#### `build.rs` 配置

```rust
// build.rs
fn main() {
    println!("cargo:rustc-link-search=native=lib");
    
    // 动态链接 min 库:
    println!("cargo:rustc-link-lib=hs_min");
    
    // 若使用静态链接，则改为:
    // println!("cargo:rustc-link-lib=static=hs_min_static");
    // #[cfg(target_os = "linux")] {
    //     println!("cargo:rustc-link-lib=pthread");
    //     println!("cargo:rustc-link-lib=m");
    //     println!("cargo:rustc-link-lib=dl");
    // }
}
```

#### `src/main.rs` 完整代码

```rust
use std::ffi::{c_char, c_void, CStr, CString};
use std::io::{self, BufRead};

#[repr(C)]
struct HsServer {
    _private: [u8; 0],
}

extern "C" {
    fn hs_abi_version() -> u32;
    fn hs_server_start(json_config: *const c_char, config_len: usize, out_server: *mut *mut HsServer) -> i32;
    fn hs_server_stop(server: *mut HsServer) -> i32;
    fn hs_server_destroy(server: *mut HsServer);
    fn hs_error_copy(code: i32, buf: *mut c_char, cap: usize) -> usize;
}

pub struct HttpServer {
    handle: *mut HsServer,
}

impl HttpServer {
    pub fn start(json_config: &str) -> Result<Self, String> {
        let c_config = CString::new(json_config).map_err(|e| e.to_string())?;
        let mut handle: *mut HsServer = std::ptr::null_mut();

        let rc = unsafe {
            hs_server_start(c_config.as_ptr(), json_config.len(), &mut handle)
        };

        if rc != 0 || handle.is_null() {
            let mut err_buf = [0u8; 128];
            let len = unsafe {
                hs_error_copy(rc, err_buf.as_mut_ptr() as *mut c_char, err_buf.len())
            };
            let err_msg = String::from_utf8_lossy(&err_buf[..len]);
            return Err(format!("Server start error ({}): {}", rc, err_msg));
        }

        Ok(HttpServer { handle })
    }

    pub fn stop(&self) {
        if !self.handle.is_null() {
            unsafe { hs_server_stop(self.handle) };
        }
    }
}

impl Drop for HttpServer {
    fn drop(&mut self) {
        if !self.handle.is_null() {
            unsafe {
                hs_server_stop(self.handle);
                hs_server_destroy(self.handle);
            }
            self.handle = std::ptr::null_mut();
        }
    }
}

fn main() {
    let ver = unsafe { hs_abi_version() };
    println!("Initialized http-server-mbt ABI: 0x{:08X}", ver);

    let config = r#"{"port": 8080, "root": ".", "silent": false}"#;
    let server = HttpServer::start(config).expect("Failed to run HTTP server");

    println!("HTTP Server is listening on http://127.0.0.1:8080");
    println!("Press ENTER to terminate...");
    let _ = io::stdin().lock().read_line(&mut String::new());

    drop(server); // 触发 Drop 自动停止并销毁句柄
    println!("Server cleanly shutdown.");
}
```

---

### 3.3 Python

借助 Python 标准库的 `ctypes`，**无需安装任何额外三方库（0 pip 依赖）**，即可直接调用动态库：

```python
# server.py
import sys
import os
import json
import ctypes
from ctypes import c_char_p, c_size_t, c_int32, c_uint32, c_void_p, POINTER

def load_hs_library():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    lib_dir = os.path.join(script_dir, "lib")

    if sys.platform.startswith("win"):
        dll_name = "hs_min.dll"
    elif sys.platform == "darwin":
        dll_name = "libhs_min.dylib"
    else:
        dll_name = "libhs_min.so"

    dll_path = os.path.join(lib_dir, dll_name)
    if not os.path.exists(dll_path):
        # 尝试当前目录
        dll_path = dll_name

    return ctypes.CDLL(dll_path)

lib = load_hs_library()

# 设置函数原型
lib.hs_abi_version.restype = c_uint32
lib.hs_abi_version.argtypes = []

lib.hs_server_start.restype = c_int32
lib.hs_server_start.argtypes = [c_char_p, c_size_t, POINTER(c_void_p)]

lib.hs_server_stop.restype = c_int32
lib.hs_server_stop.argtypes = [c_void_p]

lib.hs_server_destroy.restype = None
lib.hs_server_destroy.argtypes = [c_void_p]

lib.hs_error_copy.restype = c_size_t
lib.hs_error_copy.argtypes = [c_int32, c_char_p, c_size_t]

class HttpServer:
    def __init__(self, config: dict):
        self.config_bytes = json.dumps(config).encode('utf-8')
        self.server_ptr = c_void_p(None)

    def __enter__(self):
        self.start()
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        self.close()

    def start(self):
        rc = lib.hs_server_start(self.config_bytes, len(self.config_bytes), ctypes.byref(self.server_ptr))
        if rc != 0 or not self.server_ptr:
            err_buf = ctypes.create_string_buffer(128)
            lib.hs_error_copy(rc, err_buf, 128)
            raise RuntimeError(f"Server start failed ({rc}): {err_buf.value.decode('utf-8')}")

    def close(self):
        if self.server_ptr:
            lib.hs_server_stop(self.server_ptr)
            lib.hs_server_destroy(self.server_ptr)
            self.server_ptr = None

if __name__ == "__main__":
    print(f"ABI Version: 0x{lib.hs_abi_version():08X}")
    cfg = {"port": 8080, "root": ".", "silent": False}

    with HttpServer(cfg) as server:
        print("Server running on http://127.0.0.1:8080. Press Enter to exit...")
        input()
    print("Server cleanly closed.")
```

---

### 3.4 Go

Go 语言通过 `cgo` 可以极为简单地链接动态库：

```go
// main.go
package main

/*
#cgo CFLAGS: -I${SRCDIR}/include
#cgo LDFLAGS: -L${SRCDIR}/lib -lhs_min
#include "http_server.h"
#include <stdlib.h>
*/
import "C"
import (
	"fmt"
	"unsafe"
)

type HttpServer struct {
	server *C.hs_server_t
}

func StartServer(jsonConfig string) (*HttpServer, error) {
	cConfig := C.CString(jsonConfig)
	defer C.free(unsafe.Pointer(cConfig))

	var server *C.hs_server_t
	rc := C.hs_server_start(cConfig, C.size_t(len(jsonConfig)), &server)
	if rc != C.HS_OK {
		buf := make([]byte, 128)
		C.hs_error_copy(rc, (*C.char)(unsafe.Pointer(&buf[0])), C.size_t(len(buf)))
		return nil, fmt.Errorf("failed to start server (code %d): %s", int(rc), string(buf))
	}
	return &HttpServer{server: server}, nil
}

func (s *HttpServer) Close() {
	if s.server != nil {
		C.hs_server_stop(s.server)
		C.hs_server_destroy(s.server)
		s.server = nil
	}
}

func main() {
	ver := uint32(C.hs_abi_version())
	fmt.Printf("http-server-mbt ABI Version: 0x%08X\n", ver)

	config := `{"port": 8080, "root": ".", "silent": false}`
	server, err := StartServer(config)
	if err != nil {
		panic(err)
	}
	defer server.Close()

	fmt.Println("Server listening on http://127.0.0.1:8080. Press Ctrl+C or Enter to exit.")
	fmt.Scanln()
}
```

---

### 3.5 Node.js / Bun

在 Node.js 中，推荐使用极简高效的 `koffi` 模块调用动态库；若使用 Bun，可直接使用内置的原生 `bun:ffi`。

#### Node.js (`koffi`)

```bash
npm install koffi
```

```javascript
// index.js
const koffi = require('koffi');
const path = require('path');

const libExt = process.platform === 'win32' ? '.dll' : process.platform === 'darwin' ? '.dylib' : '.so';
const libPrefix = process.platform === 'win32' ? '' : 'lib';
const libPath = path.resolve(__dirname, 'lib', `${libPrefix}hs_min${libExt}`);

const lib = koffi.load(libPath);

const hs_server_t = koffi.opaque();
const hs_abi_version = lib.func('uint32_t hs_abi_version()');
const hs_server_start = lib.func('int32_t hs_server_start(const char* json_config, size_t config_len, _Out_ hs_server_t** out_server)');
const hs_server_stop = lib.func('int32_t hs_server_stop(hs_server_t* server)');
const hs_server_destroy = lib.func('void hs_server_destroy(hs_server_t* server)');
const hs_error_copy = lib.func('size_t hs_error_copy(int32_t code, _Out_ uint8_t* buf, size_t cap)');

console.log(`ABI Version: 0x${hs_abi_version().toString(16).padStart(8, '0')}`);

const config = JSON.stringify({ port: 8080, root: '.', silent: false });
const outServer = [null];

const rc = hs_server_start(config, Buffer.byteLength(config), outServer);
if (rc !== 0) {
  const errBuf = Buffer.alloc(128);
  hs_error_copy(rc, errBuf, 128);
  console.error(`Failed to start server: ${errBuf.toString()}`);
  process.exit(1);
}

const serverHandle = outServer[0];
console.log('Server running on http://127.0.0.1:8080. Press Ctrl+C to exit.');

process.on('SIGINT', () => {
  console.log('\nStopping server...');
  hs_server_stop(serverHandle);
  hs_server_destroy(serverHandle);
  console.log('Server destroyed cleanly.');
  process.exit(0);
});
```

---

## 4. 静态链接系统依赖对照表

当以静态库（`.a` 或 `.lib`）形式直接嵌入最终可执行二进制文件时，由于静态归档包含 MoonBit 异步网络与文件事件循环，需在链接器中补充如下系统库：

| 平台 | 必需系统依赖库 | 链接器示例选项 |
|---|---|---|
| **Linux (glibc / musl)** | `libpthread`, `libm`, `libdl` | `-lpthread -lm -ldl` |
| **macOS (Darwin)** | `libpthread`, `libm` | `-lpthread -lm` |
| **Windows (MSVC)** | `kernel32.lib`, `libcmt.lib`, `ws2_32.lib`, `crypt32.lib`, `secur32.lib`, `iphlpapi.lib`, `mswsock.lib`, `userenv.lib`, `advapi32.lib`, `synchronization.lib`, `dbghelp.lib`, `bcrypt.lib`, `shell32.lib` | `/NODEFAULTLIB:msvcrt.lib`（与 MT CRT 保持一致） |

---

## 5. 故障排查与最佳实践

1. **动态库路径加载失败（`cannot open shared object file` / `DLL not found`）**：
   - **Linux**: 编译调用程序时加上 `-Wl,-rpath,'$ORIGIN/lib'`，或运行时设置 `export LD_LIBRARY_PATH=./lib:$LD_LIBRARY_PATH`。
   - **macOS**: 加上 `-Wl,-rpath,'@executable_path/lib'`，或设置 `DYLD_LIBRARY_PATH`。
   - **Windows**: 确保 `hs_min.dll` 放置在与可执行文件同目录下，或加入系统 `PATH`。
2. **`hs_server_start` 返回 `HS_ERR_UNSUPPORTED`（错误码 5）**：
   - 在 `min` 版本库中配置了 `cert_file`（TLS 证书）或 `proxy`（代理转发）。请切换到 `full` 版本动态库/静态库（`hs_full`）。
3. **优雅停机与内存回收**：
   - 必须先调用 `hs_server_stop(server)` 让正在传输的请求完成并排空套接字，随后调用 `hs_server_destroy(server)` 释放实例。对同一个有效实例，`hs_server_stop` 可安全幂等重复调用。
