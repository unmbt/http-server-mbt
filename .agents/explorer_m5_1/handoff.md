# Handoff Report: Milestone 5 CLI Parser & Config Architecture Investigation

**Agent**: Explorer 1 (`teamwork_preview_explorer`)  
**Working Directory**: `E:\project\moonbit\unmbt\http-server-mbt\.agents\explorer_m5_1`  
**Date**: 2026-09-11  
**Milestone**: Milestone 5 (CLI 完整性、生命周期与架构规范)  
**Task Reference**: T-011, D-01, D-02, D-04, D-08, D-14, D-16  

---

## 1. Observation

### 1.1 Current CLI Implementation (`cmd/http-server-mbt/main.mbt` & `moon.pkg`)
1. **Package dependencies** (`cmd/http-server-mbt/moon.pkg:1-10`):
   ```moonbit
   import {
     "unmbt/http-server-mbt/server",
     "unmbt/http-server-mbt/core",
     "moonbitlang/async",
     "moonbitlang/core/env",
     "moonbitlang/core/argparse",
   }
   pkgtype(kind: "executable")
   ```
2. **Current argument parsing in `cmd/http-server-mbt/main.mbt:30-59`**:
   - Only declares 4 arguments:
     - `flags=[FlagArg("help", short='h', long="help"), FlagArg("version", long="version")]` (missing `-v` for version)
     - `options=[OptionArg("port", short='p', long="port", env="PORT"), OptionArg("base-url", long="base-url")]`
     - `positionals=[PositionArg("root", num_args=@argparse.ValueRange(lower=0, upper=1))]`
   - **Missing options**:
     - `--base-dir` (alias for `--base-url`)
     - `--spa`
     - `--try-files <file>`
     - `--autoIndex` / `-i` / `--no-autoIndex`
     - `--showDir` / `-d` / `--no-showDir`
     - `--cache` / `-c <sec>` (including negative values like `-1` and `max-age=3600`)
     - `--cors`
     - `--auth` / `-a <username:password>`
     - `--log-ip` / `-l`
     - `--silent` / `-s`
     - `-v` (short for version)
3. **Critical Defect: Exit code 0 and stdout on errors (`main.mbt:67-101`)**:
   ```moonbit
   let matches = command.parse(...) catch {
     _ => {
       println("error: failed to parse arguments")
       println(command.render_help())
       return // Exits with status 0!
     }
   }
   ...
   match parse_port(value) {
     Some(port) => port
     None => {
       println("error: invalid port")
       return // Exits with status 0!
     }
   }
   ```
   **Live verification command & output**:
   Command: `.\_build\native\debug\build\cmd\http-server-mbt\http-server-mbt.exe --invalid-flag`
   Output: `error: failed to parse arguments\nUsage: ...`
   Exit code: `0` (should be non-zero!).
   Command: `.\_build\native\debug\build\cmd\http-server-mbt\http-server-mbt.exe -p 99999`
   Output: `error: invalid port`
   Exit code: `0` (should be non-zero!).
4. **Missing pre-flight validation**:
   - Root directory existence is never checked before listening; entering listening with a non-existent root directory does not fail pre-flight.
   - Base-url / base-dir conflicts are not validated.
   - Mutual exclusions (e.g. `--spa` vs `--try-files`) are not checked.

### 1.2 Configuration & Core Model (`core/config.mbt`, `core/routing.mbt`, `core/security.mbt`)
1. **Existing fields in `core.Config` (`core/config.mbt:21-70`)**:
   - Filesystem & Network: `root: String`, `port: Int`, `address: String`
   - Routing & Mounts: `base_url: String`, `default_ext: String?`, `spa: Bool`, `try_files: String?`
   - Compression: `gzip: Bool`, `brotli: Bool`, `force_content_encoding: Bool`
   - Directory Handling: `auto_index: Bool`, `show_dir: Bool`, `show_dotfiles: Bool`, `dir_overrides_404: Bool`
   - Caching & ETag: `cache_seconds: Int`, `cache_control: String?`, `weak_etags: Bool`, `weak_compare: Bool`
   - Security & Headers: `cors: Bool`, `cors_headers: String?`, `coop: Bool`, `coop_header: String?`, `pna: Bool`, `basic_auth: (String, String)?`, `host_whitelist: Array[String]`, `custom_headers: Map[String, String]`, `robots: Bool`
   - Proxy & Upstream: `proxy: String?`, `proxy_all: String?`, `proxy_options: Map[String, String]`
   - Lifecycle & Errors: `handle_error: Bool`, `idle_timeout_ms: Int`, `mime_types: Map[String, String]`
