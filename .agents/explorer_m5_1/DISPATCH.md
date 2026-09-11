## 2026-09-11T15:26:04Z

<USER_REQUEST>
You are Explorer 1 for Milestone 5 (CLI 完整性、生命周期与架构规范).
Your working directory is: `E:\project\moonbit\unmbt\http-server-mbt\.agents\explorer_m5_1`.
Your identity: teamwork_preview_explorer (CLI Parser & Config Architecture Investigator).

MANDATORY FIRST STEP:
Read `E:\project\moonbit\unmbt\http-server-mbt\ORIGINAL_REQUEST.md` (especially Milestone 5 Follow-up).
Also read:
- `E:\project\moonbit\unmbt\http-server-mbt\.agents\orchestrator_m5\plan.md`
- `E:\project\moonbit\unmbt\http-server-mbt\docs\proposal.md`
- `E:\project\moonbit\unmbt\http-server-mbt\docs\design.md`
- `E:\project\moonbit\unmbt\http-server-mbt\docs\tasks.md` (T-011)

Investigation Focus:
1. Deeply examine `cmd/http-server-mbt/main.mbt` and `cmd/http-server-mbt/moon.pkg`. What does the CLI currently do? How are arguments currently parsed?
2. Deeply examine `core/config.mbt`, `core/routing.mbt`, `core/security.mbt`. What fields exist in `Config`? What fields need to be added or updated to support all required CLI options:
   - `--port` / `-p` (int, default 8080)
   - Positional `root` directory (default ".")
   - `--base-url` (string, default "/")
   - `--base-dir` (string, default "")
   - `--spa` (bool, fallback to root index.html)
   - `--try-files <file>` (string, fallback to specified file)
   - `--autoIndex` / `-i` / `--no-autoIndex` (bool, default true)
   - `--showDir` / `-d` / `--no-showDir` (bool, default true)
   - `--cache` / `-c <sec>` (supports numeric seconds and max-age format like `max-age=3600`)
   - `--cors` (bool, enables CORS headers)
   - `--auth` / `-a <username:password>` (Basic Auth credential)
   - `--log-ip` / `-l` (bool)
   - `--silent` / `-s` (bool)
   - `--help` / `-h` (print help and exit 0)
   - `--version` / `-v` (print version and exit 0)
3. Check how command-line arguments are retrieved in MoonBit Native (`@sys.get_cli_args()` or similar).
4. Propose a clean, robust argument parser design for `cmd/http-server-mbt/` (supporting `--flag`, `--flag value`, `--flag=value`, `-f value`, boolean negation `--no-flag`, positional arguments, unknown argument detection).
5. Check if a dedicated CLI parser module or testable helper should be in `cmd/http-server-mbt/` or `core/`.

Output requirements:
Write your complete findings and recommendations to `E:\project\moonbit\unmbt\http-server-mbt\.agents\explorer_m5_1\handoff.md`.
Update `E:\project\moonbit\unmbt\http-server-mbt\.agents\explorer_m5_1\progress.md` as you work.
When finished, send a message to orchestrator with a summary and path to your handoff.md.
</USER_REQUEST>
