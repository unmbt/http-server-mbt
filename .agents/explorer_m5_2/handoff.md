# Milestone 5 Pre-flight Validation & Error Handling Investigation Report

## 1. Observation

### 1.1 Existing CLI Status (`cmd/http-server-mbt/main.mbt`)
Direct inspection of `cmd/http-server-mbt/main.mbt` reveals:
- **Port Parsing (lines 10–27)**:
  ```moonbit
  fn parse_port(value : String) -> Int? {
    let chars = value.to_array()
    if chars.length() == 0 { return None }
    let mut n = 0
    for c in chars {
      if c < '0' || c > '9' { return None }
      n = n * 10 + c.to_int() - '0'.to_int()
    }
    if n < 1 || n > 65535 { None } else { Some(n) }
  }
  ```
  - Port `<= 0` or `> 65535` returns `None`.
  - Non-numeric strings return `None`.
  - Floating point strings (e.g. `"9090.86"` from `process-env-port.test.js` / C033.02) return `None`, instead of being truncated to `9090` per AD-04 specification.
- **Error Output & Exit (lines 68–72, 87–90, 97–100)**:
  ```moonbit
  println("error: failed to parse arguments")
  return
  ...
  println("error: invalid port")
  return
  ...
  println("error: invalid base-url")
  return
  ```
  - Errors are written to **stdout** via `println()`, NOT to **stderr**.
  - Functions simply `return`, terminating `main` with **exit code 0**, completely violating R2 ("发生配置错误时，向 stderr 输出友好错误提示并以非 0 状态退出，绝不进入 TCP 监听或泄露异常栈").
- **Root Directory Validation**:
  - `let root = first_value(matches, "root").unwrap_or(".")`
  - There is zero validation of whether `root` exists or is a directory on disk.
- **CLI Options Supported in `command()` (lines 30–59)**:
  - Only `--help`, `--version`, `--port` / `-p`, `--base-url`, and positional `root` are registered in `@argparse.Command`.
  - Missing options required by R1: `--base-dir`, `--spa`, `--try-files <file>`, `--autoIndex` / `-i` / `--no-autoIndex`, `--showDir` / `-d` / `--no-showDir`, `--cache` / `-c <sec>`, `--cors`, `--auth` / `-a <username:password>`, `--log-ip` / `-l`, `--silent` / `-s`.

### 1.2 Existing Core Validation (`core/config.mbt`)
Direct inspection of `core/config.mbt` reveals:
- **`validate_config` function exists (lines 237–303)**:
  ```moonbit
  pub fn validate_config(config : Config) -> Unit raise ConfigError
  ```
  It validates:
  - `validate_root`: checks `root == ""` or contains `\0` (syntactic only, no filesystem I/O).
  - `normalize_base_url`: validates URL mount prefix syntax.
  - `port`: checks `config.port < 0 || config.port > 65535` (ephemeral `0` allowed in `Config`, but out-of-range rejected).
  - `idle_timeout_ms < 0`: raises `ConfigError::InvalidTimeout`.
  - `validate_try_files_path`: checks relative path syntax, forbids `/`, `\`, `\0`, CRLF, `..`, `.`, `$uri`, `=404`, spaces, commas.
  - Mutual exclusion `config.spa && config.try_files is Some(_)`: raises `ConfigError::ConflictingRouting`.
  - Mutual exclusion `has_fallback && has_proxy`: raises `ConfigError::ConflictingRouting`.
  - Proxy consistency: `proxy_all is Some(_) && proxy is None` raises `ConfigError::InvalidProxy`.
  - Proxy URL scheme: must start with `http://` or `https://`.
  - Basic Auth credentials: username cannot contain `:`, username/password cannot contain `\0`.
  - Custom headers: cannot contain CRLF (`\r` or `\n`).
- **Missing validations in `core/config.mbt`**:
  - `Config::validate(self : Config)` method does not exist (only `validate_config(config : Config)` is declared).
  - Negative cache duration: `config.cache_seconds < -1` is not currently checked (D-01 allows `-1` for no-cache, but `< -1` is invalid).
- **Architectural Boundary (`core/moon.pkg`)**:
  - `core` only imports `"moonbitlang/core/string"`.
  - Per D-02, `core` is pure and portable (Native + wasm-gc compatible) and MUST NOT import Native I/O (`@fs`).
  - Therefore, physical filesystem checks (verifying `root` exists and is a directory) belong to the Native execution layer (`cmd/http-server-mbt` and `server`/`engine`), while `core` performs syntactic, range, and mutual exclusion validations.