2. **Missing fields in `Config`**:
   - `log_ip : Bool` (default: `false`)
   - `silent : Bool` (default: `false`)
3. **Existing pre-flight validation in `core/config.mbt:237-303`**:
   - `validate_config(config : Config)` already validates:
     - `validate_root(config.root)`
     - `normalize_base_url(config.base_url)`
     - `0 <= config.port <= 65535` (note: CLI can require `1 <= config.port <= 65535`)
     - `validate_try_files_path` (rejects leading slash, `..`, null bytes, `$uri`, etc.)
     - Mutual exclusion of `spa` and `try_files` (`ConflictingRouting`)
     - Mutual exclusion of fallback and proxy (`ConflictingRouting`)
     - `basic_auth` (username cannot contain `:` or null bytes)
4. **Existing base-url and base-dir resolution in `core/routing.mbt:38-57`**:
   - `pub fn resolve_base_url(base_url : String?, base_dir : String?) -> String raise ConfigError` is already fully implemented! It normalizes both and raises `ConflictingBaseUrl` if both are specified with different values.

### 1.3 Command-Line Argument Retrieval in MoonBit Native
1. **Inspection of `E:\dev-env\moonbit\lib\core\env\env_native.mbt:16-23`**:
   ```moonbit
   extern "C" fn get_cli_args_ffi() -> FixedArray[@os_string.OsString] = "moonbit_rt_get_cli_args"
   fn get_cli_args_internal() -> Array[String] {
     [for t in get_cli_args_ffi() => t.to_string()]
   }
   ```
2. **Public API (`E:\dev-env\moonbit\lib\core\env\pkg.generated.mbti:5`)**:
   - `pub fn args() -> Array[String]` in package `"moonbitlang/core/env"`.
   - `args()[0]` is the program executable path, and `args()[1:]` are the command-line arguments.
   - This is the standard, canonical mechanism in MoonBit Native.

### 1.4 Capabilities of `moonbitlang/core/argparse`
Inspection of `E:\dev-env\moonbit\lib\core\argparse`:
1. **Inline `--flag=value` support**:
   - `parser.mbt:458`: `let (name, inline) = split_long(arg)`. Automatically splits `--port=8080`, `--cache=3600`, `--auth=user:pass`.
2. **Boolean negation support**:
   - `arg_spec.mbt:91`: `negatable=true accepts --no-<long> for long flags.`
   - `parser_validate.mbt:65`: Automatically checks and registers `no-{name}`.
   - `parser.mbt:474`: Matches `name is [.. "no-", .. target]` and sets `matches.flags[target] = false`.
   - Verified: `FlagArg("autoIndex", short='i', long="autoIndex", negatable=true)` correctly handles `--autoIndex`, `-i`, and `--no-autoIndex`.
   - Verified: `FlagArg("showDir", short='d', long="showDir", negatable=true)` correctly handles `--showDir`, `-d`, and `--no-showDir`.
3. **Hyphen value support (`-c -1`)**:
   - `arg_spec.mbt:147`: `OptionArg` has `allow_hyphen_values=true`.
   - Verified: `OptionArg("cache", short='c', long="cache", allow_hyphen_values=true)` accepts `-1` without treating it as an unknown flag.
4. **Unknown argument detection & contextual help**:
   - `error.mbt:61-71`: Produces structured `UnknownArgument(arg, hint)` with suggestions when typos occur.
   - `command.mbt:120`: Raises `ArgError::Message(text)` with full formatted contextual help and error description.

### 1.5 Process Lifecycle & Signal Handling
Inspection of `.mooncakes\moonbitlang\async\src\signal\signal.mbt` & `internal\event_loop\signal.c`:
1. **Windows Native signals**:
   - `moonbitlang/async` automatically hooks Windows console control events via `SetConsoleCtrlHandler` (`CTRL_C_EVENT`, `CTRL_BREAK_EVENT`, `CTRL_CLOSE_EVENT`).
   - Default global cancellation signals include `Signal::SIGINT` (`CTRL_C_EVENT`).
