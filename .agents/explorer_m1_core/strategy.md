# M1 Remediation Strategy: `core` Package Warning Elimination

## Executive Summary
This document provides the exact, line-by-line remediation strategy to completely eliminate all 18 compiler warnings in `unmbt/http-server-mbt/core` under `moon check -p core --target native`, achieving **0 errors and 0 warnings**. It also analyzes the downstream impact and coordinates changes with `engine` and `server`.

---

## 1. Warning Inventory & Classification in `core`

Running `moon check -p core --target native` identifies precisely 18 warnings across 4 distinct categories:

| Warning Code | Category | File & Line | Identifier / Content | Remediation Action |
|---|---|---|---|---|
| `[0008]` | `redundant_modifier` | `core/core.mbt:12:3` | `pub method` | Remove `pub` modifier |
| `[0035]` | `reserved_keyword` | `core/core.mbt:12:7` | `method` | Rename `method` -> `meth` |
| `[0008]` | `redundant_modifier` | `core/core.mbt:13:3` | `pub target` | Remove `pub` modifier |
| `[0008]` | `redundant_modifier` | `core/core.mbt:14:3` | `pub headers` | Remove `pub` modifier |
| `[0008]` | `redundant_modifier` | `core/core.mbt:20:3` | `pub root` | Remove `pub` modifier |
| `[0008]` | `redundant_modifier` | `core/core.mbt:21:3` | `pub base_url` | Remove `pub` modifier |
| `[0008]` | `redundant_modifier` | `core/core.mbt:22:3` | `pub default_ext` | Remove `pub` modifier |
| `[0008]` | `redundant_modifier` | `core/core.mbt:23:3` | `pub gzip` | Remove `pub` modifier |
| `[0008]` | `redundant_modifier` | `core/core.mbt:24:3` | `pub brotli` | Remove `pub` modifier |
| `[0008]` | `redundant_modifier` | `core/core.mbt:25:3` | `pub auto_index` | Remove `pub` modifier |
| `[0008]` | `redundant_modifier` | `core/core.mbt:26:3` | `pub show_dir` | Remove `pub` modifier |
| `[0008]` | `redundant_modifier` | `core/core.mbt:27:3` | `pub show_dotfiles` | Remove `pub` modifier |
| `[0008]` | `redundant_modifier` | `core/core.mbt:28:3` | `pub cache_control` | Remove `pub` modifier |
| `[0008]` | `redundant_modifier` | `core/core.mbt:50:3` | `pub start` | Remove `pub` modifier |
| `[0008]` | `redundant_modifier` | `core/core.mbt:51:3` | `pub end` | Remove `pub` modifier |
| `[0027]` | `deprecated_syntax` | `core/core.mbt:63:21` | `\x00` in `normalize_base_url` | Replace `"\x00"` with `"\u0000"` |
| `[0027]` | `deprecated_syntax` | `core/core.mbt:83:20` | `\x00` in `validate_relative_path` | Replace `"\x00"` with `"\u0000"` |
| `[0006]` | `unused_constructor` | `core/core.mbt:141:3` | `InvalidRoot(String)` | Implement `validate_root` function constructing `InvalidRoot` |

Total warnings in `core/`: 18.

---

## 2. Root Cause Analysis & Detailed Fix Strategy

### 2.1 Category 1: `redundant_modifier` (14 occurrences)
- **Root Cause**: In MoonBit, declaring a struct with `pub(all) struct Name { ... }` automatically grants public visibility to all fields in the struct. Prefixing individual field declarations with `pub` inside a `pub(all) struct` is redundant, triggering compiler warning `[0008]`.
- **Target Structs**:
  1. `Request` (lines 11-15): 3 fields (`method`, `target`, `headers`).
  2. `Config` (lines 19-29): 9 fields (`root`, `base_url`, `default_ext`, `gzip`, `brotli`, `auto_index`, `show_dir`, `show_dotfiles`, `cache_control`).
  3. `ByteRange` (lines 49-52): 2 fields (`start`, `end`).
- **Fix Action**: Strip the leading `pub ` keyword from each of the 14 field definitions.
- **ABI / `.mbti` Impact**: None. `core/pkg.generated.mbti` already declares these fields without individual `pub` keywords because `pub(all)` on the struct dictates the interface.

