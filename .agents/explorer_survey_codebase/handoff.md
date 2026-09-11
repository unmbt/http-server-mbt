# Handoff Report: Codebase & Compiler Warnings Survey

**Agent**: `explorer_survey_codebase`  
**Date**: 2026-09-11  
**Handoff Type**: Hard (Task complete)  
**Report Artifact**: `D:\project\moonbit\http-server-mbt\.agents\explorer_survey_codebase\survey_codebase_report.md`

---

## 1. Observation

1. **Compiler Diagnostics**:
   Command: `moon check --target native`
   Output result:
   ```text
   Finished. moon: ran 7 tasks, now up to date (46 warnings, 0 errors)
   ```
   All 46 warnings captured verbatim in `.agents\explorer_survey_codebase\moon_check_output.txt`.
   The warnings break down into 7 categories:
   - `redundant_modifier` (17 warnings): `core\core.mbt:12,13,14,20-28,50,51`, `engine.mbt:28,29,30`.
     Example verbatim snippet:
     ```text
     Warning: [0008]
         ╭─[ D:\project\moonbit\http-server-mbt\core\core.mbt:12:3 ]
         │
      12 │   pub method : Method
         │   ─┬─  
         │    ╰─── Warning (redundant_modifier): The public modifier is redundant here since field method is public by default
     ────╯
     ```
   - `reserved_keyword` (14 warnings): `method` in `core\core.mbt:12`, `engine_test.mbt:17,31,40,65,78`, `server\server.mbt:32,41`; `use` in `engine.mbt:11,14`, `server\server.mbt:12,14,24,30`.
     Example verbatim snippet:
     ```text
     Warning: [0035]
         ╭─[ D:\project\moonbit\http-server-mbt\core\core.mbt:12:7 ]
         │
      12 │   pub method : Method
         │       ───┬──  
         │          ╰──── Warning (reserved_keyword): The word `method` is reserved for possible future use. Please consider using another name.
     ────╯
     ```
   - `deprecated` (6 warnings):
     - `engine.mbt:244`: `html.to_bytes()` -> `@encoding/utf8.encode`
     - `engine.mbt:270`: `body[...].to_bytes()` -> `to_owned` on `BytesView`
     - `engine.mbt:304`: `text.to_bytes()` -> `@encoding/utf8.encode`
     - `server\server.mbt:35`: `request.meth.to_string()` -> `@debug.to_string`
     - `server\server.mbt:37,44`: `Map::new()` -> `Map([], capacity=...)` or `Map([])`
   - `unused_constructor` (3 warnings): `InvalidRoot(String)` in `core\core.mbt:141`; `NotFound` in `engine.mbt:62`; `Closed` in `engine.mbt:64`.
   - `unused_package` (3 warnings): `moon.pkg:2` (`moonbitlang/async`), `moon.pkg:4` (`moonbitlang/async/http`), `server\moon.pkg:4` (`moonbitlang/async`).
   - `deprecated_syntax` (2 warnings): `core\core.mbt:63,83`: `contains("\x00")` -> use `\u0000`.
   - `unused_async` (1 warning): `cmd\http-server-mbt\main.mbt:103`: `async fn(_server)`.

2. **Test Diagnostics**:
   Command: `moon test --target native`
   Output result:
   ```text
   Total tests: 5, passed: 5, failed: 0.
   ```
   Tests consist of 3 tests in `core/core_test.mbt` ("normalize base url", "relative paths reject traversal", "byte ranges") and 2 tests in `engine_test.mbt` ("static get, head and missing", "range and conditional request").

3. **Package & Layout Structure**:
   `moon.mod` defines module `unmbt/http-server-mbt@0.1.5` with dependency `"moonbitlang/async@0.21.3"`.
   4 packages exist:
   - Root (`.`): `engine.mbt`, `engine_test.mbt`
   - `core`: `core.mbt`, `core_test.mbt`
   - `server`: `server.mbt`
   - `cmd/http-server-mbt`: `main.mbt` (executable)

