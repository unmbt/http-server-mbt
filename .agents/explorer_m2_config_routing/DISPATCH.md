# Task Assignment: M2 Config & Routing Contracts Strategy

## Context
You are explorer_m2_config_routing (teamwork_preview_explorer).
Working Directory: D:\project\moonbit\http-server-mbt\.agents\explorer_m2_config_routing
Project Root: D:\project\moonbit\http-server-mbt
Original User Request: D:\project\moonbit\http-server-mbt\.agents\ORIGINAL_REQUEST.md
Scope Document: D:\project\moonbit\http-server-mbt\.agents\orchestrator_1\PROJECT.md
Design References: `docs/design.md` (D-01, D-04), `docs/tasks.md` (T-003, T-019)

## Objectives
Design the architecture and exact implementation strategy in `core/` for:
1. Configuration model expansion:
   - Review and expand `core.Config` to hold full settings:
     `root`, `port`, `address`, `base_url`, `default_ext`, `gzip`, `brotli`, `auto_index`, `show_dir`, `show_dotfiles`, `cache_seconds`, `cors`, `coop`, `pna`, `basic_auth: Option[(String, String)]`, `host_whitelist: Array[String]`, `spa: Bool`, `try_files: Option[String]`, `proxy: Option[String]`, `custom_headers: Map[String, String]`, etc.
2. BaseURL and BaseDir route mounting (D-04):
   - Strict normalization: `app`, `/app`, `/app/` -> `/app`. Root is `/`.
   - Component boundary matching: `/app` matches `/app` and `/app/page`, but rejects `/application`.
   - Strip prefix for internal file lookup. Return 403 on requests outside mount prefix.
3. SPA and try-files configuration validation & mutual exclusion (D-04):
   - Mutual exclusion rules (must fail before listening):
     - `--spa` and `--try-files <file>` cannot both be set.
     - `--spa` / `--try-files` and proxy (`--proxy`) cannot both be set.
   - `try_files` path validation (must not be empty, must not escape root).
4. Write detailed strategy in `strategy.md` and `handoff.md`. Do NOT edit source code files.

## 2026-09-11T07:19:04Z
You are explorer_m2_config_routing. Working directory: D:\project\moonbit\http-server-mbt\.agents\explorer_m2_config_routing. Read D:\project\moonbit\http-server-mbt\.agents\ORIGINAL_REQUEST.md, AGENTS.md, PROJECT.md, and your DISPATCH.md. Design exact architecture and implementation strategy in core/ for Config model expansion, BaseURL route mounting (boundary matching), and SPA/try-files mutual exclusion validation. Write strategy.md and handoff.md, then message parent.
