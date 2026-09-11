# Handoff Report: M1 Core Package Compiler Warnings Remediation

## 1. Observation
- Tool execution `moon check -p core --target native` in `D:\project\moonbit\http-server-mbt` produces 18 warnings and 0 errors:
  1. `core/core.mbt:12:3`: `Warning [0008] (redundant_modifier): The public modifier is redundant here since field method is public by default`
  2. `core/core.mbt:12:7`: `Warning [0035] (reserved_keyword): The word method is reserved for possible future use. Please consider using another name.`
  3. `core/core.mbt:13:3`: `Warning [0008] (redundant_modifier): The public modifier is redundant here since field target is public by default`
  4. `core/core.mbt:14:3`: `Warning [0008] (redundant_modifier): The public modifier is redundant here since field headers is public by default`
  5. `core/core.mbt:20:3`: `Warning [0008] (redundant_modifier): The public modifier is redundant here since field root is public by default`
  6. `core/core.mbt:21:3`: `Warning [0008] (redundant_modifier): The public modifier is redundant here since field base_url is public by default`
  7. `core/core.mbt:22:3`: `Warning [0008] (redundant_modifier): The public modifier is redundant here since field default_ext is public by default`
  8. `core/core.mbt:23:3`: `Warning [0008] (redundant_modifier): The public modifier is redundant here since field gzip is public by default`
  9. `core/core.mbt:24:3`: `Warning [0008] (redundant_modifier): The public modifier is redundant here since field brotli is public by default`
  10. `core/core.mbt:25:3`: `Warning [0008] (redundant_modifier): The public modifier is redundant here since field auto_index is public by default`
  11. `core/core.mbt:26:3`: `Warning [0008] (redundant_modifier): The public modifier is redundant here since field show_dir is public by default`
  12. `core/core.mbt:27:3`: `Warning [0008] (redundant_modifier): The public modifier is redundant here since field show_dotfiles is public by default`
  13. `core/core.mbt:28:3`: `Warning [0008] (redundant_modifier): The public modifier is redundant here since field cache_control is public by default`
  14. `core/core.mbt:50:3`: `Warning [0008] (redundant_modifier): The public modifier is redundant here since field start is public by default`
  15. `core/core.mbt:51:3`: `Warning [0008] (redundant_modifier): The public modifier is redundant here since field end is public by default`
  16. `core/core.mbt:63:21`: `Warning [0027] (deprecated_syntax): The syntax \x.. in string literal for type String is deprecated. Use \u.. instead.`
  17. `core/core.mbt:83:20`: `Warning [0027] (deprecated_syntax): The syntax \x.. in string literal for type String is deprecated. Use \u.. instead.`
  18. `core/core.mbt:141:3`: `Warning [0006] (unused_constructor): Variant 'InvalidRoot' is never constructed`
- `core/core_test.mbt` execution via `moon test -p core --target native` passes 3 of 3 tests with 0 failures and 0 warnings.
- `core/moon.pkg` contains only `"moonbitlang/core/string"`, with 0 unused package warnings.
- Grep search for `Request.method` references across the repository found:
  - `engine.mbt:161`: `if request.method is Other(_) {`
  - `engine.mbt:289`: `if request.method is Head {`
  - `engine_test.mbt:17, 31, 40, 65, 78`: `method: @core.Method::...` (which currently causes 5 separate `reserved_keyword` warnings in `engine_test.mbt`)
  - `server/server.mbt:32, 41`: mapping `request.meth` to local `method` and passing `{ method, ... }` to engine handle.
- Contract in `PROJECT.md` line 57 explicitly specifies: `core.Request: Represents normalized HTTP request (meth: Method, url: String, headers: Map[String, String], etc.)`.

## 2. Logic Chain
- Step 1: In MoonBit, `pub(all) struct` already exports all struct fields as public (Observation 1: items 1, 3-15). Therefore, the `pub` keyword before struct fields in `Request` (3 fields), `Config` (9 fields), and `ByteRange` (2 fields) is redundant. Removing these 14 occurrences directly eliminates 14 `redundant_modifier` warnings without altering interface visibility or `.mbti`.
- Step 2: The identifier `method` is a reserved keyword (Observation 1: item 2). Renaming field `Request.method` to `Request.meth` eliminates warning `[0035]` in `core/core.mbt`, satisfies the `PROJECT.md` specification (`meth: Method`), and simultaneously eliminates 5 `reserved_keyword` warnings in `engine_test.mbt` (Observation 4).
- Step 3: The escape sequence `\x00` is deprecated in MoonBit string literals in favor of 4-digit unicode escape `\u0000` (Observation 1: items 16, 17). Replacing `\x00` with `\u0000` in `normalize_base_url` (line 63) and `validate_relative_path` (line 83) preserves exact NUL byte semantics while eliminating both `deprecated_syntax` warnings.
- Step 4: `ConfigError::InvalidRoot(String)` is declared in `core/core.mbt:141` but never constructed (Observation 1: item 18). `docs/design.md` requires pre-listen configuration checks where root errors reject before socket binding. Introducing a canonical `validate_root(root : String) -> String raise` function that checks for empty strings and NUL bytes and raises `ConfigError::InvalidRoot` eliminates warning `[0006]`, preserves `InvalidRoot` in `core/pkg.generated.mbti`, and provides root pre-validation.
- Step 5: Adding unit tests for `validate_root` in `core/core_test.mbt` verifies that `validate_root(".")` and `validate_root("public")` succeed while `validate_root("")` and `validate_root("dir\u0000sub")` raise `ConfigError::InvalidRoot`.
- Step 6: After applying these changes, `core/` will have 0 errors and 0 warnings under `moon check -p core --target native`, and 4 passing tests under `moon test -p core --target native`.

## 3. Caveats
- Renaming `Request.method` to `Request.meth` requires synchronized updates in downstream callers (`engine.mbt` lines 161, 289, `engine_test.mbt` lines 17, 31, 40, 65, 78, and `server/server.mbt` lines 32, 41). This has been coordinated with the assigned explorers `explorer_m1_engine` and `explorer_m1_server_cmd`.
- `validate_root` does not perform filesystem I/O (such as checking if the directory exists on disk), maintaining `core`'s strict architectural boundary of zero platform I/O dependencies (`PROJECT.md` line 5). Filesystem existence checks remain the responsibility of `engine` / `server`.

## 4. Conclusion
All 18 compiler warnings in `core/core.mbt` are completely categorized, root causes identified, and exact line-by-line remediations formulated in `strategy.md`.
Implementing the strategy will bring `core` to 0 compiler warnings and 0 compiler errors while improving standard compliance, eliminating downstream warnings in `engine_test.mbt`, and honoring all architectural contracts.

## 5. Verification Method
1. Execute `moon check -p core --target native` -> Expected result: `Finished. moon: ran 2 tasks, now up to date (0 warnings, 0 errors)`.
2. Execute `moon test -p core --target native` -> Expected result: `Total tests: 4, passed: 4, failed: 0`.
3. Execute `moon info --target native` and inspect `core/pkg.generated.mbti` diff -> Expected diff: `meth : Method` and `pub fn validate_root(String) -> String raise`.
4. Invalidation condition: Any warning code `[0008]`, `[0035]`, `[0027]`, or `[0006]` remaining after remediation.
