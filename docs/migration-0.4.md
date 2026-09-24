# MoonBit 0.4 API migration (candidate)

R-N06/R-N15, D-07/D-14/D-17, T-015/T-030/T-033. This is the next minor-release contract; it does not announce a published 0.4 release.

| Previous API | Owned asynchronous API |
|---|---|
| `StaticEngine::new(config)` | `StaticEngine::open(config)` in an async context, paired with `close()`; prefer `with_engine(config, action)` |
| Public response body / path lease | Opaque `Response`, public status and headers, `content_length() : Int64?` |
| `response.read(offset, max_len)` | `response.read(max_len=65536)`, advances a single cursor |
| `response.to_bytes()` | `response.to_bytes(max_bytes=...)`, rejects an oversized collection |
| Synchronous/no-op engine close | Async, idempotent `close()`, cancels operations and waits for completion |

One response permits one active read or send. A successful empty read means EOF; file changes, I/O failures, concurrent reads and closing raise distinct errors. `FileChanged` invalidates the response and releases its resources. A client retry must discard the old response and restart at offset zero. No whole-file hash is computed; all `If-Range` requests conservatively receive the complete representation. Plain Range behavior is unchanged.

Files and metadata come from the same opened handle. Renaming, replacing or deleting a pathname does not switch an existing response to the replacement file. Size and last-write timestamps are checked before headers, during transfer, and before EOF. Filesystems that delay or suppress timestamp updates can hide same-size writes; this is detection, not a filesystem snapshot or a guarantee against every concurrent rewrite.

Close responses when no longer needed, including unconsumed responses. Leaving `with_engine` normally, with an error, or by cancellation closes its responses and worker operations. Closing one engine does not close another. Returned immutable byte chunks belong to the caller; retaining those chunks is outside the library's buffering budget.

`Config.limits` sets worker/queue/connection capacities and body/directory budgets. Defaults are 4 workers, 256 queued operations, 1024 connections, 64 KiB blocks and 64 MiB for each memory budget. A body budget must fit both a native block and its delivered copy. Engines on the same Native owner thread share memory accounting; while limits differ, the smallest live limit governs shared admission. Directory metadata reservations remain charged until response close. Exhaustion before response commitment reports overload (HTTP 503).

Directory responses have unknown length and no Content-Length. HTTP/1.1 uses chunked framing; HTTP/1.0 closes the connection to delimit the body. HEAD does not enumerate or render a directory body. Byte chunks may split a UTF-8 code point; decode them incrementally or after reassembly.

Full now uses the pinned Mozilla roots described in [CA provenance](../full/CA-PROVENANCE.md). Explicit `ca_file` replaces the roots, and only explicit `secure=false` disables verification. Thin has no TLS backend or CA asset. WebSocket upgrades use the configured proxy routing and MbedTLS connector; frames are forwarded as bounded bytes.

C/Node asynchronous embedding, io_uring and the wasm-gc engine remain separate, incomplete tasks. Existing C/Node consumers expose complete-server mode only.
