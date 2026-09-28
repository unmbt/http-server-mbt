# ABI 1.1 异步嵌入实施记录

关联 R-N06/R-N09/R-N14/R-N15/R-N16；D-07/D-11/D-12/D-17/D-18；T-020/T-021/T-028 及其运行时、打包和资源验证依赖。

状态：进行中。2026-09-28 实施；Windows 本机分项证据如下，三平台总体验收仍待同提交 Actions 结果。

保留 ABI major 1、旧五个导出与错误码 0～5。新的异步入口复制输入，返回接纳状态和 operation；拒绝不回调，接纳恰好一次回调。回调只转交结果，不同步等待本实例关闭。关闭后不再业务回调；release 释放外部引用，不能替代显式关闭。正文错误（特别是 FILE_CHANGED）不是 EOF。

所有权：回调事件仅在回调内借用；事件中的成功 engine/server/response/chunk 转移一个外部引用给宿主。operation 输出引用由调用者 release；库独立保留执行/通知引用。response 元数据借用到 response_release，chunk 字节有效至 chunk_release。关闭不等待宿主归还已经交付的不可变字节。必须在关闭回调返回且全部引用释放后卸载库。

框架示例使用 `handle_error=false`、`cache_control="no-cache"`。宿主负责网络、TLS 与背压，库负责安全路径、文件正文、取消与资源排空。

## 构建与运行

运行 `moon run scripts/build/build_cabi.mbtx`、`moon run scripts/build/build_node.mbtx`，再运行 `moon run scripts/build/build_framework_examples.mbtx` 和 `moon run scripts/check/check_framework_examples.mbtx`。Windows 可用 `VCINSTALLDIR` 指定 MSVC、`PYTHON` 指定 Python 3.12。所有构建、依赖安装、进程编排和网络验收均由 `.mbtx` 执行。

- C：`examples/c/libevent_server.c` 同时编译为 `libevent_static`（Thin 静态链接）与 `libevent_dynamic`（运行时加载）；参数为 JSON 配置、端口、动态库路径。示例监听 loopback，`/__shutdown` 仅用于示范退出顺序。
- Python：`examples/python/hs_async.py` 提供 `Engine.create()`、`handle_request()`、响应异步迭代和 `aclose()`；`hs_asgi.py` 管理 lifespan 与 disconnect；`app.py` 为 FastAPI/Uvicorn 示例。设置 `HS_LIBRARY`、`HS_ROOT` 后用隔离环境运行。必须在 asyncio loop 关闭之前 `aclose()`；不要只依赖垃圾回收。
- Node：`examples/node/app.cjs` 使用 Express 5.1.0，挂载 `/static`，展示静态、Next 动态路由、错误链和关闭。引擎处理 Express 剥离挂载点后的 `req.url`；引擎 `base_url` 不重复配置宿主挂载前缀。

## 生命周期与边界

Node 使用每操作 TSFN，无引擎轮询线程。worker 终止可能先触发 TSFN finalizer，再收到 native 完成；工作项因此以互斥锁/条件变量等待 native 最终完成后释放，晚回调不访问已终结 TSFN。未交付结果在宿主清理阶段归还；环境退出的排空不依赖 JS 或第二个 TSFN。正常 handle/read/close 仍返回 Promise；环境销毁和遗弃句柄的最终回收允许等待 native 关闭屏障。

每个链接的 Thin/Full runtime 各有一个 owner 和一个 notifier，多个实例共用；没有宿主 pump。入口复制配置（最多 1 MiB）和请求（方法最多 64 字节、target 最多 16 KiB、最多 256 个头、头与请求字符串合计最多 64 KiB）。无监听引擎使用 `Config::middleware_default`，正文块默认 64 KiB。重复 Host、Authorization、Content-Length、Transfer-Encoding、CL/TE 歧义及非法控制字符由与 HTTP framing 共用的验证器拒绝；其余重复值按逗号合并，Cookie 用分号。

