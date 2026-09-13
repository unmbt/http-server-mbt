# Handoff Report — Milestone 5 Implementation: CLI 完整性、生命周期与架构规范

- **Agent**: Worker M5 (`teamwork_preview_worker`)
- **Working Directory**: `E:\project\moonbit\unmbt\http-server-mbt\.agents\worker_m5`
- **Role**: Implementer (Milestone 5)
- **Local Git Commit**: `178bb577a0e8e1c1f57e5c70044c54ce8ec412f0` (`178bb57`) (STRICTLY NOT PUSHED)
- **Status**: Complete & Verified

---

## 1. Observation

1. **Existing CLI Deficiencies in `cmd/http-server-mbt/main.mbt`**:
   - `main.mbt` previously declared only 4 options (`help`, `version`, `port`, `base-url`, `root`), omitting `--base-dir`, `--spa`, `--try-files`, `--autoIndex`/`--no-autoIndex`, `--showDir`/`--no-showDir`, `--cache`/`-c`, `--cors`, `--auth`/`-a`, `--log-ip`/`-l`, `--silent`/`-s`.
   - On error, `main.mbt` previously wrote error messages to stdout and returned normally with exit code 0.
   - Root directory existence was never checked before starting the listener; non-existent roots did not fail pre-flight.
   - The action callback in `with_server_at` printed a message and returned immediately, causing the server process to terminate instantaneously.
2. **Configuration & Core Model in `core/config.mbt`**:
   - `core.Config` lacked `log_ip: Bool` and `silent: Bool`.
   - `core.validate_config` lacked validation for negative cache seconds (`cache_seconds < -1`).
   - `Config::validate` instance method was missing.
3. **Server Lifecycle in `server/server.mbt`**:
   - `Server` lacked an active request counter `active_requests : Ref[Int]`.
   - `Server::stop_and_drain` was not implemented.
   - In-flight requests were not tracked during connection keep-alive.
4. **Implementation Artifacts**:
   - Created `cmd/http-server-mbt/cli.mbt`: Declarative parser with `@argparse`, pure `parse_cli(args : ArrayView[String]) -> Result[CliAction, String]`, supporting all required flags/options, negatable `--no-*` flags, float port truncation (e.g. `9090.86` -> `9090` per C033/AD-04), cache parsing (numeric, `-1`, `max-age=N`), and basic auth credentials.
   - Created `cmd/http-server-mbt/cli_wbtest.mbt`: 16 comprehensive whitebox unit tests covering all flags, aliases, mutual exclusions, error branches, and default resolutions.
   - Updated `cmd/http-server-mbt/main.mbt`: Pre-flight filesystem directory verification (`@fs.exists` & `@fs.kind(root) == Directory`), stderr error writing via `@stdio.stderr.write`, process termination via C `exit(1)`, and server suspension via `@async.sleep(2147483647)` until cancellation.
   - Updated `cmd/http-server-mbt/moon.pkg`: Added `"moonbitlang/async/stdio"` and `"moonbitlang/async/fs"`.
   - Updated `core/config.mbt`: Added `log_ip: Bool` (default `false`), `silent: Bool` (default `false`), `Config::validate`, `cache_seconds < -1` validation, and `parse_auth_credential` helper.
   - Updated `server/server.mbt`: Added `active_requests: Ref[Int]`, `Server::stop_and_drain(timeout_ms? : Int = 5000)`, `active_request_count`, and updated `with_server_at` to use `stop_and_drain`.
5. **Verification Evidence**:
   - `moon check --target native`: 0 errors, 0 warnings.
   - `moon test cmd/http-server-mbt --target native`: 16 passed, 0 failed.
   - `moon test server --target native`: 17 passed, 0 failed.
   - `moon test --target native`: 99 passed, 0 failed (all 83 existing tests + 16 new CLI tests 100% pass).
   - `moon build cmd/http-server-mbt --target native --release`: Clean compilation, produced executable.
   - Release CLI smoke tests:
     - `-h` -> Usage help displayed, exit code 0.
     - `-v` -> Version `0.1.5` displayed, exit code 0.
     - `--invalid-flag` -> Error message to stderr, exit code 1.
     - `-p 99999` -> Error message to stderr, exit code 1.
     - `./non_existent_folder_xyz` -> Error message to stderr, exit code 1.
     - `--spa --try-files index.html` -> Mutual exclusion error, exit code 1.
     - Background server launch on port 18080 -> HTTP GET `/hello.txt` returned 200 OK with `hello moonbit\n`, followed by clean process shutdown.

