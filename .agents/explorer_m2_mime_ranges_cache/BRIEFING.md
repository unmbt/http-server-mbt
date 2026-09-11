# BRIEFING — 2026-09-11T07:25:30Z

## Mission
Design exact architecture and implementation strategy in core/ for MIME types registry, .types parser, default extension, ETag strong/weak, If-None-Match/If-Modified-Since, Range parsing (206/416), and Cache-Control.

## 🔒 My Identity
- Archetype: Teamwork explorer
- Roles: Investigation, architecture design, strategy synthesis
- Working directory: D:\project\moonbit\http-server-mbt\.agents\explorer_m2_mime_ranges_cache
- Original parent: c9a1c62c-d24a-4e26-aba4-e472238529d1
- Milestone: M2 (Core Protocols, MIME, Security & Config)

## 🔒 Key Constraints
- Read-only investigation — do NOT edit source code files
- Pure logic library in core/ with strictly zero platform I/O dependencies (portable Native / wasm-gc)
- 0 warnings, 0 errors, block-style MoonBit code
- Compatible with original http-server (0d3b7bb) and D-01/D-03/D-04/D-17 specifications

## Current Parent
- Conversation ID: c9a1c62c-d24a-4e26-aba4-e472238529d1
- Updated: 2026-09-11T07:25:30Z

## Investigation State
- **Explored paths**: `ORIGINAL_REQUEST.md`, `AGENTS.md`, `PROJECT.md`, `docs/design.md`, `docs/tasks.md`, `core/core.mbt`, `core/core_test.mbt`, `engine.mbt`, `engine_test.mbt`, `http-server/lib/core/index.js`, `opts.js`, `etag.js`, `http-server/test/304.test.js`, `cache.test.js`, `range.test.js`, `mime.test.js`, `content-type.test.js`, `custom-content-type*.test.js`, `illegal-access-date.test.js`, `public/charset/arabic.html`, `public/charset/shift_jis.html`
- **Key findings**:
  1. MIME: Standard table of 60+ extensions; case-insensitive lookup supporting bare extensions (`htm`) and leading dots (`.TXT`); Apache `.types` parser; charset sniffing <= 1024 bytes supporting UTF-8 BOM, ISO-8859-6, Shift_JIS with WHATWG canonical normalization; binary formats (`application/wasm`) omit charset.
  2. Default extension: path vs query separation; terminal component extension detection; stripping leading dots; completion to `.html`.
  3. ETag & Cache: `EntityTag` strong (`"..."`) and weak (`W/"..."`); weak comparison matches opaque tags; strong comparison requires neither to be weak; pure HTTP-date parser handling IMF-fixdate, RFC 850, asctime, JS `(new Date()).toString()`, ISO 8601, and returning `None` on illegal dates (C003 `275760-09-24`); 304 decision checks both IMS and INM; Cache-Control converts seconds to `max-age=...` and `-1` to `no-cache, no-store, must-revalidate`.
  4. Range: RFC 7233 & ecstatic bare `start-end`, prefix `start-`, suffix `-len`; 416 on inverted (`333-222`), out of bounds (`start >= total`), NaN, empty file; Content-Range `bytes start-end/total` and `bytes */total`; GET Range evaluated prior to 304 conditional cache.
- **Unexplored areas**: None within the M2 MIME, Range, Cache scope.

## Key Decisions Made
- `core/` keeps strictly zero platform I/O dependencies.
- Modularized into `core/mime.mbt`, `core/extension.mbt`, `core/cache.mbt`, `core/range.mbt`.
- Strategy documented in `strategy.md`.

## Artifact Index
- `strategy.md` — Complete architecture & implementation strategy
- `handoff.md` — 5-component handoff report
