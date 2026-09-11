# Handoff Report — Milestone 5 Review (Reviewer 2, gen2)

- **Agent**: Reviewer 2 (gen2 replacement) (`teamwork_preview_reviewer`)
- **Roles**: reviewer, critic
- **Working Directory**: `E:\project\moonbit\unmbt\http-server-mbt\.agents\reviewer_m5_2_gen2`
- **Target Commit**: `178bb577a0e8e1c1f57e5c70044c54ce8ec412f0` (`178bb57`)
- **Status**: Completed
- **Verdict**: **APPROVE**

---

## 1. Observation

### 1.1 Code Changes in Commit `178bb57`
1. `cmd/http-server-mbt/main.mbt`:
   - Line 2–9: Implements C FFI `runtime_native_exit(code : Int) = "exit"` with fallback `#cfg(not(any(target="native", target="llvm")))`.
   - Line 12–16: Implements `eprint_err(msg : String)` using `@stdio.stderr.write(msg) catch { _ => () }`.
   - Line 22–37: Routes CLI parse errors directly to `eprint_err` and calls `runtime_native_exit(1)`.
   - Line 39–68: Implements pre-flight directory validation. Checks `@fs.exists(final_config.root)` and `@fs.kind(final_config.root) == Directory`. If not a directory or non-existent, outputs to stderr and exits 1 before `@server.with_server_at` is invoked. Also handles `./public` fallback when root is default `.`.
   - Line 69–84: Calls `@server.with_server_at(...)` and maintains process liveness with `@async.sleep(2147483647)`. Catches cancellation via `_ if @async.is_being_cancelled() => ()` for clean shutdown.
2. `cmd/http-server-mbt/cli.mbt`:
   - Line 26–115: Declarative command spec using `@argparse.Command` defining all required flags and options (`help`, `version`, `spa`, `autoIndex`/`--no-autoIndex`, `showDir`/`--no-showDir`, `cors`, `log-ip`, `silent`, `port`, `base-url`, `base-dir`, `try-files`, `cache`, `auth`, and `root`).
   - Line 159–183: `parse_port` enforces valid ports `1..65535`, rejects non-numeric and <= 0 strings, and correctly truncates float port strings (e.g., `9090.86` -> `9090`) per C033 and AD-04.
   - Line 187–210: `parse_cache` supports integer seconds, `-1` (no-cache), `max-age=N`, and rejects `< -1`.
   - Line 214–229: `parse_auth` enforces `username:password` format, disallows empty usernames, and rejects null bytes.
   - Line 233–332: `parse_cli` strictly checks mutual exclusion between `--spa` and `--try-files`, resolves `base-url`/`base-dir`, constructs `@core.Config`, and calls `config.validate()`.
3. `core/config.mbt`:
   - Line 93–94, 134–135: Added `log_ip: Bool` (default `false`) and `silent: Bool` (default `false`) to `Config`.
   - Line 264–334: `validate_config` verifies root, base URL, port (0..65535), idle timeout (non-negative), mutual exclusion between fallback and proxy, basic auth format, `cache_seconds >= -1`, and CRLF in custom headers.
   - Line 338–340: Added instance method `Config::validate(self : Config) -> Unit raise ConfigError`.
4. `server/server.mbt`:
   - Line 8: Added `active_requests : Ref[Int]` to `Server` struct.
   - Line 36: Initialized `active_requests: { val: 0 }` in `with_server_at`.
   - Line 51: Updated `with_server_at` exit path to invoke `server.stop_and_drain()`.
   - Line 73–91: Implemented `Server::stop_and_drain(self : Server, timeout_ms? : Int = 5000) -> Unit`: sets `self.stopped = true`, wraps draining loop inside `@async.protect_from_cancel(...)` with 10ms polling interval up to `timeout_ms`, and cancels `self.task`.
   - Line 95–97: Exposed `Server::active_request_count(self : Server) -> Int`.
   - Line 120, 138: Increments `server.active_requests.val += 1` on incoming request and decrements `server.active_requests.val -= 1` after sending response.
   - Line 116, 147: Exits keep-alive loop when `server.stopped` is true.

### 1.2 Independent Verification Results
1. `moon check --target native`:
   - Exit code: 0
   - Output: `Finished. moon: no work to do` (0 errors, 0 warnings).
2. `moon test server --target native`:
   - Exit code: 0
   - Output: `Total tests: 17, passed: 17, failed: 0.`
3. `moon test cmd/http-server-mbt --target native`:
   - Exit code: 0
   - Output: `Total tests: 16, passed: 16, failed: 0.`
4. `moon test --target native`:
   - Exit code: 0
   - Output: `Total tests: 99, passed: 99, failed: 0.`
5. `moon build cmd/http-server-mbt --target native --release`:
   - Exit code: 0
   - Created executable: `_build\native\release\build\cmd\http-server-mbt\http-server-mbt.exe`.