### 2.2 Category 2: `reserved_keyword` (1 occurrence in `core`, ripple effect in `engine` & `server`)
- **Root Cause**: The identifier `method` is a reserved keyword in MoonBit. Using `method` as a struct field name triggers warning `[0035]`.
- **Target Location**: `core/core.mbt:12:7`.
- **Fix Action**: Rename `method` to `meth` in `Request`:
  ```moonbit
  pub(all) struct Request {
    meth : Method
    target : String
    headers : Map[String, String]
  }
  ```
- **Rationale**:
  - Aligns with `PROJECT.md` line 57: `core.Request: Represents normalized HTTP request (meth: Method, url: String, ...)`
  - Aligns with standard library / async convention (e.g. `moonbitlang/async/http` request structure uses `request.meth`).
  - Eliminates 5 downstream `reserved_keyword` warnings in `engine_test.mbt` (lines 17, 31, 40, 65, 78) when tests construct requests.
  - Aligns with `server/server.mbt:32` where `request.meth` is mapped.

### 2.3 Category 3: `deprecated_syntax` (2 occurrences)
- **Root Cause**: In MoonBit string literals, hex escape sequences `\x..` are deprecated in favor of 4-digit unicode escape sequences `\u....`. Using `\x00` triggers warning `[0027]`.
- **Target Locations**:
  - `core/core.mbt:63:21` (inside `normalize_base_url`)
  - `core/core.mbt:83:20` (inside `validate_relative_path`)
- **Fix Action**: Replace `"\x00"` with `"\u0000"`.
- **Behavioral Impact**: Zero. `"\u0000"` denotes the exact same ASCII NUL character (`0x00`) with modern, standard MoonBit string literal syntax.

### 2.4 Category 4: `unused_constructor` (1 occurrence)
- **Root Cause**: In `core/core.mbt:139-142`, `pub suberror ConfigError` declares `InvalidBaseUrl(String)` and `InvalidRoot(String)`. While `InvalidBaseUrl` is constructed in `normalize_base_url`, `InvalidRoot` was never constructed anywhere in `core`, triggering warning `[0006]`.
- **Architectural Context**:
  - `docs/design.md` lines 33, 43, 97 mandate pre-listen configuration validation where invalid root / base-url / parameters reject before socket binding and return `ConfigError`.
  - `core/pkg.generated.mbti:18` already publishes `InvalidRoot(String)` as part of the public `ConfigError` type.
- **Fix Action**: Introduce `validate_root(root : String) -> String raise` in `core/core.mbt` which validates that `root` is non-empty and contains no NUL bytes (`\u0000`), raising `ConfigError::InvalidRoot`:
  ```moonbit
  ///|
  /// Validate a filesystem root directory path.
  pub fn validate_root(root : String) -> String raise {
    if root == "" || root.contains("\u0000") {
      raise ConfigError::InvalidRoot("root cannot be empty or contain null bytes")
    }
    root
  }
  ```
- **Rationale**:
  - Directly eliminates `unused_constructor` warning for `InvalidRoot`.
  - Symmetrically mirrors `normalize_base_url(value : String) -> String raise`.
  - Preserves `ConfigError::InvalidRoot` in `.mbti` without breaking existing public API signatures.
  - Enables pre-listen root validation in CLI and server embedding.
- **Companion Test**: Add unit test in `core/core_test.mbt` testing valid roots (`"."`, `"public"`) and invalid roots (`""`, `"dir\u0000sub"`).

---

## 3. Exact Code Replacement Specifications

### 3.1 Target File: `core/core.mbt`

#### Modification 1: `Request` struct (Lines 11-15)
```moonbit
<<<<<<< BEFORE (Lines 11-15)
pub(all) struct Request {
  pub method : Method
  pub target : String
  pub headers : Map[String, String]
}
=======
pub(all) struct Request {
  meth : Method
  target : String
  headers : Map[String, String]
}
>>>>>>> AFTER
```

#### Modification 2: `Config` struct (Lines 19-29)
```moonbit
<<<<<<< BEFORE (Lines 19-29)
pub(all) struct Config {
  pub root : String
  pub base_url : String
  pub default_ext : String?
  pub gzip : Bool
  pub brotli : Bool
  pub auto_index : Bool
  pub show_dir : Bool
  pub show_dotfiles : Bool
  pub cache_control : String
}
=======
pub(all) struct Config {
  root : String
  base_url : String
  default_ext : String?
  gzip : Bool
  brotli : Bool
  auto_index : Bool
  show_dir : Bool
  show_dotfiles : Bool
  cache_control : String
}
>>>>>>> AFTER
```

