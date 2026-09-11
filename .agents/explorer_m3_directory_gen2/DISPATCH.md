# Dispatch: explorer_m3_directory_gen2

## Identity
- Archetype: teamwork_preview_explorer
- Role: Directory & HTML View Analyst
- Working Directory: D:\project\moonbit\http-server-mbt\.agents\explorer_m3_directory_gen2
- Parent: orchestrator_gen2

## Task & Scope
Investigate and design implementation strategy for Directory Index and HTML Directory Listing in Milestone 3:
1. Directory Redirect (302 Found):
   - When requested path is a directory but lacks trailing slash (e.g., `/docs`), issue 302 Found redirect to `/docs/` (preserving query parameters).
2. Directory Index lookup:
   - Check for `index.html` (or configured index file) in the directory. If present, serve it directly with standard file handling.
3. HTML Directory Listing (`show_dir = true`):
   - When no index file is present and `show_dir` is enabled, generate a clean, modern HTML view of directory contents.
   - Companion files matching: $O(N)$ identification of `.br` / `.gz` companion files (e.g. `bundle.js.br` alongside `bundle.js`) to display badge or group them, rather than cluttering the directory view.
   - Natural / Case-insensitive sorting: $O(N \log N)$ sorting with directories first, followed by regular files.
   - Strict HTML & URL escaping: encode special characters (`&`, `<`, `>`, `"`, `'`) in display names, and URL-encode href paths.
   - Display size (human-readable B / KB / MB) and last modified timestamp.
   - `show_dotfiles`: hide hidden files starting with `.` unless `show_dotfiles: true`.
4. When `show_dir = false` and no index file exists: return 404 Not Found.

## Relevant Files to Read
- D:\project\moonbit\http-server-mbt\.agents\ORIGINAL_REQUEST.md (MANDATORY)
- D:\project\moonbit\http-server-mbt\.agents\orchestrator_gen2\PROJECT.md
- D:\project\moonbit\http-server-mbt\engine.mbt
- D:\project\moonbit\http-server-mbt\core\routing.mbt
- D:\project\moonbit\http-server-mbt\docs\design.md (D-03, D-06)
- Local reference: `http-server/` directory if needed.

## Deliverables
Write your findings and actionable implementation plan into `strategy.md` and `handoff.md` in your working directory.
Report back via `send_message`.

## 2026-09-11T08:03:38Z
You are explorer_m3_directory_gen2.
Your working directory is D:\project\moonbit\http-server-mbt\.agents\explorer_m3_directory_gen2.
Read D:\project\moonbit\http-server-mbt\.agents\explorer_m3_directory_gen2\DISPATCH.md and D:\project\moonbit\http-server-mbt\.agents\ORIGINAL_REQUEST.md.
Investigate directory handling: 302 Found trailing slash redirect, index.html resolution, and HTML directory listing (companion matching in O(N), case-insensitive sorting in O(N log N), HTML/URL escaping, dotfile filtering).
Write your analysis and implementation strategy to strategy.md and handoff.md in your working directory.
When done, report back using send_message.