### 1.3 Routing Normalization (`core/routing.mbt`)
Direct inspection of `core/routing.mbt` reveals:
- `normalize_base_url(value : String) -> String raise ConfigError`:
  - `""` and `"/"` normalize to `"/"`.
  - Rejects invalid characters: `?`, `#`, `\`, `\0`, `\r`, `\n`.
  - Rejects `..` and consecutive slashes `//`.
  - Adds leading `/` and strips trailing `/` (e.g. `"app/"` -> `"/app"`).
- `resolve_base_url(base_url : String?, base_dir : String?) -> String raise ConfigError`:
  - Resolves both options.
  - If both are specified and their normalized forms differ, raises `ConfigError::ConflictingBaseUrl`.

### 1.4 Native Stderr Output & Process Exit Mechanisms in MoonBit Native
Investigation of MoonBit core libraries and toolchain reveals:
- **Process Exit**:
  In `E:\dev-env\moonbit\lib\core\argparse\runtime_exit_native.mbt`:
  ```moonbit
  #cfg(any(target="native", target="llvm"))
  extern "c" fn runtime_native_exit(code : Int) = "exit"
  ```
  Calling C `exit(code)` via `extern "c"` is the official mechanism used by the MoonBit standard library itself.
  It immediately terminates the process with the given exit code, flushing C runtime file buffers, without triggering panics, abort handlers, or leaking stack traces.
- **Standard Error Output**:
  - In `moonbitlang/async@0.21.3`, package `moonbitlang/async/stdio` exposes:
    ```moonbit
    pub let stderr : Output = @event_loop.stderr
    ```
    On Windows Native, `setup_stdio(2)` connects to `GetStdHandle(STD_ERROR_HANDLE)` (`-12`).
    It implements `pub(open) trait @io.Writer`.
    In async contexts (`main.mbt` runs inside `async fn run() -> Unit`), `@stdio.stderr.write(msg + "\n")` directly writes to stderr.
  - Alternatively/complementarily, a direct C FFI printer or standard error writer can output synchronously without relying on async event loops:
    ```moonbit
    #cfg(platform="windows")
    extern "C" fn write_stderr_c(buf : String) = ... // or Win32 WriteFile(GetStdHandle(STD_ERROR_HANDLE))
    ```
    In `cmd/http-server-mbt`, `@stdio.stderr.write` combined with defensive fallback to stdout ensures 100% reliable error delivery before calling `exit(1)`.

---

## 2. Logic Chain

1. **R2 Requirement & Test Case C033/C041 Demands**:
   - `process-env-port.test.js` (C033) tests valid port, floating point `PORT=9090.86` (truncated to 9090), and invalid ports `-1`, `65536`, `65537`, expecting non-zero exit and no listening socket.
   - `cli.test.js` (C041) tests proxy missing protocol exiting with 1, `proxy-all` missing proxy exiting with 1, and boolean flags preserving positionals.
   - `ORIGINAL_REQUEST.md` (R2) mandates:
     "在启动监听前严格拦截非法配置：无效端口号（超出 1-65535）、不存在的 root 目录、非法 base-url / base-dir 路径格式、以及互斥配置（如 `--spa` 与互斥路由组合）。发生配置错误时，向 stderr 输出友好错误提示并以非 0 状态退出，绝不进入 TCP 监听或泄露异常栈。"
2. **From Observation 1.1**:
   - Currently, `main.mbt` prints errors to stdout using `println()` and executes `return`, giving exit code 0.
   - This directly fails R2 and C033/C041 exit code assertions (`t.not(evt.code, 0)`).
   - Therefore, `main.mbt` must be modified to print to stderr and call `runtime_native_exit(1)` upon validation failure.
3. **From Observation 1.2 & 1.3**:
   - `core/config.mbt` already implements most syntactic and mutual-exclusion rules in `validate_config(config : Config)`.
   - However, `Config::validate(self : Config)` should be exposed as an instance method for ergonomic access.
   - `config.cache_seconds < -1` should be explicitly validated.
   - `root` directory existence check cannot be placed in `core` because `core` has no I/O dependencies.
   - Therefore, physical checks must be performed in `cmd/http-server-mbt` before initializing the server, using `@fs.exists(root)` and `@fs.kind(root) is @fs.FileKind::Directory`.
