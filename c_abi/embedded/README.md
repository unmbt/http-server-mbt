# ABI-only async integration

The companion source replaces `src/integration.mbt` from
`moonbitlang/async@0.22.7` only during the isolated C ABI build. The upstream
file SHA-256 is `18f6e0c6e6938de1454603518e080e92bdccf41ef7782156d3993f9e798aedea`
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
