# Milestone 1 Adversarial Challenge Report: Transport Abstraction & PlainAcceptor

**Agent**: `challenger_m1_1` (Challenger 1)  
**Role**: critic, specialist  
**Date**: 2026-09-18T12:48:00Z  
**Verdict**: **REJECT** (Blocked by preflight validation bypass in `full/full.mbt` causing `moon test --target native` failures)

---

## Challenge Summary

**Overall risk assessment**: **HIGH**

While the core `Transport` abstraction and `PlainAcceptor` implementation in the `server` package are empirically sound, robust, leak-free, and pass all adversarial stress tests (95/95 passed in `server`), the repository-wide gate `moon test --target native` fails with exit code 1 (3 test failures in `full/`). Specifically, `full.with_server_at` invokes `build_tls_acceptor` before `@server.with_server_at` without first calling `@core.validate_tls(config)`, violating the D-01 preflight configuration error contract.

---

## Stress Test Suite Execution (`server/server_challenger_m1_test.mbt`)

Challenger 1 designed and executed 6 empirical adversarial stress tests covering concurrency, rapid churn, zero-copy vs streaming fallback equivalence, abrupt disconnects, error handling, and handle leak auditing:

| Test Name | Challenge Vector | Expected Result | Actual Result | Status |
|-----------|------------------|-----------------|---------------|--------|
| `20 concurrent requests & 50 rapid connection churns on PlainAcceptor` | 50 rapid open/closes + 20 concurrent tasks requesting full files and ranges | All 20 succeed (200/206), server stays responsive | All 20 succeeded with exact expected payloads | **PASS** |
| `TransmitFile zero-copy vs bounded buffer streaming byte-for-byte equivalence` | 150KB multi-chunk file (Chunk 1: 64KB, Chunk 2: 64KB, Chunk 3: 22KB) compared across `raw_fd: Some` vs `raw_fd: None` | Exact byte-for-byte match on full file (150,000B), cross-chunk boundary (5,001B), and tail (1,000B) | Zero-copy and streaming fallback produced identical byte streams matching original data | **PASS** |
| `Abrupt client disconnect during bounded-buffer streaming does not leak or deadlock` | 5 consecutive clients connect for 300KB file, read 8KB, and abruptly close socket mid-stream | Server detects write failure, clears active requests, serves next request normally | Server remained active; subsequent GET /hello.txt returned 200 with complete body | **PASS** |
| `Failing Acceptor::accept closes socket cleanly without server crash or handle leak` | Mock acceptor raising `@core.ConfigError::InvalidTls` during `accept` for 10 clients | `handle_connection` catches exception, closes socket, avoids leak | 10 sockets cleanly closed on client side; handle count delta = 0 | **PASS** |
| `Transport::close lifecycle tracking executes exactly once per connection` | Tracking acceptor recording `close_fn` invocations across 10 requests | `close_fn` invoked exactly once per completed connection | Counter = 10; no double-close or leaked connections | **PASS** |
| `Process handle count audit shows 0 handle leaks across 80 mixed requests` | 80 mixed requests (full file, range, 404, abrupt connect/close) sampled via `handle_leak_baseline()` | Final handle count returns to baseline within tolerance | 0 permanent handle leaks observed | **PASS** |

Package-level verification for `server`:
```powershell
moon test --target native -p unmbt/http-server-mbt/server
# Output: Total tests: 95, passed: 95, failed: 0.
```

---

## Challenges & Identified Defects

### [High] Challenge 1: `full.with_server_at` Bypasses D-01 TLS Pairing Validation