2. **Graceful shutdown in `server/server.mbt:23-47`**:
   - Server runs in an async task group.
   - `defer listener.close()` and `defer server.stop()` ensure that upon receiving cancellation, the listener is closed and tasks are cancelled.
   - In `handle_connection(server, tcp_conn)`, `defer tcp_conn.close()` ensures every connection socket is closed, guaranteeing 0 socket/file handle leaks.

---

## 2. Logic Chain

1. **Premise 1**: All CLI-passed arguments and configuration must be strictly validated before creating a TCP listener.
   - **Reasoning**: If an invalid port, invalid root directory, or conflicting option (e.g. `--spa` + `--try-files`) is passed, the server must output a clear error message to `stderr` and terminate with a non-zero exit code (code 1) without creating any socket.
   - **Evidence**: Observation 1.1.3 shows the current CLI prints to stdout and exits with code 0. Observation 1.2.3 shows `validate_config` is already implemented and ready to be used.

2. **Premise 2**: `core.Config` is the canonical representation of server configuration and must hold `log_ip` and `silent`.
   - **Reasoning**: All subsystems (CLI, Server, Engine, Middleware) consume `core.Config`. Adding `log_ip: Bool` (default `false`) and `silent: Bool` (default `false`) to `core.Config` provides complete feature parity without breaking existing code (because all existing tests construct configs via `Config::default(...)`).
   - **Evidence**: Observation 1.2.1 and 1.2.2.

3. **Premise 3**: CLI parsing logic should be placed in `cmd/http-server-mbt/cli.mbt`, NOT in `core/`.
   - **Reasoning**:
     - `docs/design.md` D-02 and D-14 mandate that `core` is a pure, portable module (compatible with Native, wasm-gc, C ABI) that must NOT import CLI, `@argparse`, or `@env`.
     - `core/moon.pkg` only depends on `"moonbitlang/core/string"`.
     - `cmd/http-server-mbt` is already the CLI package. By placing the declarative parser and mapping functions in `cmd/http-server-mbt/cli.mbt`, the CLI logic is cleanly decoupled and testable via `cmd/http-server-mbt/cli_wbtest.mbt`.
   - **Evidence**: Observation 1.1.1, 1.2.1, and MoonBit package test runner verification (Section 1.1 & D-02).

4. **Premise 4**: `moonbitlang/core/argparse` is fully capable of meeting all Milestone 5 CLI parsing requirements without third-party dependencies.
   - **Reasoning**:
     - It natively supports long flags, short flags, inline `--flag=value`, negatable flags (`--no-flag`), hyphen values (`-c -1`), positional arguments, and unknown argument detection.
     - By declaring `FlagArg("version", short='v', long="version")` with `disable_version_flag=true`, both `-v` and `--version` work as required.
     - By declaring `OptionArg("cache", short='c', long="cache", allow_hyphen_values=true)`, both numeric seconds and `max-age=N` formats are cleanly accepted and parsed.
   - **Evidence**: Observation 1.4.1 through 1.4.4.

5. **Premise 5**: Stderr writing and exit code 1 can be cleanly implemented in native MoonBit.
   - **Reasoning**:
     - Standard error writing can use `@stdio.stderr.write(msg + "\n")` or C runtime `exit(code)` via `extern "c" fn runtime_native_exit(code : Int) = "exit"`.
     - Calling `runtime_native_exit(1)` ensures an exact exit status of 1 across Windows and POSIX.
   - **Evidence**: Observation 1.1.3, 1.4.1, and `runtime_exit_native.mbt`.

---

## 3. Caveats

1. **Directory existence check**:
   Checking whether `root` directory exists requires calling `@fs.exists(root)` and `@fs.kind(root) == Directory` inside the async context of `main.mbt` before launching `@server.with_server_at`. If `root` is missing, print `error: root directory '<root>' does not exist` to stderr and exit 1.
