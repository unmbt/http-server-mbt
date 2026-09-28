# ABI-only async integration

The companion source replaces `src/integration.mbt` from
`moonbitlang/async@0.21.3` only during the isolated C ABI build. The upstream
file SHA-256 is `34b8623e6f6c0a30556c4b2c1c52f6a5144612ba2b69c1f540e0a4e4595010ea`
(the original LF file). Source: <https://github.com/moonbitlang/async>.
Copyright 2025 International Digital Economy Academy; Apache-2.0, as in the
dependency's LICENSE and the repository's dependency license inventory.

The public Native entry signature is unchanged. Its catch returns after normal
event-loop unwinding; the C owner then fails pending commands and retires the
runtime. There is no longjmp, patched machine code, dependency cache edit or
generated-C rewrite. The build compiles upstream package sources plus this
integration source using the existing `.mi` dependencies, then invokes the
toolchain's link-core plan and rejects generated ABI C containing `exit(`.
`runtime/embedded_signal.c` separately replaces the signal stub object.

Re-review these substitutions when upgrading async or the compiler. CLI builds
and Mooncakes consumers retain the upstream integration.
