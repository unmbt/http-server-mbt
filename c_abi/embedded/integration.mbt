// Derived from moonbitlang/async 0.21.3 src/integration.mbt.
// Copyright 2025 International Digital Economy Academy. Apache-2.0.
// ABI-only compilation substitution: preserve the interface, let the bridge
// retire the owner and fail queued commands after normal exception unwinding.
///|
#coverage.skip
#cfg(target="native")
#doc(hidden)
pub fn run_async_main(main : async () -> Unit) -> Unit {
  @event_loop.with_event_loop(() => main()) catch { _ => () }
}
///|
#cfg(target="native")
pub using @event_loop {set_external_event_loop}
///|
let _unused_import : Unit = ignore(@env_util.eprintln)