#### Modification 3: `ByteRange` struct (Lines 49-52)
```moonbit
<<<<<<< BEFORE (Lines 49-52)
pub(all) struct ByteRange {
  pub start : Int64
  pub end : Int64
} derive(Eq, Debug)
=======
pub(all) struct ByteRange {
  start : Int64
  end : Int64
} derive(Eq, Debug)
>>>>>>> AFTER
```

#### Modification 4: `normalize_base_url` (Lines 60-65)
```moonbit
<<<<<<< BEFORE (Lines 60-65)
  if value.contains("?") ||
    value.contains("#") ||
    value.contains("\\") ||
    value.contains("\x00") {
    raise ConfigError::InvalidBaseUrl("base_url contains invalid characters")
  }
=======
  if value.contains("?") ||
    value.contains("#") ||
    value.contains("\\") ||
    value.contains("\u0000") {
    raise ConfigError::InvalidBaseUrl("base_url contains invalid characters")
  }
>>>>>>> AFTER
```

#### Modification 5: Add `validate_root` (Insert above `validate_relative_path`, Line 78)
```moonbit
<<<<<<< INSERT AFTER Line 77
///|
/// Validate a filesystem root directory path.
pub fn validate_root(root : String) -> String raise {
  if root == "" || root.contains("\u0000") {
    raise ConfigError::InvalidRoot("root cannot be empty or contain null bytes")
  }
  root
}
>>>>>>>
```

#### Modification 6: `validate_relative_path` (Lines 80-86)
```moonbit
<<<<<<< BEFORE (Lines 80-86)
pub fn validate_relative_path(path : String) -> Bool {
  if path == "" ||
    path[0] == '/' ||
    path.contains("\x00") ||
    path.contains("\\") {
    false
=======
pub fn validate_relative_path(path : String) -> Bool {
  if path == "" ||
    path[0] == '/' ||
    path.contains("\u0000") ||
    path.contains("\\") {
    false
>>>>>>> AFTER
```

---

### 3.2 Target File: `core/core_test.mbt`

Add unit test for `validate_root` and `\u0000` handling at the end of `core/core_test.mbt`:

```moonbit
///|
test "validate root path" {
  assert_eq(validate_root(".") catch { _ => "error" }, ".")
  assert_eq(validate_root("public") catch { _ => "error" }, "public")
  let invalid_empty = try {
    ignore(validate_root(""))
    false
  } catch {
    _ => true
  }
  assert_true(invalid_empty)
  let invalid_nul = try {
    ignore(validate_root("dir\u0000sub"))
    false
  } catch {
    _ => true
  }
  assert_true(invalid_nul)
}
```

---

## 4. Downstream Impact and Coordination

When `core/core.mbt` renames `Request.method` to `Request.meth`, downstream packages must synchronize:

1. **`engine.mbt`**:
   - Line 161: change `request.method is Other(_)` to `request.meth is Other(_)`
   - Line 289: change `request.method is Head` to `request.meth is Head`
2. **`engine_test.mbt`**:
   - Lines 17, 31, 40, 65, 78: change `method: @core.Method::Get` / `Head` to `meth: @core.Method::Get` / `Head`
   *(This also directly resolves 5 `reserved_keyword` compiler warnings in `engine_test.mbt`!)*
3. **`server/server.mbt`**:
   - Line 32: change local variable `let method = ...` to `let meth = ...`
   - Line 41: change `server.engine.handle({ method, ... })` to `server.engine.handle({ meth, ... })`
   *(This also directly resolves 2 `reserved_keyword` compiler warnings in `server.mbt`!)*
4. **Interface Generation**:
   - Run `moon info --target native` to update `core/pkg.generated.mbti`.
   - Run `moon fmt` to ensure clean canonical formatting.

---

## 5. Verification Checklist

- [ ] `moon check -p core --target native` -> **0 warnings, 0 errors**
- [ ] `moon test -p core --target native` -> **All 4 tests pass (100% pass rate)**
- [ ] `moon info --target native` -> `core/pkg.generated.mbti` updated cleanly
- [ ] `moon fmt` -> Zero formatting diffs
- [ ] Full workspace build check: `moon check --target native` (coordinated with `explorer_m1_engine` and `explorer_m1_server_cmd` changes)
