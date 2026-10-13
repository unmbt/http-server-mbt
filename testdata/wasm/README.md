# N-15 / N-19 / N-20 replay corpus

`seeds.txt` drives the MoonBit test in `scripts/check/check_wasm_host.mbtx` on
each platform and Node version. The LCG is `(state * 1664525 + 1013904223) &
0x7fffffff`; each file read is limited to `1 + state % 127` bytes. The driver
prints the seed before running it, so failed logs identify the reproduction.
Set `HS_WASM_SEED` to one listed integer to replay only that seeded portion.

Event sequence: open a 4096-byte regular file; read under injected short reads;
assert byte-for-byte equality and complete cleanup; reopen with AbortSignal;
consume a chunk; abort; close the engine; assert zero requests, tokens and budget.

Minimal late-completion regression (non-random, same script): open binary file;
begin a read; let host I/O finish but hold its completion behind a MoonBit gate;
close the engine; assert the file token remains retained; release the gate;
assert one HS_CLOSED result and a resolved close barrier with zero resources.

Stale-event regression: begin request; reject wrong serial; accept matching
serial once; reject duplicate; release request; reject late completion. Production
request/file generations are monotonic and fail on exhaustion, never wrap/reuse.

Atomic replacement has a separately logged Windows Node `fs.rename` EPERM case;
the rename-away test is not counted as atomic replacement success.
