# Handoff Report: M1 Server & CMD Compiler Warnings Remediation

## 1. Observation

Direct observations from diagnostic tool execution and source code examination:

### 1.1 Tool Command Output
Command: `moon check --target native` (working directory: `D:\project\moonbit\http-server-mbt`)
Total findings: 46 warnings, 0 errors.
Warnings specifically originating from `server/` and `cmd/`:

1. **`cmd/http-server-mbt/main.mbt:103:40`**:
   ```text
   Warning: [0067]
        ╭─[ D:\project\moonbit\http-server-mbt\cmd\http-server-mbt\main.mbt:103:40 ]
        │
    103 │   @server.with_server_at(config, port, async fn(_server) {
        │                                        ──┬──  
        │                                          ╰──── Warning (unused_async): This `async` annotation is useless.
    ────╯
   ```

2. **`server/moon.pkg:4:3`**:
   ```text
   Warning: [0029]
      ╭─[ D:\project\moonbit\http-server-mbt\server\moon.pkg:4:3 ]
      │
    4 │   "moonbitlang/async",
      │   ─────────┬─────────  
      │            ╰─────────── Warning (unused_package): Unused package 'moonbitlang/async'
   ───╯
   ```

3. **`server/server.mbt:12:3`**:
   ```text
   Warning: [0035]
       ╭─[ D:\project\moonbit\http-server-mbt\server\server.mbt:12:3 ]
       │
    12 │   use : async (Server) -> Unit,
       │   ─┬─  
       │    ╰─── Warning (reserved_keyword): The word `use` is reserved for possible future use. Please consider using another name.
   ────╯
   ```

4. **`server/server.mbt:14:32`**:
   ```text
   Warning: [0035]
       ╭─[ D:\project\moonbit\http-server-mbt\server\server.mbt:14:32 ]
       │
    14 │   with_server_at(config, 8080, use)
       │                                ─┬─  
       │                                 ╰─── Warning (reserved_keyword): The word `use` is reserved for possible future use. Please consider using another name.
   ────╯
   ```

5. **`server/server.mbt:24:3`**:
   ```text
   Warning: [0035]
       ╭─[ D:\project\moonbit\http-server-mbt\server\server.mbt:24:3 ]
       │
    24 │   use : async (Server) -> Unit,
       │   ─┬─  
       │    ╰─── Warning (reserved_keyword): The word `use` is reserved for possible future use. Please consider using another name.
   ────╯
   ```

6. **`server/server.mbt:30:3`**:
   ```text
   Warning: [0035]
       ╭─[ D:\project\moonbit\http-server-mbt\server\server.mbt:30:3 ]
       │
    30 │   use(server)
       │   ─┬─  
       │    ╰─── Warning (reserved_keyword): The word `use` is reserved for possible future use. Please consider using another name.
   ────╯
   ```

7. **`server/server.mbt:32:9`**:
   ```text
   Warning: [0035]
       ╭─[ D:\project\moonbit\http-server-mbt\server\server.mbt:32:9 ]
       │
    32 │     let method = match request.meth {
       │         ───┬──  
       │            ╰──── Warning (reserved_keyword): The word `method` is reserved for possible future use. Please consider using another name.
   ────╯
   ```

8. **`server/server.mbt:35:45`**:
   ```text
   Warning: [0020]
       ╭─[ D:\project\moonbit\http-server-mbt\server\server.mbt:35:45 ]
       │
    35 │       _ => @core.Method::Other(request.meth.to_string())
       │                                             ────┬────  
       │                                                 ╰────── Warning (deprecated): `Show` implementation for this type is deprecated, use `Debug` related API, or use `@debug.to_string` instead.
   ────╯
   ```

9. **`server/server.mbt:37:41`**:
   ```text
   Warning: [0020]
       ╭─[ D:\project\moonbit\http-server-mbt\server\server.mbt:37:41 ]
       │
    37 │     let headers : Map[String, String] = Map::new()
       │                                         ────┬───  
       │                                             ╰───── Warning (deprecated): Use `Map([], capacity=...)` instead
   ────╯
   ```

10. **`server/server.mbt:41:41`**:
    ```text
    Warning: [0035]
        ╭─[ D:\project\moonbit\http-server-mbt\server\server.mbt:41:41 ]
        │
     41 │     let result = server.engine.handle({ method, target: request.path, headers, })
        │                                         ───┬──  
        │                                            ╰──── Warning (reserved_keyword): The word `method` is reserved for possible future use. Please consider using another name.
    ────╯
    ```

11. **`server/server.mbt:44:62`**:
    ```text
    Warning: [0020]
        ╭─[ D:\project\moonbit\http-server-mbt\server\server.mbt:44:62 ]
        │
     44 │         let out : Map[@http.CaseInsensitiveString, String] = Map::new()
        │                                                              ────┬───  
        │                                                                  ╰───── Warning (deprecated): Use `Map([], capacity=...)` instead
    ────╯
    ```

### 1.2 Surrounding Context Observations
- `cmd/http-server-mbt/moon.pkg`: Imports `server`, `core`, `moonbitlang/async`, `moonbitlang/core/env`, `moonbitlang/core/argparse`. All are actively used; no warnings.
- `server/moon.pkg`: Imports `"moonbitlang/async"` in addition to `"moonbitlang/async/http"`, `"moonbitlang/async/socket"`, `"moonbitlang/async/io"`. `server/server.mbt` only references `@http` and `@socket`; no `@async` symbols appear anywhere in `server.mbt`.
- `server/pkg.generated.mbti`:
  - `pub async fn with_server(@core.Config, async (Server) -> Unit) -> Unit`
  - `pub async fn with_server_at(@core.Config, Int, async (Server) -> Unit) -> Unit`
  - Neither positional parameter names nor `"moonbitlang/async"` are part of the exported interface.