一个响应只允许一个在途 read；未归还上一 chunk 时，下一 read 等待归还或取消。宿主持有 chunk 的字节、响应元数据、复制输入和业务操作记录受 C 桥接预算限制；Native 文件池另执行自己的正文和目录预算。桥接有 64 MiB runtime 总上限、256 个创建/并发接纳上限及 1024 个实例上限；每实例业务容量跟随 limits。控制操作不占业务队列配额，取消/关闭在业务队列满时仍可提交。系统分配失败仍可返回 LIMIT。

close 排空已接纳业务通知后才通知完成。返回后的 response/chunk 元数据和字节仍按各自引用生命周期有效；已关闭实例不能再读取。正常宿主线程在关闭后 release engine 或最后 operation 时，等待通知返回并 join 最后 runtime 的线程；库回调线程的 release 不等待。动态卸载必须在宿主线程执行这一屏障并释放全部句柄，不能在库通知中卸载。失败/取消不是 EOF；FILE_CHANGED 不自动重试或拼接新版本。

## 嵌入入口与依赖

固定 `moonbitlang/async 0.21.3`。`c_abi/embedded/integration.mbt` 是上游 Apache-2.0 integration 的最小 Native 变体，保留公开签名，在 `with_event_loop` 正常异常展开后返回。构建脚本只在 `target/cabi-build` 重新编译该包的 core，再按 Moon dry-run 的 link-core 计划生成 ABI C，检查生成代码无 `exit(`。不编辑 `.mooncakes`、不修改生成 C，普通 CLI 使用原入口。

仅 ABI staging 使用 `embedded_signal.c` 替换上游 signal 对象，不安装/恢复宿主 signal handler。POSIX 还以 `embedded_thread_pool.c` 包装固定上游线程池，禁止其安装全局 SIGPIPE/SIGUSR2 handler；owner 仅阻塞自身线程的 SIGPIPE，worker 继承屏蔽。上游 POSIX 阻塞任务取消等待自然完成，不再发送 SIGUSR2；这可能使 DNS 等系统阻塞调用的关闭等待更久，不承诺即时抢占。静态引擎独立文件池的有界读取/取消不变。消费者检查 SIGTERM、POSIX SIGPIPE/SIGUSR2 的宿主处理器保持不变；POSIX 路径待对应 runner 实测。owner 意外返回时拒绝接纳、将待处理命令完成为 IO 并退休实例；通知线程完成后由宿主 join，重建引擎可以重新启动。Thin 符号检查继续拒绝 MbedTLS/PSA；19 个导出由 `c_abi/exports.txt` 固定。

libevent 来源、SHA-256 与许可证见 [examples/c/PROVENANCE](../examples/c/PROVENANCE.md)，仅为示例构建依赖。Python 完整版本固定于 requirements，Node 直接和传递依赖固定于 package-lock。glibc 和 musl npm 产物明确区分；没有匹配包时报告缺少对应构建，不尝试加载另一 libc。

## 本机验证记录

Windows x86_64；Moon 0.1.20260920 / moonc 0.10.14；MSVC 14.44.35207。工作树未提交，不能将现有 HEAD 哈希冒充本改动的源码提交。

- Native 全套：266/266 通过（新增共享头验证后）。
- C ABI：Thin/Full 静态/动态旧消费者、新异步消费者通过；严格导出名单、Thin 无 TLS 符号、受控入口无 exit 检查通过。
- Node 22.21.1 / 24.10.0：离线候选包消费均通过（旧入口 6 项 + 异步用例），含多实例、worker 在途退出和自然退出、流提前退出、AbortSignal、FILE_CHANGED，以及 304/416/预压缩/目录多块/BaseURL/SPA/try-files/认证/长配置。新增 musl 诊断测试验证不尝试加载 glibc 产物。
- libevent 静态/动态、FastAPI/Uvicorn、Express：真实 HTTP GET/HEAD/Range、多块、Next、慢客户端断连、关闭通过；Express 验证挂载路径与未提交响应的错误链。libevent 关闭路由的最小竞态回归为“写出响应 → 写完成回调 → 关闭引擎 → 释放宿主 → 卸载”；不能在关闭响应尚未写出时直接释放 evhttp。
- ASan：实际 Native 文件池及实际 C ABI 队列/引用/线程实现，固定种子 `2442cafe/00000001/ffffffff` 通过。ABI sanitizer harness 仅替换 MoonBit dispatcher，不能代替实际库消费者；Windows 不宣称 LeakSanitizer/UBSan 结果。Linux 配置 ASan+UBSan+LSan，macOS 配置适用 ASan+UBSan。

