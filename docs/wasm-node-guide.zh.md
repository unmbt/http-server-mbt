# Node WasmGC 使用指南

这是在 **Node 中运行的 WasmGC 静态文件引擎**：MoonBit `.wasm` 决定路由、响应头、缓存、Range 和目录页面，Node 提供文件 I/O 与 HTTP 监听。浏览器可以访问它提供的网站；将 `.wasm` 直接放进浏览器或云 Worker 运行不在当前支持范围。

已验证 Node **22.21.1 / 24.10.0**，Windows x64、Linux x64、macOS arm64。三平台结果、提交与产物哈希见[验收记录](wasm-node-20261013.md)。运行时只需 Node 和完整 Wasm 分发目录，不需要 MoonBit、C 编译器、npm 安装或 `.node` 插件。

## 从源码构建并启动

在仓库根目录执行。构建使用 MoonBit `0.10.17+093cb8f9c` 发行工具链及配套 core（`moon version --all` 中 Moon 为 `0.1.20261021`）。

```powershell
moon update
moon run scripts/build/build_wasm.mbtx
$env:HS_ROOT = "testdata/public"
node examples/wasm-node/app.mjs
```

Linux/macOS：

```sh
moon update
moon run scripts/build/build_wasm.mbtx
HS_ROOT=testdata/public node examples/wasm-node/app.mjs
```

访问 <http://127.0.0.1:8080/hello.txt>，应看到 `hello moonbit`。可用以下请求检查 HEAD 和 Range（PowerShell 使用 `curl.exe`）：

```sh
curl -I http://127.0.0.1:8080/hello.txt
curl -i -H 'Range: bytes=0-4' http://127.0.0.1:8080/hello.txt
```

第二个请求返回 `206`、`Content-Range: bytes 0-4/14`，正文为 `hello`。按 Ctrl+C 关闭，服务会停止接纳请求、取消正文并等待文件操作排空。

## 使用 CI 产物，无需本地编译

