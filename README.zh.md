<div align="center">

[English](./README.md) | [简体中文](./README.zh.md)

# 🚀 http-server-mbt

*一款使用 [MoonBit](https://moonbitlang.com) 编写的极速、零依赖、高性能静态 HTTP 服务器。*

[![MoonBit](https://img.shields.io/badge/Language-MoonBit-f86800?logo=moonbit&logoColor=white)](https://moonbitlang.com)
[![mooncakes.io](https://img.shields.io/badge/mooncakes.io-unmbt%2Fhttp--server--mbt-f86800)](https://mooncakes.io/docs/unmbt/http-server-mbt)
[![Build Status](https://img.shields.io/badge/Tests-240%2F240%20Pass-brightgreen)](#)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Platform](https://img.shields.io/badge/Platform-Windows%20%7C%20Linux%20%7C%20macOS%20(Verified)-brightgreen)](#-平台支持矩阵)
[![Native Speed](https://img.shields.io/badge/Backend-Native_C_FFI-8a2be2)](#)

</div>

## 🖥️ 平台支持矩阵 (Platform Support)

| 平台 | 架构 | 状态 | 核心传输机制 | 质量门禁与测试 |
| :--- | :--- | :---: | :--- | :--- |
| **Windows** | x86_64 | **✅ 本机 Native 已验证** | Win32 `TransmitFile` + IOCP Overlapped 异步内核级零拷贝 | 当前本机 240/240 通过；Full/Thin 依赖和体积审计见 `docs/architecture-review.md` |
| **Linux** | x86_64 | **🔶 等待 Actions 证据** | `sendfile(2)` + `epoll` | 平台发布、TLS 和容器证据由 T-032/T-035 跟踪 |
| **macOS** | arm64 / x86_64 | **🔶 等待 Actions 证据** | Darwin `sendfile` + `kqueue` | 平台发布、TLS 和容器证据由 T-032/T-035 跟踪 |

> 📌 **跨平台说明**：当前可复核证据是 Windows 本机 Native。Linux/macOS 仍需 Actions 矩阵和发行门禁；Windows 结果不计作三平台整体完成。

---

## 🔥 相比原版 Node.js http-server 的重大拓展与重构

本项目基于 MoonBit 对经典 Node.js 版 `http-party/http-server`（基准提交 `0d3b7bb5`）进行了底层架构级的重构与现代化拓展：

| 维度 | 原版 Node.js http-server | 本项目 http-server-mbt | 拓展与提升价值 |
| :--- | :--- | :--- | :--- |
| **底层 I/O 传输** | 依赖 Node.js/V8 流管道与 libuv，用户态 Buffer 内存拷贝，受垃圾回收 (GC) 开销影响 | **分平台内核级零拷贝**：Win32 `TransmitFile`（Windows）/ `sendfile` + `epoll`（Linux）/ Darwin `sendfile` + `kqueue`（macOS），静态大文件与 Range 切片由内核直接 DMA 推送至网络套接字 | 极致吞吐，大幅削减 CPU 占用与上下文切换开销，内建 100ms 超时防悬挂与有界缓冲降级保护 |
| **路由兜底与 SPA** | 仅提供基础 `--spa`（404 简单重定向/回退到 `index.html`），可能意外掩盖权限与认证错误 | **同时支持 `--spa` 与 `--try-files <file>`**，且核心状态机**严格保留 401（未授权）与 403（禁止访问）** | 生产级 SPA 支持，彻底消除安全信息泄露与认证穿透隐患；支持 `--base-url` / `--base-dir` 灵活挂载 |
| **预压缩协商** | 仅按文件名后缀简单匹配 `.gz` / `.br` 是否存在，无内容合法性校验 | **Brotli (`.br`) 优先协商**，内置 **gzip 魔数校验（`0x1F 0x8B`）**，支持 `forceContentEncoding` | 杜绝伪劣残缺压缩文件错误下发，自动校验并优雅降级至原文件直接输出 |
| **WebSocket 代理** | 依赖第三方 `http-proxy` 模块，长连接异常断连容易发生句柄与连接挂死 | **原生全双工 WebSocket 代理**，内建 `Upgrade` 协议升级、透明双向管道与断连取消排空 | 彻底消除 IOCP 读阻塞死锁，高并发长连接跨周期实测 **0 句柄泄漏** |
| **运行时文件防护** | 静态服务期间无文件修改保护，文件被外部覆写/截断时客户端会收到损坏脏数据 | **D-17 运行时在途文件变更防御**，绑定已打开文件 handle，检测原地修改/截断实时终止排空 | 严格杜绝脏数据拼合与残卷传输，保证静态内容分发的高度确定性 |
| **网络故障注入韧性** | 缺乏异常报文切片与慢速攻击的系统性抗压测试 | **内建 T-034 状态机故障注入测试**：单字节短写切片、截断风暴、Slowloris 慢读反压 | 系统抗高并发混沌网络能力极强，`stop_and_drain` 优雅停机屏障排空保证 0 悬挂 |
| **部署与运行开销** | 需安装庞大的 Node.js 运行时与 `node_modules` 数百个依赖包，冷启动慢 | **纯 MoonBit 编译为独立机器码二进制**，零运行时依赖，冷启动毫秒级，常驻内存仅数 MB | 运维零负担，开箱即用，单可执行文件直接拷贝即可运行 |

---

## ✨ 核心特性

- **极速性能**：使用 MoonBit 最前沿的 Native 后端直接编译为原生机器码，Windows（`TransmitFile`）/ Linux（`sendfile`）/ macOS（Darwin `sendfile`）三平台均开启内核零拷贝。
- **独立 Native CLI**：无需安装 Node.js、V8 或 Python；平台系统 DLL 仍属于 Native 运行时依赖契约。
- **现代路由支持**：支持 BaseURL 路径挂载前缀、SPA 路由兜底及 `--try-files` 自定义降级策略。
- **智能预压缩协商**：优先支持 Brotli 与 gzip 双重内容协商，内建 gzip 魔数校验防损坏。
- **全双工代理**：支持 HTTP 404 反向代理与 WebSocket 协议升级长连接双向代理。
- **生产级安全性**：路径穿越防御（`..`、反斜杠、NUL 字符与越界拦截）、常量时间 Basic 认证、敏感错误隔离。
- **美观目录列表**：支持自动生成现代风格 HTML 目录列表视图，包含文件大小、伴生文件折叠与智能排序。
- **极简生命周期**：优雅响应 `Ctrl+C` 信号，支持在途请求排空，历经极端压测保证 0 句柄泄漏。

---

## 📦 安装指南

推荐使用 MoonBit 包管理器从源码编译安装：

```bash
# 完整版（支持 TLS 加密与反向代理）
moon install unmbt/http-server-mbt/cmd/http-server-mbt
http-server-mbt -v

# 或 Thin 版（明文静态托管，不含 TLS、代理、MbedTLS 或 PSA）
moon install unmbt/http-server-mbt/cmd/http-server-mbt-thin
http-server-mbt-thin -v
```

`moon install` 会将可执行文件安装到 `~/.moon/bin`。请确保该目录已加入 `PATH`。

### 预编译二进制

如果不希望从源码构建，可使用对应系统的安装脚本直接从最新的 GitHub Release 下载独立可执行程序：

提供两种独立 CLI 二进制版本：
- **Full（完整版，默认）**：包含完整静态文件托管、内置 MbedTLS 的 TLS 1.2/1.3 (HTTPS) 加密以及 HTTP/WebSocket 全双工反向代理（`http-server-mbt`）。
- **Thin（精简版）**：不含 TLS、代理、MbedTLS 或 PSA；Windows release 实测 1,602,560 字节，Full 为 3,884,544 字节，产物缩小约 58.75%。Windows 仍可能由通用 runtime 导入 `bcrypt.dll`，因此不宣称零系统加密库。

#### Linux & macOS

```bash
# 完整版（默认）
curl -fsSL https://raw.githubusercontent.com/unmbt/http-server-mbt/master/scripts/install.sh | bash

# Thin 版（轻量明文版本，不含 TLS/代理）
curl -fsSL https://raw.githubusercontent.com/unmbt/http-server-mbt/master/scripts/install.sh | bash -s -- --thin
```

#### Windows (PowerShell)

```powershell
# 完整版（默认）
irm https://raw.githubusercontent.com/unmbt/http-server-mbt/master/scripts/install.ps1 | iex

# Thin 版（轻量明文版本，不含 TLS/代理）
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/unmbt/http-server-mbt/master/scripts/install.ps1))) -Thin
```

> **注意**：预编译二进制安装脚本会将文件安装到 `~/.unmbt`（Windows 下为 `$HOME\.unmbt`），并将该目录加入 `PATH`。无论安装哪个版本，主执行程序均命名为 `http-server-mbt`（选择 `--thin` / `-Thin` 时还会额外创建 `http-server-mbt-thin` 软链接或副本）。安装完成后可能需要重启终端以使环境变量生效。

#### 嵌入式 C ABI SDK

如果需要在 C、C++、Rust、Zig、Go 或 Python 等项目中将 `http-server-mbt` 作为动态库（`.so` / `.dylib` / `.dll`）或静态库（`.a` / `.lib`）内嵌使用，可直接前往 [GitHub Releases](https://github.com/unmbt/http-server-mbt/releases) 页面下载独立的 `http-server-cabi-<platform>-<arch>.tar.gz`（Windows 为 `.zip`）归档包。该包内含 `http_server.h` 头文件、`thin` 与 `full` 双变体库及完整嵌入调用示例。详见 [C ABI 嵌入使用指南](docs/cabi-usage-guide.md)。

---

## 🚀 使用方法

直接在终端中运行即可：

```bash
http-server-mbt [root] [选项]
```

### 命令行选项说明

| 参数 | 说明 | 默认值 |
|---|---|---|
| `[root]` | 静态文件根目录路径 | `.` |
| `-p`, `--port <port>` | 监听的 TCP 端口（也可通过环境变量 `PORT` 指定） | `8080` |
| `--base-url <url>` | 挂载的 URL 路径前缀（如 `/docs/`） | `/` |
| `--base-dir <dir>` | `--base-url` 的别名 | `/` |
| `--spa` | 启用 SPA 模式：未命中请求回退到根目录的 `index.html`（保留 401/403） | 禁用 |
| `--try-files <file>` | 指定未命中时的自定义回退文件路径（相对于 root，保留 401/403） | 无 |
| `-c`, `--cache <time>` | 设置 Cache-Control 缓存时长（秒数或 `max-age=...`） | `3600` |
| `-i`, `--autoIndex` / `--no-autoIndex` | 是否在访问目录时自动寻找并展示默认 `index.html` | 开启 (`true`) |
| `-d`, `--showDir` / `--no-showDir` | 是否在找不到 `index.html` 时展示美观的 HTML 目录文件列表 | 开启 (`true`) |
| `--cors` | 启用 CORS 跨域支持，注入 `Access-Control-Allow-Origin` 等响应头 | 禁用 |
| `-a`, `--auth <user:pass>` | 启用 HTTP Basic 认证（用户名与密码以冒号隔开） | 禁用 |
| `-P`, `--proxy <url>` | 未命中静态文件时的备用反向代理目标 URL | 禁用 |
| `--proxy-all <url>` | 将所有传入请求无条件代理转发到目标 URL | 禁用 |
| `--proxy-config <file>` | 路由级反向代理规则配置文件路径或内联 JSON | 禁用 |
| `--cert <file>` | TLS 证书链文件（PEM），配置后启用 HTTPS 服务（内置 MbedTLS 4.2.0） | 禁用 |
| `--key <file>` | TLS 私钥文件（PEM） | 无 |
| `--key-passphrase <pass>` | 加密私钥的口令（或 `TLS_KEY_PASSPHRASE` 环境变量） | 无 |
| `-l`, `--log-ip` | 在控制台日志中记录访问客户端的 IP 地址 | 禁用 |
| `-s`, `--silent` | 静默模式，关闭终端请求日志输出 | 禁用 |
| `-h`, `--help` | 显示命令行帮助信息并退出 | - |
| `-v`, `--version` | 显示版本信息并退出 | - |

---

## 💡 示例

### 1. 基础静态托管
在端口 `3000` 上启动服务，托管 `./public` 目录：
```bash
http-server-mbt ./public -p 3000
```

### 2. 现代单页应用 (SPA) 路由托管
启用 SPA 兜底，自动将所有未命中的前端路由回退到 `index.html`，同时开启跨域与禁用缓存：
```bash
http-server-mbt ./dist -p 8080 --spa --cors -c -1
```

### 3. 子路径挂载与 Basic 认证
将服务挂载在 `/app/` 路径前缀下，并开启 Basic 密码保护：
```bash
http-server-mbt ./site -p 8000 --base-url /app/ -a admin:secret123
```

*终端输出演示：*
```text
Starting up http-server, serving ./public

http-server version: 0.1.5
http-server settings: 
CORS: true
Cache: 3600 seconds
Connection Timeout: 120 seconds
Directory Listings: visible
AutoIndex: visible
Serve GZIP Files: false
Serve Brotli Files: false
Default File Extension: none

Available on:
  http://127.0.0.1:8080
  http://192.168.1.10:8080
Hit CTRL-C to stop the server
```

---

## 🛠️ 从源码构建

确保已安装 [MoonBit 工具链](https://docs.moonbitlang.com/zh/latest/commands/installation.html)。

```bash
# 克隆仓库
git clone https://github.com/unmbt/http-server-mbt.git
cd http-server-mbt

# 安装依赖并检查
moon update
moon check --target native

# 运行全套测试（当前 Windows 基线为 240 项）
moon test --target native

# 编译原生 Release 二进制文件
moon build --target native --release
```

编译生成的原生二进制位于 `_build/native/release/build/cmd/http-server-mbt/http-server-mbt.exe`（Windows、Linux、macOS 三平台命令与产物名一致）。

---

## 📄 许可证

本项目基于 [MIT 许可证](LICENSE) 开源，依赖的底层异步库 `moonbitlang/async` 基于 Apache-2.0 许可证。