- **Assumption challenged**: Worker assumed `build_tls_acceptor(config)` handles invalid TLS configurations correctly according to D-01 preflight contracts.
- **Attack scenario**: When a user configures `cert_file: Some(...)` with `key_file: None`, or `key_file: Some(...)` with `cert_file: None`, `full.with_server_at` executes:
  ```moonbit
  // full/full.mbt:10-15
  let acceptor : &@server.Acceptor? = if config.has_tls() {
    let tls_acc = build_tls_acceptor(config)
    Some(TlsServerAcceptor::new(tls_acc))
  } else {
    None
  }
  @server.with_server_at(config, port, acceptor?, action)
  ```
  Because `config.has_tls()` evaluates to `true` when either cert or key is set, it directly calls `build_tls_acceptor(config)`. In `full/tls_acceptor.mbt`:
  ```moonbit
  let cert_path = match config.cert_file { Some(p) => p, None => "" }
  let key_path = match config.key_file { Some(p) => p, None => "" }
  let cert = @fs.read_file(cert_path).binary() catch { ... }
  let key = @fs.read_file(key_path).binary() catch { ... }
  ```
  It attempts to read `""` from disk and fails with `"cannot read key_file : ..."` or `"cannot read cert_file : ..."`. The required D-01 preflight error `"cert_file requires key_file to be set"` or `"key_file requires cert_file to be set"` from `@core.validate_tls(config)` is never reached because `@server.with_server_at` is only invoked after `build_tls_acceptor`.
- **Blast radius**: Breaks D-01 preflight error diagnostics in full HTTPS mode; causes `moon test --target native` to fail.
- **Reproducing test cases**:
  - `full challenger m1-2: preflight rejects missing key when cert is present in full` (FAILED)
  - `full challenger m1-2: preflight rejects missing cert when key is present in full` (FAILED)
- **Mitigation**: In `full/full.mbt`, add `@core.validate_tls(config)` at the beginning of `with_server_at` before checking `config.has_tls()`.

### [Medium] Challenge 2: Snapshot Handle Count Assertion Flakiness Under Parallel Test Execution

- **Assumption challenged**: Worker/peer assumed instantaneous `assert_eq(@server.get_handle_count(), h_before)` is stable across full test runs.
- **Attack scenario**: In `full/full_challenger_m1_2_test.mbt` line 194:
  `assert_eq(h_after, h_before)` compares raw handle counts without waiting or using a quiescence window. When `moon test --target native` executes all packages in parallel, background tasks and sibling test threads concurrently open and close handles, leading to transient noise (`158 != 163`).
- **Blast radius**: Intermittent test failure in CI / test runner when multiple tests execute concurrently.
- **Mitigation**: Adopt the standard `handle_leak_baseline()` and `assert_no_handle_leak(baseline)` helpers established in `server/handle_leak_assert_test.mbt`.

---

## Build & Test Quality Gate Results

1. **Compiler Check**:
   ```powershell
   moon check --target native
   ```
   *Result*: **PASS** (`Finished. moon: no work to do (0 warnings, 0 errors)`).

2. **Full Test Suite**:
   ```powershell
   moon test --target native
   ```
   *Result*: **FAIL** (`Total tests: 216, passed: 213, failed: 3`).
   - `full/full_challenger_m1_2_test.mbt:26`: FAILED
   - `full/full_challenger_m1_2_test.mbt:46`: FAILED
   - `full/full_challenger_m1_2_test.mbt:148`: FAILED (due to parallel test interference)

---

## Unchallenged Areas

- **C ABI library exports (`c_abi/`)**: Scheduled for Milestone 3 per `PROJECT.md`.
- **Reverse Proxy forwarding state machine**: Scheduled for Milestone 4 per `PROJECT.md`.
- **Dedicated CLI binaries (`cmd/http-server-min` & `cmd/http-server-full`)**: Scheduled for Milestone 2 per `PROJECT.md`.

---

## Final Verdict

**REJECT**

Although the `Transport` abstraction and `PlainAcceptor` pass all empirical stress and leak assertions, the workspace fails the required quality gate `moon test --target native` due to the missing preflight validation in `full/full.mbt`. A targeted fix by the worker is required before Milestone 1 can be certified.
