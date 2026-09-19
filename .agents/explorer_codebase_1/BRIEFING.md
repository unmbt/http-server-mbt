# BRIEFING — 2026-09-18T13:26:00Z

## Mission
Investigate existing MoonBit codebase architecture to determine how to cleanly bridge `server` and `full` packages to the C ABI.

## 🔒 My Identity
- Archetype: explorer
- Roles: Teamwork explorer
- Working directory: E:/project/moonbit/unmbt/http-server-mbt/.agents/explorer_codebase_1
- Original parent: be14ba26-5f6e-4798-86b0-13c3fed6e4a0
- Milestone: C ABI Architecture Investigation

## 🔒 Key Constraints
- Read-only investigation — do NOT implement
- Investigate clean bridge of server and full packages to C ABI
- Follow project conventions, AGENTS.md, and SDD workflow

## Current Parent
- Conversation ID: be14ba26-5f6e-4798-86b0-13c3fed6e4a0
- Updated: 2026-09-18T13:12:27Z

## Investigation State
- **Explored paths**: `server/`, `full/`, `cmd/`, `core/`, `tls/`, `moon.mod`, `moon.pkg`, `.mooncakes/`, `_build/native/`, MSVC / MinGW toolchains, generated C code.
- **Key findings**:
  1. `server` and `full` both use scoped `with_server_at(config, port, action)` with graceful `stop_and_drain()` and cancel on exit.
  2. To bridge scoped MoonBit async server to C ABI handle-based lifecycle (`hs_server_start`/`stop`), an internal owner OS thread runs `@async.run_async_main` and awaits stop events.
  3. MoonBit exports functions via `pkgtype(kind: "foreign_library")` and `#export_name("...")`. Generated C has no `main()`, only `moonbit_init()`.
  4. While `moon build` fails on Native during the final exe link step for `foreign_library`, the `.c` and `.obj` are successfully generated and can be linked via `scripts/build_cabi.mbtx`.
  5. Stripping `.drectve` from runtime dependency objects using `objcopy --remove-section=.drectve` achieves 100% pure export tables in MSVC DLLs with only `hs_*` symbols.
  6. Sub-packages `c_abi/min` and `c_abi/full` with header `c_abi/include/http_server.h` is the cleanest package architecture.
- **Unexplored areas**: None within the scope of this investigation.

## Key Decisions Made
- Recommended package structure: `c_abi/` containing `include/http_server.h`, `min/` (`moon.pkg`, `abi.mbt`, `bridge.c`, `hs_min.def`), and `full/` (`moon.pkg`, `abi.mbt`, `bridge.c`, `hs_full.def`).
- Recommended lifecycle model: Background owner thread per server instance managed by C bridge.
- Recommended symbol isolation: Strip embedded `/EXPORT` directives from runtime dependencies.

## Artifact Index
- handoff.md — Final 5-component handoff report
- progress.md — Heartbeat and step log
- DISPATCH.md — Received requests log