4. **Codebase Implementation Status vs. Requirements (R1-R4)**:
   - Static I/O in `engine.mbt` reads entire files into memory via `@fs.read_file(path).binary()`.
   - Windows zero-copy (`TransmitFile` / IOCP) is completely absent.
   - SPA (`--spa`) and single-file fallback (`--try-files`) are completely absent from `Config`, `engine.mbt`, and `cmd`.
   - Security: Basic Auth, CORS, COOP, PNA headers are completely absent. Path traversal only guards against `..` and `\` without handle-anchored root validation or symlink traversal checks.
   - MIME: hardcoded to 6 file extensions; no custom MIME or `.types` file parsing.

5. **Licenses**:
   - `LICENSE` in project root: MIT License (Copyright 2026 UnMoonBit).
   - `.mooncakes/moonbitlang/async/LICENSE`: Apache License 2.0.
   - `http-server/LICENSE` (reference upstream): MIT License (Copyright 2011-2026 Charlie Robbins et al.).
   - Standard library `moonbitlang/core`: Apache-2.0.

---

## 2. Logic Chain

1. From Observation 1: The compiler outputs 46 warnings with exit code 0. Every warning is traced to an exact line and character position. Fixing them requires systematic edits (stripping redundant `pub`, renaming identifiers `method` -> `meth` and `use` -> `handler`, replacing deprecated byte conversion and map constructors, updating escape sequences to `\u0000`, removing unused package imports from `moon.pkg`, and adjusting the async callback).
2. From Observation 2: The test suite has 5 passing tests, confirming that the current rudimentary engine and core compile and run natively on Windows x86_64. However, test coverage is minimal and does not yet cover the 42 migration test files or CC fixtures.
3. From Observation 3 and 4: The existing architecture is an initial baseline. To fulfill R1 and R2, the engine cannot rely on synchronous `read_file` memory buffers; it must integrate with Windows IOCP and `TransmitFile` (T-031), while routing logic must be expanded for BaseURL, SPA, and try-files (T-019).
4. From Observation 5: All components strictly adhere to the user's licensing constraints ("MIT, Apache-2.0, BSD-3-Clause"). There are no restrictive or incompatible copyleft licenses present.

---

## 3. Caveats

1. **CodeGraph Exploration**: `.codegraph` directory is not present at the repository root, so CodeGraph indexing was bypassed in accordance with the user instructions.
2. **C ABI Export**: As noted in `docs/design.md` D-11 and `docs/windows-baseline.md`, Native library generation (`.a`, `.lib`, `.dll`) requires toolchain verification under T-002; the current survey audited the existing MoonBit source packages and did not test external C linkage.
3. **Reference Repo Execution**: The local reference checkout `http-server/` does not have `node_modules` installed, so upstream JavaScript tests were not executed locally; migration baselines rely on the documented fixtures and test files.

---

## 4. Conclusion

1. **Zero Warnings Target is Ready for Refactoring**: All 46 compiler warnings have been cataloged with precise line locations and remediation steps. None require architectural rewrites; they can be eliminated cleanly in a focused refactoring step.
2. **Architecture Baseline Established**: The 4-package layout (`cmd`, `server`, `core`, and root engine) provides a clean starting structure, but `core.Config` and `engine.mbt` need substantial feature additions to support SPA/try-files, full HTTP compliance, and Windows IOCP/TransmitFile zero-copy transmission.
3. **Licensing Verified**: Full compliance with commercial-friendly permissive licenses (MIT and Apache-2.0).

---

## 5. Verification Method

To independently verify these findings on Windows Native:

1. **Verify Compiler Warnings (46 warnings)**:
   ```powershell
   moon check --target native
   ```
   *Expected result*: `Finished. moon: ran 7 tasks, now up to date (46 warnings, 0 errors)`
   *Invalidation condition*: Any count other than 46 warnings or any compiler error.

2. **Verify Native Tests (5 passed)**:
   ```powershell
   moon test --target native
   ```
   *Expected result*: `Total tests: 5, passed: 5, failed: 0.`

3. **Verify License Files**:
   Inspect `LICENSE`, `.mooncakes/moonbitlang/async/LICENSE`, and `http-server/LICENSE`.
