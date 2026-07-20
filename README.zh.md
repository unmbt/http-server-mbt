<div align="center">

[English](./README.md) | [简体中文](./README.zh.md)

# 🚀 http-server-mbt

*一款使用 [MoonBit](https://moonbitlang.com) 编写的极速、零依赖的静态 HTTP 服务器。*

[![MoonBit](https://img.shields.io/badge/Language-MoonBit-f86800?logo=moonbit&logoColor=white)](https://moonbitlang.com)
[![Build Status](https://img.shields.io/github/actions/workflow/status/unmbt/http-server-mbt/ci.yml?branch=master&logo=github)](https://github.com/unmbt/http-server-mbt/actions)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Cross Platform](https://img.shields.io/badge/Platform-Windows%20%7C%20Linux%20%7C%20macOS-success)](#)
[![Native Speed](https://img.shields.io/badge/Backend-Native_C_FFI-8a2be2)](#)

</div>

## ✨ 特性

- **极速性能**：使用 MoonBit 最前沿的 Native 后端直接编译为机器码。
- **零依赖**：作为一个独立的二进制文件分发。无需安装 Node.js、Python 或任何其他运行时环境！
- **跨平台**：完美支持 Windows、macOS 和 Linux。
- **智能 IP 探测**：在启动时自动检测并打印真实的本地网卡 IP 地址。
- **反向代理支持**：使用 `--proxy` 参数可轻松将未命中（`404`）的请求转发到上游服务器。
- **开发者体验友好**：提供与经典的 npm `http-server` 一致的高颜值彩色终端输出，并优雅地拦截和处理 `Ctrl+C` 退出信号。
- **目录浏览**：如果找不到 `index.html`，会自动生成清晰美观的 HTML 目录文件列表。

## 📦 安装

我们为 Windows、macOS 和 Linux 提供了全自动的安装脚本。脚本会自动下载适合你系统的二进制文件，放置在 `~/.unmbt` 目录下，并优雅地处理版本升级。

### 🍎/🐧 macOS & Linux

打开你的终端，运行以下命令：

```bash
curl -fsSL https://raw.githubusercontent.com/unmbt/http-server-mbt/master/scripts/install.sh | bash
```

> **注意：** 脚本会自动尝试将 `~/.unmbt` 目录追加到你的 `~/.zshrc` 或 `~/.bashrc` 中。你可能需要重启终端才能使环境变量生效。

### 🪟 Windows

以管理员（或普通用户）身份打开 PowerShell，然后运行：

```powershell
irm https://raw.githubusercontent.com/unmbt/http-server-mbt/master/scripts/install.ps1 | iex
```

> **注意：** 脚本会自动尝试将 `C:\Users\<你的用户名>\.unmbt` 写入到当前用户的系统环境变量（Path）中。你可能需要重启终端以使其生效。

---

### 🔄 更新

升级非常简单！只需为你所在的操作系统**重新运行上面一模一样的安装命令**即可。脚本会自动检测你当前的版本，检查是否有最新的 Release 版本，只有在需要时才会进行无缝的覆盖更新！

### 🗑️ 卸载

- **macOS/Linux**: 运行 `bash -c "$(curl -fsSL https://raw.githubusercontent.com/unmbt/http-server-mbt/master/scripts/install.sh)" -- uninstall`
- **Windows**: 运行 `& ([scriptblock]::Create((irm https://raw.githubusercontent.com/unmbt/http-server-mbt/master/scripts/install.ps1))) -Uninstall`

<details>
<summary><b>🛠️ 从源码构建</b></summary>

请确保你已经安装了 [MoonBit 工具链](https://docs.moonbitlang.com/zh/latest/commands/installation.html)。

```bash
git clone https://github.com/unmbt/http-server-mbt.git
cd http-server-mbt
moon update
moon build --target native --release --target-dir target
```
编译好的二进制可执行文件将被放置在 `target/native/release/build/src/main/` 目录下。
</details>

## 🚀 使用方法

直接在终端中运行即可：

```bash
http-server-mbt [选项]
```

### 命令行选项

| 参数 | 描述 |
|---|---|
| `-p`, `--port <port>` | 指定端口（默认为 `8080`） |
| `-a`, `--address <addr>` | 指定监听地址（默认为 `0.0.0.0`） |
| `-d`, `--dir <dir>` | 指定静态服务根目录（默认为 `./`） |
| `-c`, `--cache <time>` | 设置 Cache-Control 的 max-age 缓存时间（秒，默认为 `3600`） |
| `--cors` | 启用跨域支持，注入 `Access-Control-Allow-Origin` 响应头 |
| `-e`, `--ext <ext>` | 找不到文件时的默认文件扩展名（例如 `html`） |
| `-P`, `--proxy <url>` | 代理转发未命中请求（404）到指定的上游 URL |
| `-D`, `--debug` | 开启 Debug 模式，在终端打印详细的请求和执行日志 |

## 💡 示例

在端口 `3000` 上启动服务，映射 `public` 文件夹，启用 CORS 跨域，并将所有 404 未命中请求转发到 `http://localhost:8000`：

```bash
http-server-mbt -d ./public -p 3000 --cors -P http://localhost:8000
```

*终端输出演示：*
```text
Starting up http-server, serving ./public

http-server version: 0.1.0
http-server settings: 
CORS: true
Cache: 3600 seconds
Connection Timeout: 120 seconds
Directory Listings: visible
AutoIndex: visible
Serve GZIP Files: false
Serve Brotli Files: false
Default File Extension: none
Unhandled requests will be served from: http://localhost:8000

Available on:
  http://127.0.0.1:3000
  http://192.168.1.10:3000
Hit CTRL-C to stop the server
```

## 🛠 硬核架构解析

- **路由与代理层**: 全程基于 MoonBit 提供的 `moonbitlang/async` 异步网络接口实现无阻塞的静态文件伺服与 HTTP 代理。
- **底层 Native C-FFI**: 为了达到完美的体验，真实网卡 IP 的嗅探和 `SIGINT` (Ctrl+C) 中断信号拦截等功能是由 C 语言编写的 (`src/server/get_ip.c`)，并通过 MoonBit 的 Native 后端实现了无缝桥接与跨平台编译。
- **编译期配置嵌入**: 使用了 MoonBit 的 `:embed` 宏指令，在代码编译期间直接将项目版本号等配置元数据硬编码打入最终的二进制产物中。

## 🤖 特别鸣谢

本项目全程使用 **[Google Antigravity CLI](https://github.com/google/antigravity)** 与 **Google Gemini AI** 结对编程开发。
它展现了在像 MoonBit 这种前沿系统级语言中，人机协同不仅能极速完成跨平台的底层架构搭建，还能将代码的性能与优雅发挥到极致！

## 📄 许可证

本项目基于 [MIT 许可证](LICENSE) 开源。
