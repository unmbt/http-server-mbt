# BRIEFING — 2026-09-11T15:23:45+08:00

## Mission
Design exact architecture and implementation strategy in core/ for Config model expansion, BaseURL route mounting (boundary matching), and SPA/try-files mutual exclusion validation.

## 🔒 My Identity
- Archetype: explorer
- Roles: teamwork_preview_explorer
- Working directory: D:\project\moonbit\http-server-mbt\.agents\explorer_m2_config_routing
- Original parent: c9a1c62c-d24a-4e26-aba4-e472238529d1
- Milestone: M2

## 🔒 Key Constraints
- Read-only investigation — do NOT implement source changes
- Do not edit files outside `.agents/explorer_m2_config_routing/`
- Target: `core/` package and configuration/routing contracts
- Output: `strategy.md`, `handoff.md`, `progress.md`
- Message parent with summary

## Current Parent
- Conversation ID: c9a1c62c-d24a-4e26-aba4-e472238529d1
- Updated: not yet

## Investigation State
- **Explored paths**:
  - `core/core.mbt`, `core/core_test.mbt`, `core/moon.pkg`, `core/pkg.generated.mbti`
  - `engine.mbt`, `server/server.mbt`, `cmd/http-server-mbt/main.mbt`
  - `docs/design.md` (D-01, D-04, D-10), `docs/tasks.md` (T-003, T-019), `docs/proposal.md`
  - `http-server/test/main.test.js` (baseDir test), `http-server/doc/http-server.1`
  - `.agents/orchestrator_1/PROJECT.md`, `.agents/spec_miner_docs/`
- **Key findings**:
  - `core.Config` has only 9 fields, missing 21 settings including `port`, `spa`, `try_files`, `proxy`, `basic_auth`, `host_whitelist`.
  - AD-02 requires dual defaults: CLI/Server `gzip: false`, Core middleware `gzip: true`.
  - D-04 requires strict component boundary matching: `/app` matches `/app` and `/app/page`, but strictly rejects `/application` (403 Forbidden).
  - Pre-listen validation requires mutual exclusion between `--spa` and `--try-files`, and between page fallback and `--proxy`.
  - Security/auth errors (401, 403, traversal) must never be swallowed into SPA fallback.
- **Unexplored areas**:
  - No unexplored areas within M2 config and routing scope.

## Key Decisions Made
- Designed 30-field `core.Config` with dual constructors (`Config::default` and `Config::middleware_default`).
- Designed pure `match_and_strip_base_url` for component boundary matching with zero platform I/O.
- Designed `validate_config` for pre-listen syntactic validation and mutual exclusion.
- Proposed splitting `core/` into `config.mbt`, `routing.mbt`, and `core.mbt` to prevent monolith conflicts.

## Artifact Index
- D:\project\moonbit\http-server-mbt\.agents\explorer_m2_config_routing\BRIEFING.md — Working memory and identity
- D:\project\moonbit\http-server-mbt\.agents\explorer_m2_config_routing\progress.md — Liveness heartbeat
- D:\project\moonbit\http-server-mbt\.agents\explorer_m2_config_routing\strategy.md — Complete architecture & implementation strategy
- D:\project\moonbit\http-server-mbt\.agents\explorer_m2_config_routing\handoff.md — 5-component self-contained handoff report