Node 回归记录：先前一次候选复验在 worker 提交 64 个请求后强制终止时崩溃。真实 addon 的 MSVC ASan 报告 `work_completed` 写入已由 `work_finalizer` 释放的工作项；原因为错误假设 TSFN finalizer 总在 native 完成后运行。保留该失败原因，测试扩展为连续 8 次 worker 终止并验证另一环境引擎仍可用。`scripts/check/check_node_sanitizer.mbtx` 构建实际 addon ASan、运行异步消费者并恢复普通产物，日志保存为 `target/sanitizer/node-v*.log`；Windows Actions 的 Node 22/24 均执行它。底层 MoonBit 静态库没有因此变成全库 ASan 构建，另由文件池/C ABI harness 覆盖 C 资源实现。

附加本机 Linux 分项：WSL FedoraLinux-43 x86_64，GCC 15.2.1；`gcc -fsyntax-only -pthread -I<moon/include> c_abi/runtime/embedded_thread_pool.c` 通过。`gcc -std=c11 -pthread -g -O1 -fsanitize=address,undefined -fno-omit-frame-pointer -I<moon/include> tests/native_sanitizer/abi.c -o <abi-linux>` 后，三个固定种子均报告 `concurrent submit/cancel/close/restart/bootstrap-failure; drained` 并以 0 退出，无 sanitizer 报告。这只覆盖 POSIX C 桥接和包装源码编译，不是 Linux 完整 MoonBit ABI/文件/宿主验收。

新增共享请求头包 wasm-gc 测试通过；外部 C/Rust/Python 旧服务消费者及独立 MoonBit engine/Thin/Full 消费通过。`moon info` 生成接口中删除的是旧 Thin/Full 的 MoonBit 桥接内部 runner（不是 C 导出），新运行时仅公开跨包注册与入口；原五个 C 导出保持。

三平台 Actions、同提交产物哈希与 run/job 链接尚未取得；T-020/T-021/T-028 及关联总任务保持进行中，不作 registry 发布声明。

最后复验（同一 Windows 工作树，2026-09-28）：`fnm exec --using=22.21.1 moon run scripts/check/check_node_sanitizer.mbtx` 与 24.10.0 均通过 6/6 异步组；恢复普通插件后，两版本 `check_node_candidate.mbtx` 均通过旧入口 6/6 与异步 6/6；`check_framework_examples.mbtx` 四种宿主全部通过。`check_automation.mbtx` 检查根构建入口与 22 个维护脚本通过，`git diff --check` 通过。源码包检查、Native 266/266、`moon info --target native` 与接口审查见此前记录；本次竞态修复仅改 C/Node 层及自动化，没有再改 MoonBit 包源码。

本机普通产物 SHA-256（未提交工作树产物，不充当同提交 Actions 证据）：

| 文件 | SHA-256 |
|---|---|
| `target/cabi/hs_thin.dll` | `8335C95E946ABA94FA94430865D946780B381736DDBB877F3D60DA21FB44F806` |
| `target/cabi/hs_full.dll` | `A6C5A8734DF8FD14318F05026AC938C391AC306ADB285A0E55FBE1690B50D7BE` |
| `target/node/http_server.win32-x64-msvc.node` | `1507F29DD1583A54CE377A440A2381B90B838FC540B991AE9E07D767ECD73D0F` |
