# Handoff Report: M1 Engine Warnings Remediation Strategy

**Agent**: `explorer_m1_engine`  
**Working Directory**: `D:\project\moonbit\http-server-mbt\.agents\explorer_m1_engine`  
**Date**: 2026-09-11  
**Handoff Type**: Hard (Task Complete)  

---

## 1. Observation

### 1.1 Compiler Diagnostics from `moon check --target native`
Directly observed in `moon check --target native` output:
- **`engine.mbt` Line 11:3 & 14:3**:
  ```text
  Warning: [0035]
      ╭─[ D:\project\moonbit\http-server-mbt\engine.mbt:11:3 ]
   11 │   use : async (StaticEngine) -> T,
      │   ─┬─  
      │    ╰─── Warning (reserved_keyword): The word `use` is reserved for possible future use. Please consider using another name.
  Warning: [0035]
      ╭─[ D:\project\moonbit\http-server-mbt\engine.mbt:14:3 ]
   14 │   use(engine)
      │   ─┬─  
      │    ╰─── Warning (reserved_keyword): The word `use` is reserved for possible future use. Please consider using another name.
  ```
- **`engine.mbt` Lines 28:3, 29:3, 30:3**:
  ```text
  Warning: [0008]
   28 │   pub status : Int
      │   ─┬─  
      │    ╰─── Warning (redundant_modifier): The public modifier is redundant here since field status is public by default
  Warning: [0008]
   29 │   pub headers : Map[String, String]
      │   ─┬─  
      │    ╰─── Warning (redundant_modifier): The public modifier is redundant here since field headers is public by default
  Warning: [0008]
   30 │   pub body : Bytes
      │   ─┬─  
      │    ╰─── Warning (redundant_modifier): The public modifier is redundant here since field body is public by default
  ```
- **`engine.mbt` Lines 62:3, 64:3**:
  ```text
  Warning: [0006]
   62 │   NotFound
      │   ────┬───  
      │       ╰───── Warning (unused_constructor): Variant 'NotFound' is never constructed
  Warning: [0006]
   64 │   Closed
      │   ───┬──  
      │      ╰──── Warning (unused_constructor): Variant 'Closed' is never constructed
  ```
- **`engine.mbt` Lines 244:26, 270:60, 304:16**:
  ```text
  Warning: [0020]
  244 │         data = Some(html.to_bytes())
      │                          ────┬───  
      │                              ╰───── Warning (deprecated): Check `@encoding/utf8.encode`
  Warning: [0020]
  270 │         output = body[r.start.to_int():r.end.to_int() + 1].to_bytes()
      │                                                            ────┬───  
      │                                                                ╰───── Warning (deprecated): Use `to_owned` to allocate an owned `Bytes` from a `BytesView`
  Warning: [0020]
  304 │     body: text.to_bytes(),
      │                ────┬───  
      │                    ╰───── Warning (deprecated): Check `@encoding/utf8.encode`
  ```
- **`engine_test.mbt` Lines 17:5, 31:5, 40:5, 65:5, 78:5**:
  ```text
  Warning: [0035]
   17 │     method: @core.Method::Get,
      │     ───┬──  
      │        ╰──── Warning (reserved_keyword): The word `method` is reserved for possible future use. Please consider using another name.
  (Repeated at lines 31, 40, 65, 78)
  ```
- **`moon.pkg` (root) Lines 2:3, 4:3**:
  ```text
  Warning: [0029]
    2 │   "moonbitlang/async",
      │   ─────────┬─────────  
      │            ╰─────────── Warning (unused_package): Unused package 'moonbitlang/async'
  Warning: [0029]
    4 │   "moonbitlang/async/http",
      │   ────────────┬───────────  
      │               ╰───────────── Warning (unused_package): Unused package 'moonbitlang/async/http'
  ```

### 1.2 Baseline Test Execution
Direct execution of `moon test --target native`:
```text
Total tests: 5, passed: 5, failed: 0.
```

### 1.3 Toolchain and Standard Library Verification
- `moon 0.1.20260904 (94521db 2026-09-04)` is installed at `D:\devenv\moonbit\bin\moon.exe`.
- Package `"moonbitlang/core/encoding/utf8"` exists at `D:\devenv\moonbit\lib\core\encoding\utf8`.
- Its exported function is `pub fn encode(StringView, bom? : Bool) -> Bytes`.
- In `D:\devenv\moonbit\lib\core\internal\os_string\os_string.mbt:66`, standard library usage confirms importing `"moonbitlang/core/encoding/utf8"` allows calling `@utf8.encode(str)`.
- In `engine.mbt:48`, `to_owned()` is already used on `BytesView`.

