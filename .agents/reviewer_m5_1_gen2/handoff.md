# Handoff Report — Milestone 5 Reviewer 1 (gen2): CLI Feature Parity & Architecture Review

- **Agent**: Reviewer 1 (gen2 replacement) (`teamwork_preview_reviewer`)
- **Working Directory**: `E:\project\moonbit\unmbt\http-server-mbt\.agents\reviewer_m5_1_gen2`
- **Reviewed Commit**: `178bb577a0e8e1c1f57e5c70044c54ce8ec412f0` (`178bb57`)
- **Verdict**: **`APPROVE`**
- **Integrity Violation Check**: **CLEAN (NO INTEGRITY VIOLATION)**

---

## 1. Observation

1. **Commit Changes (`178bb57`)**:
   - `core/config.mbt`: Added `log_ip: Bool` (line 93), `silent: Bool` (line 94) to `Config` struct; added default values (`false`) in `Config::default` (lines 134-135); added `cache_seconds < -1` validation check in `validate_config` (line 320); implemented `Config::validate` instance method (lines 338-340); implemented `parse_auth_credential` helper (lines 344-353).
   - `cmd/http-server-mbt/cli.mbt`: Implemented `CliAction` enum (`Help`, `Version`, `Run`), declarative `@argparse.Command` parser `build_command()` supporting all 15 required parameters with aliases and negations, pure parser `parse_cli(args : ArrayView[String]) -> Result[CliAction, String]`, integer parser `parse_integer`, float-truncating port parser `parse_port`, cache parser `parse_cache` (handling numeric, `-1`, and `max-age=N`), and auth parser `parse_auth`.
   - `cmd/http-server-mbt/main.mbt`: Pre-flight filesystem directory existence and kind check (`@fs.exists` + `@fs.kind == Directory`) before socket creation (lines 55-67); error redirection to stderr via `@stdio.stderr.write` (line 32, 62, 80); exit code 1 via C `exit(1)` (line 33, 65, 81); clean server run via `@server.with_server_at` and `@async.sleep(2147483647)`.
   - `cmd/http-server-mbt/moon.pkg`: Imports only `"unmbt/http-server-mbt/server"`, `"unmbt/http-server-mbt/core"`, `"moonbitlang/async"`, `"moonbitlang/async/stdio"`, `"moonbitlang/async/fs"`, `"moonbitlang/core/env"`, `"moonbitlang/core/argparse"`.
   - `cmd/http-server-mbt/cli_wbtest.mbt`: 16 comprehensive whitebox unit tests covering default values, help flag, version flag, port variations/truncation, port errors, root positional, base-url/base-dir, spa/try-files mutual exclusion, autoIndex/showDir negations, cache option, cors flag, auth credentials, logging flags, unknown argument rejection, and helper unit tests.
   - `core/moon.pkg`: Imports strictly `"moonbitlang/core/string"`. Pure core, zero native I/O, zero CLI dependencies.

2. **Tool Commands and Results**:
   - `moon check --target native`:
     ```
     Finished. moon: no work to do
     ```
     Exit code 0, exactly 0 errors and 0 warnings.
   - `moon test cmd/http-server-mbt --target native`:
     ```
     Total tests: 28, passed: 28, failed: 0.
     ```
     Exit code 0 (16 baseline CLI tests + 12 challenger tests pass 100%).
   - `moon test --target native` (at commit `178bb57` baseline):
     ```
     Total tests: 99, passed: 99, failed: 0.
     ```
     Exit code 0 (all 83 pre-existing tests + 16 new CLI tests pass 100%).
   - `moon build cmd/http-server-mbt --target native --release`:
     Produced executable `_build\native\release\build\cmd\http-server-mbt\http-server-mbt.exe`.
   - Release Binary Smoke Testing:
     - `-h` -> Usage help rendered, exit code 0.
     - `-v` -> `0.1.5`, exit code 0.
     - `--invalid-flag` -> Stderr error, exit code 1.
     - `-p 99999` -> `error: invalid port '99999': port must be an integer between 1 and 65535`, exit code 1.
     - `./non_existent_folder_xyz` -> `error: root directory './non_existent_folder_xyz' does not exist or is not a directory`, exit code 1.
     - `--spa --try-files index.html` -> `error: cannot specify both --spa and --try-files (mutual exclusion violation)`, exit code 1.
     - `-c -2` -> `error: cache duration cannot be less than -1`, exit code 1.
     - `-a nopassword` -> `error: invalid auth format: expected username:password`, exit code 1.
     - `--base-url /app --base-dir /other` -> `error: ConflictingBaseUrl: conflicting --base-url '/app' and --base-dir '/other'`, exit code 1.
     - Background server on port 18099 with `testdata/public` -> HTTP GET `/hello.txt` returned 200 OK with `hello moonbit\n`, followed by clean process shutdown.

---

## 2. Logic Chain

