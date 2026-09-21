# DISPATCH

## 2026-09-18T12:01:35Z
You are the Project Orchestrator for the `thin` & `full` layered packaging, TLS decoupling, and Proxy architecture readiness project in `http-server-mbt`.

Your working directory is: `E:\project\moonbit\unmbt\http-server-mbt\.agents\orchestrator_pkg_1`
The project root is: `E:\project\moonbit\unmbt\http-server-mbt`
The authoritative user request is recorded in: `E:\project\moonbit\unmbt\http-server-mbt\ORIGINAL_REQUEST.md` (and `.agents/ORIGINAL_REQUEST.md`).

Please read the latest section of `ORIGINAL_REQUEST.md` (timestamp `2026-09-18T12:00:00Z`) for complete requirements:
1. R1: Decouple Server from TLS (abstract transport / connection handling so static server does not hard-depend on `tls` package or MbedTLS C stubs; dependency injection for TLS in `full` build; zero regression on all 183 existing tests).
2. R2: Thin & Full CLI build & distribution (`thin` CLI errors out with code 1 if `--cert`, `--key`, `--proxy` are given; `full` CLI supports TLS and future proxy args; separate entry points or build scripts).
3. R3: C ABI dynamic & static library export pipeline (`.mbtx` script-driven export of `.dll`/`.so`/`.dylib` and `.lib`/`.a`; strictly `hs_*` exports with no CLI main pollution; `thin` library completely free of MbedTLS symbols; minimal C verification program).
4. R4: Reverse Proxy architecture design & interface readiness (align with original C037~C039, C041, T-013, state machine Resolving -> Proxying -> Idle, config data structures, streaming forward interface).
5. Strict SDD workflow: update `docs/design.md`, `docs/tasks.md` / ADRs.
6. Automation: scripts must use `.mbtx`.
7. Quality gates: MoonBit code changes must pass `moon check --target native`, `moon test --target native`, `moon info --target native`, and `moon fmt`.
8. Git constraint: local commits only, NEVER execute `git push`.
9. Team structure: decompose the work into milestones/subtasks and dispatch to specialized subagents (explorers, implementers/workers, reviewers, challengers, forensic auditor). Multi-role independent gate verification is mandatory.
10. Maintain `BRIEFING.md` and `progress.md` in your working directory.
11. When work is complete and all gates pass, submit your victory claim and final handoff report back to Sentinel.

## 2026-09-18T12:31:25Z
【用户最新追加指令更新 (User Follow-up Directive)】：
用户指令：“继续做完当前的cli部分min/full打包，但是准备开始做动态库静态库导出前记录已完成的工作内容后停下来，以便后面能根据记录的文档继续完成动静态库导出的实现”

请 Project Orchestrator 严格执行：
1. 继续完成 Milestone 1（Server 与 TLS 依赖解耦）与 Milestone 2（Thin/Full 双版本 CLI 打包、验证与全量测试保护）。
2. 在进入 Milestone 3（动静态库导出）之前：
   - 详细记录已完成的工作内容；
   - 编写动静态库导出的接续指南文档；
   - 立即停下来（PAUSE / STOP），暂不启动 Milestone 3 的实施，向用户汇报当前阶段成果！
