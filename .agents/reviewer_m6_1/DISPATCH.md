1: # DISPATCH — reviewer_m6_1
2: 
3: ## Identity
4: - Name: reviewer_m6_1
5: - Role: teamwork_preview_reviewer
6: - Working Directory: E:\project\moonbit\unmbt\http-server-mbt\.agents\reviewer_m6_1
7: - Parent: orchestrator_m6_gen2
8: - Parent Conv ID: dcf6fc8a-69f5-4537-8275-a1f2ab70f9af
9: 
10: ## Mission
11: Phase 2: Reviewer Quality & Contract Review (R2) for Milestone 6.
12: You MUST read:
13: - ORIGINAL_REQUEST.md at E:\project\moonbit\unmbt\http-server-mbt\ORIGINAL_REQUEST.md
14: - docs/design.md (D-01~D-18 and AD-01~AD-10 difference records)
15: - docs/tasks.md (migration matrix C001~C042, CC-01~CC-28, CE-01~CE-02, T-034)
16: - Current codebase in server/, core/, engine/, cmd/
17: 
18: Review scope:
19: 1. Verify contract adherence to D-01~D-18 and AD-01~AD-10 (especially AD-05 Windows path constraints, AD-03 timeout units, AD-07 WebSocket startup validation, AD-09 proxy exclusivity).
20: 2. Verify all 42 C-cases, CC-cases, CE-cases, E2E tests, fault injection tests pass and have proper assertions without shortcuts or fake passes.
21: 3. Run `moon check --target native` and `moon test --target native` to independently verify.
22: 4. Output detailed handoff.md with a clear verdict: APPROVE or REQUEST_CHANGES.
23: 
24: ## 2026-09-12T02:20:35Z
25: You are reviewer_m6_1.
26: Your working directory is: E:\project\moonbit\unmbt\http-server-mbt\.agents\reviewer_m6_1
27: Your DISPATCH file is: E:\project\moonbit\unmbt\http-server-mbt\.agents\reviewer_m6_1\DISPATCH.md
28: Your parent is orchestrator_m6_gen2 (conv ID: dcf6fc8a-69f5-4537-8275-a1f2ab70f9af).
29: 
30: You MUST read ORIGINAL_REQUEST.md at: E:\project\moonbit\unmbt\http-server-mbt\ORIGINAL_REQUEST.md before starting.
31: Also review `docs/design.md` (D-01~D-18 and AD-01~AD-10) and `docs/tasks.md`.
32: 
33: Review Objectives:
34: 1. Verify contract adherence to D-01~D-18 and AD-01~AD-10 (especially AD-05 Windows path constraints, AD-03 timeout units, AD-07 WebSocket startup validation, AD-09 proxy exclusivity).
35: 2. Check C001~C042, CC-01~CC-28, CE-01~CE-02 in `server/c_suite_*.mbt`, `server/server_e2e_client_test.mbt`, and `server/server_fault_injection_test.mbt`.
36: 3. Verify that tests are authentic, comprehensive, and have genuine assertions.
37: 4. Run `moon check --target native` and `moon test --target native` to independently verify.
38: 5. Write your handoff report to `E:\project\moonbit\unmbt\http-server-mbt\.agents\reviewer_m6_1\handoff.md` with an explicit verdict: APPROVE or REQUEST_CHANGES.
39: 6. Send a message to parent with your verdict and handoff summary.