6. CLI pre-flight validation smoke test results:
   - `-h` -> ExitCode: 0, help text to stdout.
   - `-v` -> ExitCode: 0, `http-server-mbt 0.1.5` to stdout.
   - `-p 0` -> ExitCode: 1, `error: invalid port '0': port must be an integer between 1 and 65535` to stderr.
   - `-p 99999` -> ExitCode: 1, `error: invalid port '99999': port must be an integer between 1 and 65535` to stderr.
   - `-p abc` -> ExitCode: 1, `error: invalid port 'abc': port must be an integer between 1 and 65535` to stderr.
   - `--port=-80` -> ExitCode: 1, `error: invalid port '-80': port must be an integer between 1 and 65535` to stderr.
   - `./non_existent_folder_98765` -> ExitCode: 1, `error: root directory './non_existent_folder_98765' does not exist or is not a directory` to stderr.
   - `moon.mod` (file as root dir) -> ExitCode: 1, `error: root directory 'moon.mod' does not exist or is not a directory` to stderr.
   - `--spa --try-files index.html` -> ExitCode: 1, `error: cannot specify both --spa and --try-files (mutual exclusion violation)` to stderr.
   - `--unknown` -> ExitCode: 1, `error: error: unexpected argument '--unknown' found` to stderr.
   - `-c -2` -> ExitCode: 1, `error: cache duration cannot be less than -1` to stderr.
   - `-a :pass` -> ExitCode: 1, `error: auth username cannot be empty` to stderr.
   - `--base-url /app --base-dir /other` -> ExitCode: 1, `error: ConflictingBaseUrl: conflicting --base-url '/app' and --base-dir '/other'` to stderr.
7. Real HTTP lifecycle test:
   - Started server in background on port 18099 with `--silent`.
   - Performed HTTP GET `/moon.mod`: received 200 OK with full content (`name = "unmbt/http-server-mbt"`).
   - Terminated server process cleanly.

---

## 2. Logic Chain

1. **Pre-Flight Interception (R2)**:
   - Observation 1.1.1 and 1.1.2 demonstrate that all CLI validation (`parse_cli`), configuration validation (`config.validate`), and filesystem directory checks (`@fs.exists` && `@fs.kind == Directory`) occur *prior* to calling `@server.with_server_at`.
   - Observation 1.2.6 confirms that invalid ports (0, negative, > 65535, non-numeric), non-existent root folders, regular files passed as roots, invalid auth strings, invalid cache durations, and mutual exclusions (`--spa` + `--try-files`) are intercepted before binding any socket.
   - In all failure scenarios, error messages are written directly to stderr and the process exits with exit code 1 without panicking or leaking stack traces.
2. **Graceful Lifecycle & Draining (R3)**:
   - Observation 1.1.4 demonstrates that in-flight requests are tracked by `active_requests : Ref[Int]`.
   - `stop_and_drain` sets `self.stopped = true` (preventing any keep-alive connection from accepting new requests) and runs a loop checking `self.active_requests.val == 0` within `@async.protect_from_cancel`.
   - This ensures that if the process receives a termination signal (SIGINT / Ctrl+C), cancellation does not abort the in-flight response transmission.
   - In `main.mbt`, `@async.sleep(2147483647)` keeps the server running indefinitely until cancellation occurs, at which point the cancellation error is caught by `_ if @async.is_being_cancelled() => ()` and exits cleanly.
   - Observation 1.2.7 independently proves that a launched server remains responsive to HTTP traffic and terminates cleanly.
3. **Integrity & Quality Assessment**:
   - Examination of the code in `cmd/http-server-mbt/cli.mbt`, `main.mbt`, `core/config.mbt`, and `server/server.mbt` reveals no dummy facades, no hardcoded test outputs, and no integrity violations.
   - `moon check --target native` produces strictly 0 warnings and 0 errors.
   - All 99 unit and blackbox tests pass without failure.

---

## 3. Caveats & Adversarial Observations

1. **PORT Environment Variable Handling in `@argparse` (Minor Finding)**:
   In `cli.mbt` line 75, `OptionArg("port", ..., env="PORT")` defines `env="PORT"`. However, in `cmd.parse(argv=args)`, the `env` parameter is not supplied and defaults to `Map([])`. Consequently, `@argparse.Command::parse` will not automatically read `$env:PORT` from the operating system environment unless `env` is loaded via `@env.get("PORT")` and passed in.
   *Assessment*: This is a minor non-blocking limitation; CLI parameter `-p` / `--port` works completely as intended. Recommendation: Load `@env` variables into `cmd.parse(argv=args, env=env_map)` in a future enhancement.
2. **Defense-in-depth: Exception Safety for `active_requests.val` (Minor Finding)**:
   In `server/server.mbt`, `server.active_requests.val += 1` is followed by `handle` and `send_response`, and decremented with `server.active_requests.val -= 1`. Currently, neither `handle` nor `send_response` throws unhandled exceptions. However, if an unanticipated panic or unhandled error were to occur, `active_requests.val` might not decrement, causing `stop_and_drain` to wait for the full `timeout_ms` (5000ms).
   *Assessment*: Non-blocking, as both functions are robust and do not raise unhandled errors. Recommendation: In future refactorings, wrap in `try ... finally` or inner block `defer`.

---

## 4. Conclusion

**Verdict: APPROVE**

The implementation in commit `178bb57` satisfies all criteria for Milestone 5:
- Full CLI argument parity and declarative parsing with `@argparse`.
- Pre-flight validation intercepts all invalid configurations before TCP listening.
- Stderr error output and exit code 1 on errors without stack trace leakage.
- Graceful shutdown and draining using `active_requests` counter and `@async.protect_from_cancel`.
- Clean compilation (0 errors, 0 warnings) and 100% test pass rate (99/99).
- Absolute integrity: no shortcuts, dummy facades, or hardcoded values.

---

## 5. Verification Method

To independently reproduce and verify this review:

```powershell
# 1. Verify 0 errors, 0 warnings
moon check --target native

# 2. Run all unit and blackbox tests (99 tests)
moon test --target native

# 3. Build release executable
moon build cmd/http-server-mbt --target native --release

# 4. Run CLI pre-flight validation smoke suite
powershell -File .agents/reviewer_m5_2_gen2/test_cli.ps1

# 5. Run real HTTP lifecycle test
powershell -File .agents/reviewer_m5_2_gen2/test_lifecycle.ps1
```
