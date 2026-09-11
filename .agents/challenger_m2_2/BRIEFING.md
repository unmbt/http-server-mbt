# BRIEFING — 2026-09-11T07:39:00Z

## Mission
Adversarially challenge M2 security (path traversal, NUL bytes, ADS, devices), constant-time Basic Auth, and RFC 7233 range 416 errors.

## 🔒 My Identity
- Archetype: challenger
- Roles: critic, specialist
- Working directory: D:\project\moonbit\http-server-mbt\.agents\challenger_m2_2
- Original parent: c9a1c62c-d24a-4e26-aba4-e472238529d1
- Milestone: M2
- Instance: 2 of 2

## 🔒 Key Constraints
- Review-only — do NOT modify implementation code
- Report findings and verdict: APPROVE or REQUEST_CHANGES
- Empirical challenger: must write and execute verification code/tests; do not trust claims without empirical reproduction

## Current Parent
- Conversation ID: c9a1c62c-d24a-4e26-aba4-e472238529d1
- Updated: not yet

## Review Scope
- **Files to review**: `core/security.mbt`, `core/range.mbt`, `core/config.mbt`, `core/core_test.mbt`
- **Interface contracts**: `docs/proposal.md`, `docs/design.md`, `docs/tasks.md`
- **Review criteria**: Adversarial probing of path traversal (.., \u0000, ADS, Windows devices), root prefix collisions, constant-time Basic Auth error handling, RFC 7233 range 416 errors.

## Key Decisions Made
- Executed empirical adversarial challenge suite in `core/security_auth_range_adversarial_test.mbt` covering path traversal, root boundary escapes, BaseURL collision attacks, Basic Auth timing safety, and RFC 7233 Range 416 conformance.
- Verdict: APPROVE. Core defenses are robust and pass all 30 tests (0 warnings, 0 errors).
- Documented three minor defense-in-depth edge cases (CONIN$/CONOUT$ console devices, trailing space canonicalization, and UTF-8 surrogate halves).

## Artifact Index
- DISPATCH.md — Assignment instructions
- progress.md — Liveness heartbeat and progress tracking
- handoff.md — Final adversarial evaluation report
- `core/security_auth_range_adversarial_test.mbt` — Empirical adversarial challenge suite (co-located per layout rules)

## Attack Surface
- **Hypotheses tested**:
  - Path traversal bypass via `..`, `../`, `..\\`, `\`, NUL, ADS (`file.txt::$DATA`), Windows devices (`CON`, `PRN`, `AUX`, `NUL`, `COM1-9`, `LPT1-9`) -> BLOCKED.
  - Root prefix collision bypass (`root: "public"`, target: `"public-secret/passwords.txt"`) -> ANCHORED INSIDE ROOT.
  - BaseURL prefix collision (`/app` vs `/application`) -> REJECTED with `OutsideBaseUrl` (403 empty body).
  - Basic Auth error handling on malformed headers, wrong scheme, invalid base64, missing colon -> FAILS GRACEFULLY.
  - Basic Auth constant-time comparison -> TIMING SAFE (uniform loop iterations, dummy fallbacks, non-short-circuiting evaluation).
  - Range parsing on inverted ranges (`333-222`), non-numeric (`abc-def`), out-of-bounds start (`500-`), zero-length files -> RETURN 416 NotSatisfiable.
  - Suffix range clamping and prefix range EOF clamping -> FULLY COMPLIANT.
- **Vulnerabilities found**:
  - [Low / Edge Case] `is_windows_reserved_name` does not check `CONIN$` and `CONOUT$`.
  - [Low / Edge Case] `is_windows_reserved_name` does not strip trailing spaces before comparing DOS device names (e.g. `"CON "`).
  - [Low / Edge Case] `decode_utf8_bytes` emits isolated surrogate halves `0xD800..0xDFFF` via `unsafe_to_char` on `%ED%A0%80`.
- **Untested angles**:
  - Runtime TransmitFile streaming integration with IOCP (deferred to M3/T-031).

## Loaded Skills
- None
