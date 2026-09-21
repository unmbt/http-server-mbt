# Handoff Report: E2E Testing Track Infrastructure & 4-Tier Test Suite Specification

**Agent**: `test_writer_e2e_1`  
**Parent**: `orchestrator_pkg_1` (`4e28988c-0fb8-4c25-808e-968dbd1ae0f2`)  
**Working Directory**: `E:\project\moonbit\unmbt\http-server-mbt\.agents\test_writer_e2e_1`  
**Date**: 2026-09-18  
**Handoff Type**: Hard (Task Complete)  

---

## 1. Observation

1. **Authoritative Mandate**:
   - `E:\project\moonbit\unmbt\http-server-mbt\ORIGINAL_REQUEST.md` (lines 393–452, timestamp `2026-09-18T12:00:00Z`) mandates:
     - R1: Server TLS Decoupling and dependency injection with zero test regression across 183 existing test cases.
     - R2: Dual CLI builds (`thin` rejecting `--cert`, `--key`, `--proxy` with exit code 1; `full` supporting TLS and proxy).
     - R3: C ABI dynamic & static library export pipeline (`hs_*`, no `main`, zero crypto in `thin`).
     - R4: Reverse proxy architecture design and interface readiness (C037~C041 alignment).
2. **Project Structure & Feature Catalog**:
   - `E:\project\moonbit\unmbt\http-server-mbt\.agents\orchestrator_pkg_1\PROJECT.md` (lines 15–34) defines 16 authoritative features across Milestones 1 to 5.
   - `E:\project\moonbit\unmbt\http-server-mbt\.agents\spec_miner_survey_1\spec_report.md` (lines 26–43, 50–71) catalogs 15 discovered features and 21 edge cases with explicit inputs, outputs, and authoritative sources.
3. **Current Test Baseline**:
   - Running `moon test --target native` executes 183 tests:
     ```
     Total tests: 183, passed: 183, failed: 0.
     ```
   - Compilation output during test execution revealed compilation of over 100 MbedTLS C files (e.g. `ssl_tls.c`, `psa_crypto.c`, `aes.c`, `tls_bridge.c`), confirming that the current `server` package directly imports `unmbt/http-server-mbt/tls`.
4. **Fixture Baseline**:
   - `testdata/public/` contains standard static assets, gzip/brotli pre-compressed files, custom 404, and subdirectories.
   - `testdata/tls/` contains `server_cert.pem`, `server_key.pem`, `server_key_enc.pem`, and `other_cert.pem`.

---

## 2. Logic Chain

1. From **Observation 1 & 2**, all 16 features from `PROJECT.md` require rigorous end-to-end testing across 4 tiers:
   - Tier 1: Feature Coverage (>=5 positive/happy-path tests per feature, totaling 80 tests).
   - Tier 2: Boundary & Corner Cases (>=5 edge/boundary/failure tests per feature, totaling 80 tests).
   - Tier 3: Cross-Feature Combinations (pairwise interactions, e.g. Min CLI flag rejection with complex routing, Full CLI TLS with SPA).
   - Tier 4: Real-World Application Scenarios (end-to-end production deployment scenarios).
2. From **Observation 3**, the existing 183 tests provide the regression baseline (`F03`). Because `server` currently references `tls`, decoupling `server` from `tls` via `Acceptor` (`F01`) and injecting `TlsAcceptor` (`F02`) will allow `cmd/http-server-mbt-thin` to compile with zero MbedTLS C files (`F05`, `F11`), while preserving 100% pass rate on existing tests.
3. From **Observation 1 & 2**, `TEST_INFRA.md` was established at the project root (`E:\project\moonbit\unmbt\http-server-mbt\TEST_INFRA.md`) mapping every one of the 16 features to:
   - Explicit test identifiers (`T1-F01-01` ~ `T1-F16-05` for Tier 1, `T2-F01-01` ~ `T2-F16-05` for Tier 2).
   - Specific input conditions and authoritative expected outputs derived from RFC 9110/9112, D-07, D-08, D-11, D-15, D-16, D-20, D-21, and original `http-party/http-server` @ `0d3b7bb5` test cases (C037~C041).
   - Non-deterministic variance handling (regex/structural matching for ephemeral ports and timestamps).
   - 10 Pairwise combinations (`C3-01` ~ `C3-10`) and 5 Real-World scenarios (`S4-01` ~ `S4-05`).
4. To support progressive testability, a comprehensive implementation plan and directory layout was detailed in `test_plan.md`, establishing dual execution runners: native `moon test` for in-memory and package integration, and `.mbtx` scripts (`scripts/run_e2e.mbtx`, `scripts/build_cabi.mbtx`, `scripts/verify_symbols.mbtx`, `scripts/verify_zero_crypto.mbtx`) for external process orchestration and symbol audits.

---

## 3. Caveats

- **Progressive Testability**: Features for Milestones 2 through 5 (`http-server-mbt-thin.exe`, `http-server-full.exe`, C ABI libraries, and reverse proxy data structures) are not yet implemented in code. Their corresponding test files and verification commands are designed in `TEST_INFRA.md` and `test_plan.md` to be implemented progressively as each milestone reaches completion.
- **MSVC Environment Assumption**: The C ABI harness and symbol validation tests (`dumpbin /EXPORTS`) assume a standard Windows MSVC or MinGW toolchain in PATH.

---

## 4. Conclusion

1. `TEST_INFRA.md` has been successfully authored at the project root `E:\project\moonbit\unmbt\http-server-mbt\TEST_INFRA.md`. It provides complete coverage of all 16 features across all 4 tiers (80 Tier 1 tests, 80 Tier 2 tests, 10 Tier 3 combinations, 5 Tier 4 scenarios), with explicit authoritative sources and execution mechanisms.
2. `test_plan.md` has been created in `.agents/test_writer_e2e_1/test_plan.md` detailing runner architectures, directory structures, phased implementation milestones, and fixture invariants.
3. The E2E Testing Track infrastructure is ready for orchestrator integration and progressive implementation.

---

## 5. Verification Method

To independently verify this deliverable:
1. **Inspect Root Infrastructure File**:
   View `E:\project\moonbit\unmbt\http-server-mbt\TEST_INFRA.md` and confirm that all 16 features are mapped with >=5 Tier 1 and >=5 Tier 2 tests, along with Tiers 3 and 4.
2. **Inspect Test Plan Report**:
   View `E:\project\moonbit\unmbt\http-server-mbt\.agents\test_writer_e2e_1\test_plan.md`.
3. **Verify Baseline Test Suite Execution**:
   Run `moon test --target native` at project root to verify all 183 existing tests continue to pass with 0 failures.
