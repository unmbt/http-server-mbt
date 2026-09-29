# Fixed license inputs

- HTTP-server-MIT.txt: verbatim LICENSE from http-party/http-server commit
  `0d3b7bb5b6e8a59fd450ae2dca65870009cfcd8b`, including the original authors.
  Applies to migrated test assets and adapted material, not only the ignored
  local reference checkout.
- simdutf-MIT.txt: upstream LICENSE-MIT at commit
  `df8bfed3256cf5ca29969a9dd1db677e835b2c6c` (v7.3.5),
  https://github.com/simdutf/simdutf/blob/df8bfed3256cf5ca29969a9dd1db677e835b2c6c/LICENSE-MIT.
  We select MIT. This pins the notice text, **not** the version of the
  precompiled simdutf object shipped by MoonBit. That object has no independently
  verified upstream version here; each build records the compiler version and
  its SHA-256. A toolchain update requires reviewing its third-party notices.

Build-time inputs are read from the actual MoonBit installation: core LICENSE,
NOTICE and moon.mod, runtime source copyright headers, and backtrace.h's
license. Linux also reads /usr/share/doc/musl/copyright from the installed
Debian package and records dpkg-query's musl/musl-dev versions. Missing
required inputs fail staging; no guessed fallback license is substituted.