4. **From Observation 1.4**:
   - MoonBit does not have a `@sys` package.
   - MoonBit's standard library `argparse` uses `extern "c" fn runtime_native_exit(code : Int) = "exit"` to terminate with non-zero exit codes.
   - `@stdio.stderr` in `moonbitlang/async/stdio` writes asynchronously to the OS standard error stream.
   - Together, `@stdio.stderr.write(...)` followed by `runtime_native_exit(1)` provides clean, unpolluted, zero-stack-trace exit handling.

---

## 3. Caveats

1. **Port 0 Handling**:
   - In library usage (`core.Config` and `server.with_server_at`), port `0` is valid and instructs the OS to assign an ephemeral TCP port (essential for concurrent integration tests).
   - For CLI execution, `ORIGINAL_REQUEST.md` specifies "无效端口号（超出 1-65535）", and `http-server` original documentation notes `-p --port Port to use. If 0, look for open port [8080]`. In CLI pre-flight check, port must be within `1..=65535`.
2. **Floating Point Port Parsing (AD-04 & C033.02)**:
   - Node.js `parseInt(process.env.PORT, 10)` truncates strings like `"9090.86"` to integer `9090`.
   - When parsing port strings from CLI or `PORT` environment variable, digits preceding `.` should be converted to an integer, matching original behavior without crashing or failing.
3. **Fallback Target File Check on Startup (D-04)**:
   - D-04 notes that during runtime, if a fallback target file is missing, the engine produces a terminal 404 (verified in `engine_security_directory_adversarial_test.mbt:397`).
   - The CLI pre-flight must strictly check the existence of the `root` directory. If the `root` directory itself does not exist, the CLI must abort immediately with exit code 1.
4. **`negatable=true` in `@argparse.FlagArg`**:
   - `@argparse.FlagArg(..., negatable=true)` natively generates `--no-<name>` (e.g. `--no-autoIndex`, `--no-showDir`), aligning with R1 requirements without manual parsing hackery.

---

## 4. Conclusion & Actionable Recommendations

### 4.1 Recommended CLI Pre-Flight Validation Flow (in `cmd/http-server-mbt/main.mbt`)

The pre-flight sequence in `main.mbt` before calling `@server.with_server_at` must be structured as follows:

```
[CLI Argv Parsing via @argparse]
       │
       ├──> Parse Error ──> Write to stderr + print help ──> exit(1)
       │
       ├──> --help / -h ──> Print help to stdout ──> exit(0)
       │
       ├──> --version / -v ──> Print version to stdout ──> exit(0)
       │
[Pre-flight Validation Step 1: Port]
       ├──> If port <= 0 or > 65535 or non-numeric (handling float truncation)
       │    └──> Write "Error: invalid port '<val>' (must be 1-65535)" to stderr ──> exit(1)
       │
[Pre-flight Validation Step 2: Root Directory]
       ├──> If !@fs.exists(root) || !(@fs.kind(root) is @fs.FileKind::Directory)
       │    └──> Write "Error: root directory '<root>' does not exist or is not a directory" to stderr ──> exit(1)
       │
[Pre-flight Validation Step 3: Base-URL & Base-Dir]
       ├──> core.resolve_base_url(base_url, base_dir)
       │    └──> Catch ConfigError::* ──> Write "Error: <msg>" to stderr ──> exit(1)
       │
[Pre-flight Validation Step 4: Auth Format]
       ├──> If --auth specified: verify contains ':' and valid username/password
       │    └──> If invalid ──> Write "Error: invalid auth format (expected username:password)" to stderr ──> exit(1)
       │
[Pre-flight Validation Step 5: Cache Option]
       ├──> If -c / --cache specified: parse Int, verify >= -1
       │    └──> If < -1 or non-numeric ──> Write "Error: invalid cache value" to stderr ──> exit(1)
       │
[Pre-flight Validation Step 6: Config Object Validation]
       ├──> config.validate() (calling core.validate_config)
       │    ├──> Mutual exclusion violations: --spa + --try-files
       │    ├──> Mutual exclusion violations: fallback + proxy
       │    ├──> Proxy defects: --proxy-all without --proxy, invalid proxy URL
       │    ├──> Try-files syntactic defects
       │    └──> Catch ConfigError ──> Write "Error: <msg>" to stderr ──> exit(1)
       │
[Start Server & Listen]
       └──> @server.with_server_at(config, port, ...)
```