2. **Default root directory fallback (`public` vs `.`)**:
   Per design D-01: if no positional root argument is passed, check whether `./public` exists and is a directory; if so, use `"public"`, otherwise use `"."`. If a positional root argument is explicitly passed, use it directly and verify it exists.
3. **`-a` flag assignment**:
   In Milestone 5 request, `-a` is specified as `--auth / -a <username:password>`. Note that original Node.js `http-server` had `-a` for address and `--user / --password` for credentials. Per Milestone 5 instructions and proposal, `-a` is mapped to `--auth`, and address can be specified via `--address <ip>` or default to `"0.0.0.0"`.

---

## 4. Conclusion & Recommended Design

### 4.1 Changes to `core/config.mbt`
Add two fields to `pub(all) struct Config`:
```moonbit
// In core/config.mbt:
pub(all) struct Config {
  ...
  // --- Logging & Output ---
  log_ip : Bool // Enable logging of client IP address (default false)
  silent : Bool // Suppress console log messages (default false)
  ...
}
```
Update `Config::default(root : String) -> Config`:
```moonbit
log_ip: false,
silent: false,
```

### 4.2 New File: `cmd/http-server-mbt/cli.mbt`
Implement the declarative parser and pure mapping logic:
```moonbit
pub enum CliAction {
  Help(String)
  Version(String)
  Run(@core.Config, Int) // (config, port)
}

pub fn build_command() -> @argparse.Command {
  @argparse.Command(
    "http-server-mbt",
    about="Windows Native static HTTP server",
    version="0.1.5",
    disable_help_flag=true,
    disable_version_flag=true,
    flags=[
      @argparse.FlagArg("help", short='h', long="help", about="show help"),
      @argparse.FlagArg("version", short='v', long="version", about="show version"),
      @argparse.FlagArg("spa", long="spa", about="fallback to root index.html"),
      @argparse.FlagArg(
        "autoIndex",
        short='i',
        long="autoIndex",
        negatable=true,
        about="display autoIndex [default: true]",
      ),
      @argparse.FlagArg(
        "showDir",
        short='d',
        long="showDir",
        negatable=true,
        about="show directory listings [default: true]",
      ),
      @argparse.FlagArg("cors", long="cors", about="enable CORS headers"),
      @argparse.FlagArg("log-ip", short='l', long="log-ip", about="log client IP address"),
      @argparse.FlagArg("silent", short='s', long="silent", about="suppress log messages"),
    ],
    options=[
      @argparse.OptionArg("port", short='p', long="port", env="PORT", about="listen TCP port [default: 8080]"),
      @argparse.OptionArg("base-url", long="base-url", about="mount URL prefix [default: /]"),
      @argparse.OptionArg("base-dir", long="base-dir", about="alias for base-url"),
      @argparse.OptionArg("try-files", long="try-files", about="custom fallback file relative to root"),
      @argparse.OptionArg(
        "cache",
        short='c',
        long="cache",
        allow_hyphen_values=true,
        about="cache duration in seconds or max-age [default: 3600]",
      ),
      @argparse.OptionArg("auth", short='a', long="auth", about="Basic Auth credentials <username:password>"),
    ],
    positionals=[
      @argparse.PositionArg("root", about="filesystem root [default: .]", num_args=@argparse.ValueRange(lower=0, upper=1)),
    ],
  )
}

pub fn parse_cli(argv : ArrayView[String]) -> Result[CliAction, String] {
  let cmd = build_command()
  let matches = cmd.parse(argv~) catch {
    err => return Err(err.to_string())
  }
  if matches.flags.get("help") == Some(true) {
    return Ok(CliAction::Help(cmd.render_help()))
  }
  if matches.flags.get("version") == Some(true) {
    return Ok(CliAction::Version("http-server-mbt 0.1.5"))
  }
  // Parse & validate port (1..65535)
  // Resolve base-url & base-dir via @core.resolve_base_url
  // Parse cache (numeric seconds, -1, max-age=N, or custom string)
  // Parse auth (split at ':', validate non-empty user)
  // Build Config and validate via @core.validate_config
  // Return Ok(CliAction::Run(config, port))
}
```