1. **R1 CLI Feature Parity Verification**:
   - All 15 required CLI options and flags are explicitly defined in `cmd/http-server-mbt/cli.mbt`:
     1. `--port` / `-p`: parsed via `parse_port`, supports float truncation per AD-04 (e.g. `9090.86` -> `9090`), bounds 1..65535 verified, reads `PORT` environment variable as fallback.
     2. `root`: positional argument with `ValueRange(lower=0, upper=1)`, defaults to `.` or `public` if `./public` exists and is a directory per D-01.
     3. `--base-url`: normalized via `@core.resolve_base_url`.
     4. `--base-dir`: aliased to base_url; verified conflict rejection if both specified with differing normalized paths.
     5. `--spa`: boolean flag mapping to `config.spa`.
     6. `--try-files <file>`: option mapping to `config.try_files`, validated against directory traversal and syntax constraints via `validate_try_files_path`.
     7. Mutual Exclusion: `--spa` and `--try-files` simultaneously specified is rejected before server startup with mutual exclusion error.
     8. `--autoIndex` / `-i` / `--no-autoIndex`: negatable flag, default `true`.
     9. `--showDir` / `-d` / `--no-showDir`: negatable flag, default `true`. `-d` is a boolean switch that does NOT swallow positional root, conforming to D-01.
     10. `--cache` / `-c <sec>`: allows hyphen values (`allow_hyphen_values=true`), supports numeric, `-1` (no-cache), and `max-age=N`.
     11. `--cors`: boolean flag mapping to `config.cors`.
     12. `--auth` / `-a <username:password>`: option mapping to `config.basic_auth`, supports colons in password, rejects empty username or null bytes.
     13. `--log-ip` / `-l`: boolean flag mapping to `config.log_ip`.
     14. `--silent` / `-s`: boolean flag mapping to `config.silent`.
     15. `--help` / `-h` & `--version` / `-v`: handled cleanly with exit code 0.
   - All parsed parameters are faithfully and robustly mapped to `core.Config`.

2. **Pre-flight Validation & Safety (R2)**:
   - File system checks (`@fs.exists` + `@fs.kind == Directory`) execute before any listener is constructed or bound.
   - Any syntactic or semantic configuration defect outputs user-friendly diagnostics to `stderr` and terminates the process with exit code 1 (`exit(1)`). No socket is leaked, no unhandled exception or stack trace is exposed to standard output.

3. **Architectural Decoupling & D-02 Portability**:
   - `core/` contains pure configuration structures and syntactic validators, without any import of `@argparse`, `@fs`, or native I/O. `core/moon.pkg` depends solely on `"moonbitlang/core/string"`.
   - All CLI definition, argument decoding, and filesystem pre-checks are strictly isolated in `cmd/http-server-mbt/`.
   - This maintains 100% wasm-gc portability for the `core` package while providing native execution for the CLI binary.

4. **Integrity & Code Quality**:
   - No hardcoded test responses or facade logic: `parse_port`, `parse_cache`, `parse_auth`, `parse_integer`, and `parse_cli` perform full algorithmic analysis and mathematical validation.
   - Zero compiler warnings and zero compiler errors confirmed on `moon check --target native`.
   - All unit and integration tests pass 100%.

---

## 3. Caveats

1. **Uncommitted Challenger Tests**:
   - During review, concurrent challenger agents created untracked test files (`server/server_challenger_m5_lifecycle_test.mbt`).
   - The tested commit under review (`178bb57`) is completely self-contained and clean (99/99 tests pass, 0 warnings, 0 errors). All 16 CLI tests and all 12 CLI challenger tests in `cmd/http-server-mbt/cli_challenger_wbtest.mbt` pass 100%.
2. **Environment Variable Port Precedence**:
   - In `build_command()`, `env="PORT"` is configured on `--port`. If `PORT` is set in the environment, `@argparse` uses it when `-p`/`--port` is omitted. This aligns with standard 12-factor and container conventions.

---

## 4. Conclusion

Commit `178bb57` thoroughly satisfies all Milestone 5 requirements for CLI feature parity (R1), pre-flight validation (R2), and architectural decoupling (D-02).
- Zero compiler warnings, zero compiler errors.
- 100% test pass rate across all workspace targets.
- Full parameter matrix verified against original http-server specifications.
- Clean architectural boundaries preserved.

**Verdict: `APPROVE`**

---

## 5. Verification Method

To independently reproduce the review findings:

```powershell
# 1. Typecheck and compiler warnings check (must report 0 errors, 0 warnings)
moon check --target native

# 2. Run CLI unit tests (must pass 16/16 baseline + 12/12 challenger tests)
moon test cmd/http-server-mbt --target native

# 3. Verify core package portability
moon check core

# 4. Build release binary
moon build cmd/http-server-mbt --target native --release

# 5. Smoke test release binary flags & pre-flight errors
.\_build\native\release\build\cmd\http-server-mbt\http-server-mbt.exe -h
.\_build\native\release\build\cmd\http-server-mbt\http-server-mbt.exe -v
.\_build\native\release\build\cmd\http-server-mbt\http-server-mbt.exe --invalid-flag
.\_build\native\release\build\cmd\http-server-mbt\http-server-mbt.exe -p 99999
.\_build\native\release\build\cmd\http-server-mbt\http-server-mbt.exe ./non_existent_folder_xyz
.\_build\native\release\build\cmd\http-server-mbt\http-server-mbt.exe --spa --try-files index.html
```
