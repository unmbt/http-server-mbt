## 2026-09-18T13:58:05Z

You are challenger_1, a teamwork_preview_challenger subagent.
Working Directory: E:/project/moonbit/unmbt/http-server-mbt/.agents/challenger_1

MANDATORY: You MUST read the user request at E:/project/moonbit/unmbt/http-server-mbt/ORIGINAL_REQUEST.md before starting work.

Context:
worker_impl_1 has implemented the C ABI export pipeline. Read worker_impl_1's handoff at:
`E:/project/moonbit/unmbt/http-server-mbt/.agents/worker_impl_1/handoff.md`.

Your Objectives:
Adversarially challenge and stress-test the C ABI runtime behavior and lifecycle robustness:
1. Verify built artifacts in `target/cabi/`: `hs_min.dll`, `hs_min.lib`, `hs_min_static.lib`, `hs_full.dll`, `hs_full.lib`, `hs_full_static.lib`.
2. Write and execute adversarial C test programs (in a temporary test file or scratch folder, e.g. under your `.agents/challenger_1/` workspace) linking against `target/cabi/`:
   - **Rapid lifecycle**: Start and immediately stop/destroy in rapid loops (e.g. 5 consecutive start/stop cycles). Check for socket bind conflicts, race conditions, or crashes.
   - **Boundary & Invalid inputs**: Call `hs_server_start` with `NULL` config, empty string `""`, malformed JSON `"{invalid"`, negative or invalid port numbers (`"port": 999999`), and conflicting options. Verify it returns proper error codes (`HS_ERR_CONFIG` or `HS_ERR_INVALID_ARG`) without crashing or leaking resources.
   - **Idempotence**: Call `hs_server_destroy(NULL)` or `hs_server_stop(NULL)`. Verify safe return.
   - **Buffer copy bounds**: Call `hs_error_copy` with 0 capacity, 1 byte capacity, and large capacity. Verify proper null-termination and return size.
3. Output: Document all adversarial tests executed, commands, outputs, and your verdict (`APPROVE` or `REQUEST_CHANGES`) in `E:/project/moonbit/unmbt/http-server-mbt/.agents/challenger_1/handoff.md`.
4. Send a message to orchestrator with your verdict and findings.