---

## 2. Logic Chain

1. **Manifest cleanup**: Root `moon.pkg` imports `"moonbitlang/async"` and `"moonbitlang/async/http"`. Neither package is referenced in `engine.mbt` or `engine_test.mbt` (Obs 1.1). Removing them eliminates two `[0029]` warnings.
2. **UTF-8 encode support**: `html.to_bytes()` and `text.to_bytes()` in `engine.mbt` trigger deprecation warnings `[0020]` advising `@encoding/utf8.encode` (Obs 1.1). Importing `"moonbitlang/core/encoding/utf8"` in root `moon.pkg` provides `@utf8.encode()` (Obs 1.3).
3. **BytesView conversion**: Slicing `body[...]` returns a `BytesView`. Calling `.to_bytes()` on `BytesView` triggers `[0020]` advising `to_owned` (Obs 1.1). Slicing already uses `.to_owned()` at line 48. Replacing line 270 with `.to_owned()` eliminates the warning while preserving byte semantics.
4. **Reserved keyword `use`**: `with_engine` names its closure parameter `use` at lines 11 and 14, triggering `[0035]` (Obs 1.1). Renaming to `handler` resolves the reserved keyword warning and does not alter the generated interface signature in `pkg.generated.mbti`.
5. **Redundant modifiers in `Response`**: In MoonBit struct definitions, fields are public by default; explicit `pub` triggers `[0008]` (Obs 1.1). Removing `pub` on fields `status`, `headers`, `body` eliminates all three warnings without changing field accessibility.
6. **Unused constructors in `ServerError`**: Variants `NotFound` and `Closed` are declared in `ServerError` but never constructed in the package (Obs 1.1). `handle` returns `Handled(404)` for missing files, and tests verify `Handled(response)` with `status == 404` (Obs 1.1, Obs 1.2). Removing `NotFound` and `Closed` eliminates two `[0006]` warnings.
7. **Reserved keyword `method` & cross-package alignment**: In `core/core.mbt`, `Request::method` triggers `[0035]` and is being renamed to `meth` by `explorer_m1_core`. Consequently:
   - `engine_test.mbt` struct literals must rename `method:` -> `meth:` (eliminating 5 `[0035]` warnings).
   - `engine.mbt` lines 161 and 289 must access `request.meth` to match `core.Request`.
8. **Behavioral preservation**: All changes are strictly syntactic refactorings. Field types and payload encodings are unchanged. All 5 native tests will continue to pass (Obs 1.2).

---

## 3. Caveats

- **`ServerError` variant removal vs preservation**: Option 1 removes `NotFound` and `Closed` from `ServerError` since they are unused stubs. If the team prefers preserving them for API compatibility, Option 2 can be used by declaring helper constructor functions (`pub fn ServerError::not_found() -> ServerError { NotFound }`). Option 1 is recommended as standard MoonBit convention.
- **Coordination timing**: Changes to `engine_test.mbt` and `engine.mbt` (`request.meth`) depend on `core/core.mbt` renaming `method` to `meth`. They should be applied in lockstep or core should be updated first.

---

## 4. Conclusion

All 17 compiler warnings in the root package scope can be completely resolved with zero regressions:
- 3 redundant modifiers removed (`engine.mbt:28,29,30`)
- 2 reserved keyword `use` renamed to `handler` (`engine.mbt:11,14`)
- 2 unused constructors removed or handled (`engine.mbt:62,64`)
- 3 deprecated byte conversions updated (`engine.mbt:244,270,304`)
- 5 reserved keyword `method` renamed to `meth` (`engine_test.mbt:17,31,40,65,78`)
- 2 cross-package member accesses aligned to `request.meth` (`engine.mbt:161,289`)
- 2 unused package imports removed, 1 encoding import added (`moon.pkg`)

Full diffs and step-by-step instructions are documented in `strategy.md`.

---

## 5. Verification Method

1. **Compilation Check**:
   ```powershell
   moon check --target native
   ```
   *Expected*: Root package warnings drop from 17 to 0.

2. **Test Suite Verification**:
   ```powershell
   moon test --target native
   ```
   *Expected*: 5 passed, 0 failed.

3. **Interface and Formatting Synchronization**:
   ```powershell
   moon info --target native
   moon fmt
   ```
   *Expected*: `pkg.generated.mbti` regenerates cleanly.