### 4.3 Updates to `cmd/http-server-mbt/main.mbt`
```moonbit
extern "c" fn runtime_native_exit(code : Int) = "exit"

async fn run() -> Unit {
  let argv = @env.args()
  let args = if argv.length() > 1 { argv[1:] } else { [] }
  match parse_cli(args) {
    Ok(Help(msg)) => println(msg)
    Ok(Version(msg)) => println(msg)
    Err(err) => {
      @stdio.stderr.write("\{err}\n") catch { _ => () }
      runtime_native_exit(1)
    }
    Ok(Run(config, port)) => {
      // Pre-flight check: root directory must exist
      if !(@fs.exists(config.root)) || @fs.kind(config.root) != Directory {
        @stdio.stderr.write("error: root directory '\{config.root}' does not exist\n") catch { _ => () }
        runtime_native_exit(1)
        return
      }
      @server.with_server_at(config, port, fn(_server) {
        if !config.silent {
          println("Starting up http-server, serving \{config.root}")
          println("Available on:")
          println("  http://127.0.0.1:\{port}")
          println("Hit CTRL-C to stop the server")
        }
      }) catch {
        _ if @async.is_being_cancelled() => ()
        error => {
          @stdio.stderr.write("server error: \{error}\n") catch { _ => () }
          runtime_native_exit(1)
        }
      }
    }
  }
}
```

### 4.4 New Unit Test File: `cmd/http-server-mbt/cli_wbtest.mbt`
Add whitebox tests covering:
1. Default arguments (`argv = []` -> port 8080, auto_index true, show_dir true, cache 3600, etc.)
2. Flag variations:
   - `-p 9000`, `--port 9000`, `--port=9000`
   - `-p 0`, `-p 70000`, `-p abc` -> `Err`
   - `--base-url /app`, `--base-dir app`, conflicting base-url/base-dir -> `Err`
   - `--spa`, `--try-files file.html`, both together -> `Err`
   - `--no-autoIndex`, `--autoIndex`, `-i`
   - `--no-showDir`, `--showDir`, `-d`
   - `-c 60`, `--cache -1`, `--cache max-age=3600`
   - `--cors`
   - `-a user:pass`, `--auth user:pass`, `--auth=user:pass`, `--auth invalid` -> `Err`
   - `-l`, `--log-ip`, `-s`, `--silent`
   - `-h`, `--help`, `-v`, `--version`
   - Unknown flags `--bad-flag` -> `Err` with contextual help

---

## 5. Verification Method

1. **Compile & Typecheck Verification**:
   ```powershell
   moon check --target native
   ```
   Must pass with **0 errors, 0 warnings**.

2. **Test Suite Verification**:
   ```powershell
   moon test --target native
   ```
   All existing 83 tests plus new CLI unit tests must pass 100%.

3. **Executable Smoke Test & Non-Zero Exit Verification**:
   ```powershell
   moon build --target native
   # 1. Help flag test (expect exit code 0):
   .\_build\native\debug\build\cmd\http-server-mbt\http-server-mbt.exe -h
   echo $LASTEXITCODE # must be 0

   # 2. Version flag test (expect exit code 0):
   .\_build\native\debug\build\cmd\http-server-mbt\http-server-mbt.exe -v
   echo $LASTEXITCODE # must be 0

   # 3. Invalid flag (expect exit code 1, stderr output):
   .\_build\native\debug\build\cmd\http-server-mbt\http-server-mbt.exe --unknown-flag 2>&1
   echo $LASTEXITCODE # must be 1

   # 4. Invalid port (expect exit code 1):
   .\_build\native\debug\build\cmd\http-server-mbt\http-server-mbt.exe -p 99999 2>&1
   echo $LASTEXITCODE # must be 1

   # 5. Non-existent root (expect exit code 1):
   .\_build\native\debug\build\cmd\http-server-mbt\http-server-mbt.exe ./non_existent_folder_xyz 2>&1
   echo $LASTEXITCODE # must be 1

   # 6. Conflicting options (expect exit code 1):
   .\_build\native\debug\build\cmd\http-server-mbt\http-server-mbt.exe --spa --try-files index.html 2>&1
   echo $LASTEXITCODE # must be 1
   ```

4. **Interface and Formatting**:
   ```powershell
   moon info --target native
   moon fmt
   ```
   Confirm `.mbti` diffs are clean and formatted.