---

## 2. Logic Chain

1. **Architecture Decoupling**:
   Per D-02 and D-14, `core` is pure and portable across Native and wasm-gc targets and must not depend on CLI, `@argparse`, or `@fs`. Therefore, all CLI argument parsing is encapsulated in `cmd/http-server-mbt/cli.mbt`, while `core/config.mbt` manages pure semantic model and syntactic validation.
2. **Pre-flight Interception**:
   To strictly satisfy R2, any invalid configuration (port out of range, malformed auth, mutual exclusion between `--spa` and `--try-files`, or missing root directory) is intercepted before `@socket.TcpServer` or `@server.with_server_at` is invoked. Errors are routed to `@stdio.stderr.write` and terminated via C runtime `exit(1)`, guaranteeing that no socket is bound and no unhandled stack trace leaks to users.
3. **In-Flight Request Draining**:
   In `server/server.mbt`, `active_requests.val` tracks in-flight request processing (incremented upon receiving a valid request from `read_request()`, decremented once `send_response` finishes). When `server.stop_and_drain()` is invoked:
   - `self.stopped` is set to `true`, preventing keep-alive loops from accepting further requests.
   - Active in-flight requests are granted up to `timeout_ms` (default 5000ms) to drain inside `@async.protect_from_cancel`.
   - `self.task` is cancelled, completing server cleanup without leaking sockets or handles.
4. **Zero Compiler Warnings & Format Compliance**:
   All new code was formatted with `moon fmt`, `.mbti` interfaces regenerated via `moon info --target native`, and `moon check --target native` verified to produce exactly 0 errors and 0 warnings.

---

## 3. Caveats

1. **Directory Existence Pre-flight**:
   Checking directory existence requires calling `@fs.exists(path)` followed by `@fs.kind(path) == Directory`. Calling `@fs.kind` directly on a non-existent path raises `OSError(ENOENT)`, so `main.mbt` guards the call with `let is_dir = if exists { @fs.kind(path) == Directory } else { false }`.
2. **Local Commit Constraint**:
   Per MANDATORY GIT WORKFLOW GATE, local commit `178bb57` was created using `git add -A` and `git commit -m "feat: 实现 Milestone 5 完整 CLI 参数与生命周期"`. This commit is strictly local and has NOT been pushed to remote.

---

## 4. Conclusion

Milestone 5 implementation is complete, meeting all requirements of T-011, D-01, D-02, D-05, and `ORIGINAL_REQUEST.md`.
All 99 tests pass, compiler output is completely free of warnings and errors, release CLI binary passes all smoke tests and lifecycle verification, and the local git commit checkpoint has been established.

---

## 5. Verification Method

To independently reproduce and verify all results:

```powershell
# 1. Typecheck and compiler warnings verification (must be 0 errors, 0 warnings):
moon check --target native

# 2. Full test suite verification (must pass 99/99 tests):
moon test --target native

# 3. CLI unit tests verification:
moon test cmd/http-server-mbt --target native

# 4. Server tests verification:
moon test server --target native

# 5. Interface and formatting checks:
moon info --target native
moon fmt

# 6. Build release binary:
moon build cmd/http-server-mbt --target native --release

# 7. Smoke test CLI flags:
.\_build\native\release\build\cmd\http-server-mbt\http-server-mbt.exe -h
.\_build\native\release\build\cmd\http-server-mbt\http-server-mbt.exe -v
.\_build\native\release\build\cmd\http-server-mbt\http-server-mbt.exe --invalid-flag 2>&1
.\_build\native\release\build\cmd\http-server-mbt\http-server-mbt.exe -p 99999 2>&1
.\_build\native\release\build\cmd\http-server-mbt\http-server-mbt.exe ./non_existent_folder_xyz 2>&1

# 8. Git log verification:
git status
git log -1
```