从[已通过的 Actions](https://github.com/unmbt/http-server-mbt/actions/runs/38378097351) 页面下载对应平台的 `candidate-*` artifact，解压后取出完整的 `wasm/` 目录。也可以用 GitHub CLI 下载，例如：

```sh
gh run download 38378097351 --repo unmbt/http-server-mbt --name candidate-Windows-X64 --dir downloaded-candidate
```

保留其中的 `engine.wasm`、`app.mjs`、`index.mjs`、`host.mjs`、`loader.mjs`、`index.d.ts`、`README.md`、`LICENSE` 和 `licenses/`。`licenses/` 中包含项目第三方声明、WasmGC 依赖审计以及实际工具链的 core 许可/NOTICE。Wasm 宿主只依赖用户提供的 Node 内置模块，不打包 Node、npm、Native addon、TLS 或 CA 证书；io_uring 也不属于 Wasm 运行时。完整边界见[依赖审计](dependency-audit-20261024.md)。这些是候选产物，未作为 npm 包发布；Actions artifact 有保留期限（当前 14 天），过期后从相同提交构建。

进入 `wasm/` 目录，设置**资源目录的绝对路径**后启动：

```powershell
$env:HS_ROOT = "D:/sites/public"
$env:PORT = "8080"
node app.mjs
```

Linux/macOS 使用 `HS_ROOT=/srv/site/public PORT=8080 node app.mjs`。也可搬移本地构建生成的 `target/wasm/`，用同样方式运行。文件相对路径以启动时的工作目录为准，Wasm 二进制则由 loader 相对自身位置寻找。

## 配置静态站点

| 入口 | 含义与默认值 |
| --- | --- |
| `HS_ROOT` | 服务的真实目录；优先于 `HS_CONFIG.root`，默认当前工作目录 |
| `PORT` | HTTP 端口，默认 `8080`；`0` 分配临时端口，启动日志显示实际端口 |
| `HS_CONFIG` | 静态引擎配置的 JSON 对象，默认 `{}` |

例如将 `public/` 中的 SPA 挂在 `/app`，禁用目录列表和缓存：

```powershell
$env:HS_ROOT = "D:/sites/public"
$env:PORT = "8081"
$env:HS_CONFIG = '{"base_url":"/app","spa":true,"show_dir":false,"cache_seconds":-1}'
node examples/wasm-node/app.mjs
```

此时访问 <http://127.0.0.1:8081/app/>；SPA 启动时要求根目录中有可读的 `index.html`。环境变量会保留在当前终端，换示例时请相应修改。

常用选项（完整定义见 [index.d.ts](../examples/wasm-node/index.d.ts)）：

| 选项 | 默认值 | 作用 |
| --- | --- | --- |
| `base_url` | `"/"` | URL 挂载前缀，不改变文件根目录 |
| `default_ext` | `"html"` | 无扩展名路径补全；`null` 关闭 |
| `spa` / `try_files` | `false` / `null` | 回退到根 `index.html` 或指定的根内相对文件，二者不能同时设置 |
| `auto_index` / `show_dir` | `true` / `true` | 优先索引页；没有索引时可显示目录 |
| `show_dotfiles` | `false` | 目录页是否显示点文件 |
| `gzip` / `brotli` | `true` / `false` | 协商已有 `.gz` / `.br` 文件，不现场压缩 |
| `cache_seconds` | `3600` | 缓存秒数；`-1` 禁用缓存 |
| `handle_error` | `true` | `false` 时适用的未处理请求返回 `next`，交给宿主继续处理 |
| `basic_auth` | 不设置 | `["用户名", "密码"]` |

自定义 404 使用根目录的 `404.html`。端口及监听地址属于 HTTP 宿主配置，不放在 `HS_CONFIG` 或 `createEngine` 的配置中；未知字段、TLS、代理及服务器专属字段会被拒绝。脚本入口默认监听 `127.0.0.1`。

## 在 Node 程序中调用

将以下示例保存为仓库根目录的 `use-wasm.mjs`，先构建，然后运行 `node use-wasm.mjs`。使用分发目录时，将 import 改为该目录的 `index.mjs` 路径。

```javascript
import { createEngine } from './examples/wasm-node/index.mjs';

const engine = await createEngine({ root: './testdata/public' });
const controller = new AbortController();
try {
  const result = await engine.handle({
    method: 'GET',
    target: '/hello.txt', // 原始 URL 路径及查询串，不是完整网址
    headers: [['Range', 'bytes=0-4']],
    signal: controller.signal,
  });
  if (result.kind === 'next') {
    console.log('交给其他路由处理');
  } else {
    console.log(result.status, result.headers, result.contentLength);
    try {
      for await (const bytes of result.body) process.stdout.write(bytes);
    } finally {
      result.body.destroy();
    }
  }
} finally {
  await engine.close();
}
```

`createEngine` 异步装载并预检；`handle` 返回 `next` 或 `handled`。后者包含状态、响应头对、`bigint | null` 长度和 Node Readable；长度不能直接放进 JSON，要显式转字符串。每个正文都应消费或销毁，即使不需要内容。AbortSignal 在正文消费期仍有效。`close()` 可重复调用，等待在途操作和文件句柄释放，不需要应用 pump/poll。

如果只想从程序中启动示例 HTTP 服务，可以直接使用现成适配器：

```javascript
import { serve } from './examples/wasm-node/app.mjs';

const running = await serve(
  { root: './testdata/public' },
  { port: 8080, address: '127.0.0.1' },
);
process.once('SIGINT', () => {
  running.close().catch(error => { console.error(error); process.exitCode = 1; });
});
```

嵌入已有 HTTP 框架时参考 [app.mjs](../examples/wasm-node/app.mjs)：转交原始 method/target/headers、将断连接到 AbortSignal、尊重写入背压，正文错误发生在发头之后应终止响应。`next` 不提交响应；示例独立 HTTP 适配器把它转换为 404，应用框架可以继续后续路由。

## 资源、变更与错误

每个引擎的 `limits` 可限制并发 I/O（`file_workers=4`）、排队操作（`queued_operations=256`）、活动请求（`connections=1024`）、正文块（`body_block_bytes=65536`）、正文预算及目录元数据预算（后两项各 64 MiB）。`connections` 在此约束引擎请求，不等同于 Node HTTP socket 数量。生成的目录页跨 JSON 桥接还需额外内存额度，实际块大小可能为适应预算而缩小。慢消费通过 Readable 背压暂停后续读取。

| 错误/表现 | 处理方式 |
| --- | --- |
| `HS_UNSUPPORTED` | 核对 Node 版本、Wasm 是否已构建、分发文件是否匹配；查看 `error.cause` |
| `HS_INVALID_REQUEST` | 核对配置字段、类型、SPA/try-files 冲突和回退文件 |
| `HS_FORBIDDEN` | 检查目录权限、路径边界和 symlink/junction |
| `HS_OVERLOADED` | 预算或队列耗尽；降低并发、及时释放正文，或调整容量 |
| `HS_FILE_CHANGED` | 丢弃已收到的响应；如需重试，从偏移 0 重新下载，不能拼接旧正文 |
| `HS_CANCELLED` / `HS_CLOSED` | 请求已取消或引擎正在关闭 |
| 启动时报 `EADDRINUSE` | 更换 `PORT`，或关闭占用端口的服务 |

请求计划期错误使 Promise 拒绝；正文期错误由流传播。示例 HTTP 适配器在尚未提交响应时将文件变化返回 409，已经开始响应则断开连接。它不自动重试。

只服务部署者控制的真实目录，拒绝 symlink/junction（包括根路径组件）；不承诺抵御恶意并发目录替换。文件内容允许更新，下载保持同一个打开句柄，在提交前、读前/后和 EOF 检查身份/长度/时间戳。元数据检测不是不可变快照，存在文件系统精度及恢复元数据等边界。Windows 的 `fs.rename` 原子覆盖已打开文件可能返回 `EPERM`，详见验收记录。

## 开发者验证

运行示例只需上述 Wasm 构建。完整候选验收另包含 Native/Wasm 差分进程，需要先构建 Native C ABI 和 addon：

```powershell
moon run scripts/build/build_cabi.mbtx
moon run scripts/build/build_node.mbtx
$env:HS_WASM_NODE = "D:/runtimes/node22/node.exe"
moon run scripts/check/check_wasm_candidate.mbtx
```

再换 Node 24.10.0 重跑。Windows 用各自目录中原名为 `node.exe` 的运行时。普通 Wasm 验收进程不加载 addon，只有单独差分进程加载。日志输出到 `target/candidate/wasm/`；语料和种子见 [testdata/wasm](../testdata/wasm/README.md)。三平台 CI 会执行同一驱动，不能用本机单平台结果替代。
