# Handoff Report: Test Suite Baseline & Requirements Survey

**Agent**: `explorer_survey_tests`  
**Working Directory**: `D:\project\moonbit\http-server-mbt\.agents\explorer_survey_tests`  
**Date**: 2026-09-11T06:48:00Z  
**Type**: Hard Handoff (Investigation Complete)  
**Detailed Report**: `D:\project\moonbit\http-server-mbt\.agents\explorer_survey_tests\survey_tests_report.md`

---

## 1. Observation

1. **Test Execution Command & Output**:
   Executed `moon test --target native` at `D:\project\moonbit\http-server-mbt`. Output:
   ```text
   Total tests: 5, passed: 5, failed: 0.
   ```
2. **Existing Test Files & Functions**:
   Only two test files exist across all packages:
   - `core/core_test.mbt:3` (`normalize base url`)
   - `core/core_test.mbt:17` (`relative paths reject traversal`)
   - `core/core_test.mbt:27` (`byte ranges`)
   - `engine_test.mbt:3` (`static get, head and missing`)
   - `engine_test.mbt:51` (`range and conditional request`)
   - `server/server.mbt` has no test file (`server_test.mbt` does not exist).
   - `cmd/http-server-mbt/` has no test file.
3. **Test Data State**:
   - `testdata/public` contains only two files: `hello.txt` (14 bytes) and `index.html` (15 bytes).
   - Full reference test fixtures reside in `http-server/test/public/` (21 directories/files including `brotli`, `gzip`, `charset`, `compress`, `curimit@gmail.com (40%)`, `中文`) and `http-server/test/fixtures/` (`common-cases.js`, `common-cases-error.js`, `https/`, `proxy-all-local/`, `root/`).
4. **C001～C042 Migration Status**:
   `docs/tasks.md` lines 181–237 define 42 test files with subcases C001.01～C042.21. In the target MoonBit codebase:
   - C001 (304), C004 (range), C008/C015 (defaultExt): only minimal subsets tested.
   - C008 (CC-01～CC-28) and C035 (CC-01～CC-28): 0 of 28 common fixtures are tested in MoonBit.
   - C009 & C036 (CE-01～CE-02 error delegation): 0 of 2 tested.
   - Remaining 37 test files (C002, C003, C005～C007, C010～C014, C016～C034, C037～C042) have zero tests in MoonBit.
5. **Windows TransmitFile & Zero-Copy Status**:
   - `engine.mbt:182, 197, 207, 215, 227` reads entire files synchronously into memory as heap `Bytes` via `@fs.read_file(path).binary()`.
   - `server/server.mbt:49` writes `conn.write(response.body)` using standard socket writes.
   - Searching for `TransmitFile` across the codebase and `.mooncakes` yields zero matches. Win32 `TransmitFile` FFI is completely unimplemented.
6. **Compiler Warnings**:
   Running `moon check --target native` outputs:
   ```text
   Finished. moon: ran 7 tasks, now up to date (46 warnings, 0 errors)
   ```
   Comprising 32 reserved keyword warnings (`method`, `use`), 6 deprecated API warnings (`to_bytes`, `Show`, `Map::new`), 3 redundant modifier warnings (`pub` inside `pub struct`), 2 unused enum constructor warnings (`NotFound`, `Closed`), and 3 unused package warnings in `moon.pkg`.

---

## 2. Logic Chain

1. From Observation 1 and 2, MoonBit native tests pass 5 tests, but coverage is restricted to simple unit tests in `core` and in-memory GET/HEAD/Range/ETag checks in `engine_test.mbt`.
2. From Observation 3 and 4, `tasks.md` establishes 42 original test files (C001～C042) and 28 common test fixtures (CC-01～CC-28) as the compatibility baseline (R-COMPAT, R-SDD). Because none of these fixtures are present in `testdata/` and 0 of the 28 common cases are run in MoonBit, the test suite currently satisfies less than 5% of the functional compatibility baseline.
3. From Observation 5, R2 and T-031 explicitly require Windows Native `TransmitFile` zero-copy transfer for static files and ranges, with handle leak verification and cancellation safety. The current engine relies exclusively on full-file heap allocations (`@fs.read_file`), which violates R2 and leaves zero-copy, handle leak, and disconnection unverified.
4. From Observation 6, R3 requires zero compiler warnings (0 warnings, 0 errors). The 46 warnings stem from specific syntax patterns (reserved keywords `method`/`use`, deprecated APIs, redundant `pub`, unused imports/constructors) that must be remediated in the source files and package manifests.
5. Therefore, bringing the project to compliance requires: (a) importing fixture assets into `testdata/fixtures/`; (b) fixing the 46 warnings; (c) implementing the missing engine features (MIME parser, charset detector, directory table renderer, ETag/IMS, SPA/try-files); (d) building an in-memory test runner for CC-01～CC-28; (e) adding TransmitFile FFI with handle leak tests; and (f) creating server TCP and CLI integration test harnesses.

---

## 3. Caveats

1. The reference directory `http-server/` does not contain `node_modules`, so running original Node.js tests directly was not attempted per project policy (`http-server/` is an immutable reference).
2. Network performance and throughput benchmarks (historical P-series) are withdrawn per task T-024 and specification v4; this survey focuses strictly on functional correctness, zero-copy mechanics, and handle safety.
3. POSIX-only filename fixtures (e.g. `<dir>` in C019) cannot be created on Windows NTFS. Per AD-05, Windows tests must verify NUL safety and pure HTML entity escaping rather than physical NTFS directory creation.

---

## 4. Conclusion

The current test suite is a functional skeleton with 5 passing tests, leaving the vast majority of C001～C042 and CC-01～CC-28 unverified. TransmitFile zero-copy transfer and handle leak diagnostics are completely missing.
A structured 7-step testing roadmap is outlined in `survey_tests_report.md` to guide the engineering agents through fixture consolidation, warning remediation, in-memory CC-01～CC-28 testing, Windows zero-copy testing, and E2E integration verification.

---

## 5. Verification Method

To independently verify all claims made in this report:

1. **Verify Test Execution**:
   Run `moon test --target native` in PowerShell at `D:\project\moonbit\http-server-mbt`. Confirm exactly 5 tests execute and pass:
   - 3 in `core/core_test.mbt`
   - 2 in `engine_test.mbt`
2. **Verify Compiler Warnings**:
   Run `moon check --target native`. Confirm the compiler reports exactly 46 warnings and 0 errors.
3. **Verify Fixture Absence**:
   Inspect `testdata/public`. Confirm only `hello.txt` and `index.html` exist.
   Inspect `http-server/test/public` and `http-server/test/fixtures/common-cases.js`. Confirm the presence of the 28 common fixtures and 42 reference test files.
4. **Verify TransmitFile Absence**:
   Search for `TransmitFile` in `engine.mbt` and `server/server.mbt`. Confirm file responses are generated by loading full file bytes into memory via `@fs.read_file()`.