### 4.2 Proposed Code Enhancements in `core/config.mbt`

1. Expose `Config::validate` method:
   ```moonbit
   pub fn Config::validate(self : Config) -> Unit raise ConfigError {
     validate_config(self)
   }
   ```
2. Enrich `validate_config`:
   ```moonbit
   if config.cache_seconds < -1 {
     raise ConfigError::InvalidHeader("cache_seconds cannot be less than -1")
   }
   ```
3. Add helper to parse CLI auth string:
   ```moonbit
   pub fn parse_auth_credential(str : String) -> (String, String)? {
     match str.find(":") {
       Some(idx) => {
         let username = str[:idx].to_owned()
         let password = str[idx + 1:].to_owned()
         Some((username, password))
       }
       None => None
     }
   }
   ```

### 4.3 Proposed Implementation for `cmd/http-server-mbt/`

1. **Imports in `cmd/http-server-mbt/moon.pkg`**:
   Add `"moonbitlang/async/stdio"` and `"moonbitlang/async/fs"`:
   ```moonbit
   import {
     "unmbt/http-server-mbt/server",
     "unmbt/http-server-mbt/core",
     "moonbitlang/async",
     "moonbitlang/async/stdio",
     "moonbitlang/async/fs",
     "moonbitlang/core/env",
     "moonbitlang/core/argparse",
   }
   ```
2. **Process Exit Helper**:
   ```moonbit
   #cfg(any(target="native", target="llvm"))
   extern "c" fn runtime_exit(code : Int) = "exit"

   #cfg(not(any(target="native", target="llvm")))
   fn runtime_exit(code : Int) = abort("exit(\{code})")
   ```
3. **Stderr Printer Helper**:
   ```moonbit
   async fn eprintln(msg : String) -> Unit {
     try {
       @stdio.stderr.write(msg + "\n")
     } catch {
       _ => println(msg)
     }
   }
   ```
4. **Enhanced Port Parser (with Float Support per C033/AD-04)**:
   ```moonbit
   fn parse_port(value : String) -> Int? {
     let trimmed = value.trim()
     if trimmed.length() == 0 {
       return None
     }
     let int_part = match trimmed.find(".") {
       Some(idx) => trimmed[:idx].to_owned()
       None => trimmed
     }
     let chars = int_part.to_array()
     if chars.length() == 0 {
       return None
     }
     let mut n = 0
     for c in chars {
       if c < '0' || c > '9' {
         return None
       }
       n = n * 10 + c.to_int() - '0'.to_int()
       if n > 65535 {
         return None
       }
     }
     if n < 1 || n > 65535 {
       None
     } else {
       Some(n)
     }
   }
   ```

---

## 5. Verification Method

To verify these findings and implementations:

1. **Typecheck & 0 Warnings**:
   ```powershell
   moon check --target native
   ```
   Must pass with 0 errors and 0 warnings.
2. **Existing Test Suite Integrity**:
   ```powershell
   moon test --target native
   ```
   All 83 existing unit and integration tests must pass 100%.
3. **CLI Pre-Flight Validation Tests**:
   Create a dedicated test file `cmd/http-server-mbt/cli_test.mbt` or `server/cli_preflight_test.mbt` testing:
   - Invalid port strings (`"0"`, `"-1"`, `"65536"`, `"abc"`, `""`) -> verified rejected.
   - Float port strings (`"9090.86"`) -> truncated to `9090` and accepted.
   - Non-existent root directory (`"nonexistent_dir_12345"`) -> verified rejected.
   - Conflicting base-url and base-dir (`--base-url /app --base-dir other`) -> verified rejected.
   - Mutually exclusive configurations (`--spa` + `--try-files`) -> verified rejected.
   - Mutually exclusive configurations (`--spa` + `--proxy`) -> verified rejected.
   - Invalid auth strings (`"no_colon_here"`) -> verified rejected.
4. **End-to-End CLI Execution via Subprocess**:
   Execute compiled CLI executable using `@process.collect_stderr` in a test or shell:
   ```powershell
   # Run with invalid port
   ./target/native/release/build/cmd/http-server-mbt/http-server-mbt.exe -p 99999
   # Exit code must be 1, stderr must contain "Error: invalid port"
   ```
   ```powershell
   # Run with non-existent root
   ./target/native/release/build/cmd/http-server-mbt/http-server-mbt.exe ./does_not_exist_folder
   # Exit code must be 1, stderr must contain "Error: root directory"
   ```