---

## 2. Logic Chain

1. **`unused_async` remediation in `cmd/http-server-mbt/main.mbt:103`**:
   - Observation 1.1 (#1) shows `async fn(_server)` marked as useless `async`.
   - Inspection of lines 103-105 reveals the body contains only `println("Listening on port \{port}")`, which performs zero async operations (`await` or async calls).
   - In MoonBit, synchronous closures satisfy parameter types of form `async (T) -> Unit` without qualification.
   - Therefore, replacing `async fn(_server)` with `fn(_server)` completely clears Warning [0067] while maintaining exact type conformance with `with_server_at`.

2. **`unused_package` remediation in `server/moon.pkg:4`**:
   - Observation 1.1 (#2) and 1.2 demonstrate that `"moonbitlang/async"` is unused.
   - Language features `async fn` and `defer` are compiler intrinsics and do not depend on the package namespace `moonbitlang/async`.
   - Subpackages `moonbitlang/async/http`, `socket`, and `io` remain imported and satisfy all external type requirements.
   - Therefore, removing `"moonbitlang/async",` from `server/moon.pkg` clears Warning [0029] without compile errors.

3. **`reserved_keyword: use` remediation in `server/server.mbt:12, 14, 24, 30`**:
   - Observation 1.1 (#3, #4, #5, #6) identifies `use` as a reserved keyword in MoonBit.
   - Observation 1.2 shows that `server/pkg.generated.mbti` declares `with_server` and `with_server_at` without positional parameter names.
   - Renaming `use` to `action` in both function signatures and internal call sites (`action(server)`) eliminates all 4 occurrences of Warning [0035] and leaves public interface signatures identical.

4. **`reserved_keyword: method` remediation in `server/server.mbt:32, 41`**:
   - Observation 1.1 (#7, #10) identifies `method` as a reserved keyword.
   - In `core/core.mbt:12`, struct field `method : Method` is simultaneously being renamed to `meth : Method` by `explorer_m1_core`.
   - Renaming local variable `method` to `meth` aligns directly with `@http.Request.meth`, avoids the keyword conflict, and allows struct punning `{ meth, target: request.path, headers, }` on line 41 to construct `@core.Request` seamlessly.
   - This clears both occurrences of Warning [0035].

5. **`deprecated: Show for RequestMethod` remediation in `server/server.mbt:35`**:
   - Observation 1.1 (#8) shows `request.meth.to_string()` invoking a deprecated `Show` implementation.
   - Verification of `.mooncakes/moonbitlang/async/src/http/deprecated.mbt:70-71` confirms the compiler warning recommendation: "use Debug related API, or use @debug.to_string instead."
   - Replacing `request.meth.to_string()` with `@debug.to_string(request.meth)` produces PascalCase strings (`"Post"`, etc.) identical to the previous behavior and clears Warning [0020].

6. **`deprecated: Map::new()` remediation in `server/server.mbt:37, 44`**:
   - Observation 1.1 (#9, #11) notes `Map::new()` is deprecated in favor of `Map([], capacity=...)`.
   - In MoonBit core stdlib, `Map([])` is the canonical literal constructor for an empty map.
   - Replacing both calls with `Map([])` satisfies the compiler and clears both instances of Warning [0020].

---

## 3. Caveats

1. **Inter-package Coordination with `core/core.mbt`**:
   - Line 41 of `server/server.mbt` constructs `@core.Request` using struct punning `{ meth, target: request.path, headers, }`.
   - This requires `core/core.mbt` to have renamed field `method` to `meth`. If applied in isolation before `core/` is updated, a field mismatch error will occur. Both packages must be updated together during M1 execution.
2. **String casing of `@core.Method::Other`**:
   - `@debug.to_string(request.meth)` outputs PascalCase (`"Post"`). If canonical HTTP method uppercase (`"POST"`) is required, an explicit pattern match mapping should be used. For the static file server, all non-GET/HEAD methods are routed to 405 Method Not Allowed anyway, so string casing does not alter server behavior.
3. **Scope Bounds**:
   - This investigation exclusively analyzed `server/` and `cmd/http-server-mbt/`. The other 35 compiler warnings in `core/` and `engine.mbt` are documented and resolved by their respective explorer agents.

---

## 4. Conclusion

All 11 compiler warnings in `server/` and `cmd/http-server-mbt/` have been comprehensively diagnosed. The remediation strategy is completely specified in `strategy.md` with exact line diffs and proposed file contents:
- `cmd/http-server-mbt/main.mbt`: 1 warning eliminated.
- `server/moon.pkg`: 1 warning eliminated.
- `server/server.mbt`: 9 warnings eliminated.
Total warnings eliminated: 11.
No breaking changes are introduced to public APIs or `.mbti` signatures.

---

## 5. Verification Method

To independently verify after the patches are applied:

1. **Compiler Warning Check**:
   ```powershell
   moon check --target native
   ```
   **Expected**: The 11 warnings from `server/` and `cmd/` must disappear completely from the compiler output.

2. **Interface Parity Check**:
   ```powershell
   moon info --target native
   git diff server/pkg.generated.mbti cmd/http-server-mbt/pkg.generated.mbti
   ```
   **Expected**: Zero diff against `server/pkg.generated.mbti` and `cmd/http-server-mbt/pkg.generated.mbti`.

3. **Format & Test Verification**:
   ```powershell
   moon fmt
   moon test --target native
   ```
   **Expected**: All tests pass cleanly without errors.
