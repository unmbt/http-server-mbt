# Task Assignment: Test Suite Baseline & Requirements Survey

## Context
You are explorer_survey_tests (teamwork_preview_explorer).
Working Directory: D:\project\moonbit\http-server-mbt\.agents\explorer_survey_tests
Project Root: D:\project\moonbit\http-server-mbt
Original User Request: D:\project\moonbit\http-server-mbt\.agents\ORIGINAL_REQUEST.md

## Objective
Investigate the test suite, test cases, and fixtures baseline:
1. Read D:\project\moonbit\http-server-mbt\.agents\ORIGINAL_REQUEST.md and AGENTS.md.
2. Check existing tests across all packages by running `moon test --target native` (or examining all `*_test.mbt` / `*_wbtest.mbt` files).
3. Investigate the test migration matrix from `docs/tasks.md`:
   - Case migration C001~C042 (status, what is implemented, what is missing/failing).
   - Fixture suites CC-01~CC-28, CE-01~CE-02 (where fixtures are located, what fixtures are present vs missing).
   - Any integration / E2E test harness that exists or needs to be built.
   - Verification of Windows IOCP/TransmitFile, handle leak tests, disconnection tests, fault injection tests (D-18).
4. Synthesize all findings in `D:\project\moonbit\http-server-mbt\.agents\explorer_survey_tests\survey_tests_report.md` and complete your handoff.md.

## Communication
When finished, send a message to orchestrator parent with the path to your report.

## 2026-09-11T06:44:38Z
You are explorer_survey_tests. Working directory: D:\project\moonbit\http-server-mbt\.agents\explorer_survey_tests. Read D:\project\moonbit\http-server-mbt\.agents\ORIGINAL_REQUEST.md, AGENTS.md, and your DISPATCH.md. Investigate current tests (`moon test --target native`), C001~C042 cases, CC-01~CC-28 / CE-01~CE-02 fixtures, and test coverage gaps. Write survey_tests_report.md and handoff.md in your working directory. Then send a message to parent with your findings.
