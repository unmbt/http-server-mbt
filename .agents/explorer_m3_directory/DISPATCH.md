# Task Assignment: M3 Directory Index & HTML Listing Strategy

## Context
You are explorer_m3_directory (teamwork_preview_explorer).
Working Directory: D:\project\moonbit\http-server-mbt\.agents\explorer_m3_directory
Project Root: D:\project\moonbit\http-server-mbt
Original User Request: D:\project\moonbit\http-server-mbt\.agents\ORIGINAL_REQUEST.md
Scope Document: D:\project\moonbit\http-server-mbt\.agents\orchestrator_1\PROJECT.md
Design References: `docs/design.md` (D-03, D-06), `docs/tasks.md` (T-009, T-018)

## Objectives
Design the integration and implementation strategy in `engine.mbt` for:
1. Directory Index resolution:
   - When a request maps to a directory, check for `index.html` (or configured index).
   - If directory path lacks trailing slash (`/subdir`), issue 302 Found redirect to `/subdir/` preserving query parameters and BaseURL prefix.
2. HTML Directory Listing Generator:
   - Scan directory entries using `@fs`.
   - $O(N)$ companion matching: group companion `.gz`/`.br` files using a set so they are not shown as duplicate clutter.
   - $O(N \log N)$ stable sorting: directories first or alphabetical order.
   - HTML entity escaping: file names like `<dir>` safely rendered as `&#x3C;dir&#x3E;`.
   - URL encoding for hrefs: space -> `%20`, `+` -> `%2B`.
   - Query string inheritance: append existing query (`?sort=name&view=list`), escaping `&` as `&#x26;`.
   - `dirOverrides404`: when directory lacks `index.html` and `show_dir=true`, if `dirOverrides404=false` and a custom `404.html` exists in root, serve `404.html`; if `dirOverrides404=true`, display directory listing.
3. Deliver `strategy.md` and `handoff.md`.

## 2026-09-11T07:51:06Z
You are explorer_m3_directory. Working directory: D:\project\moonbit\http-server-mbt\.agents\explorer_m3_directory. Read D:\project\moonbit\http-server-mbt\.agents\ORIGINAL_REQUEST.md, AGENTS.md, PROJECT.md, and your DISPATCH.md. Design exact strategy for directory index lookup, trailing slash 302 redirects, and HTML directory listing (O(N) companion matching, O(N log N) sorting, HTML/URL escaping, dirOverrides404) in engine.mbt. Write strategy.md and handoff.md, then message parent.
