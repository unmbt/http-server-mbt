///|
/// Shared helpers for process handle-leak assertions.
///
/// async tests in one package run in parallel inside a single process, so
/// `@server.get_handle_count()` snapshots observe handles owned by sibling
/// tests too. A snapshot assert therefore races against unrelated tests and
/// flakes. Leak semantics differ though: sibling noise is transient (their
/// handles are released when they finish) while a real leak never subsides.
/// The helpers below sample a robust baseline and wait for quiescence instead
/// of asserting on one instantaneous snapshot.

///|
/// Sample the handle-count baseline as the minimum of 3 probes 30ms apart,
/// so a transient sibling-test spike is not frozen into the baseline.
async fn handle_leak_baseline() -> UInt {
  let mut baseline = @server.get_handle_count()
  for _ in 0..<3 {
    @async.sleep(30)
    let cur = @server.get_handle_count()
    if cur < baseline {
      baseline = cur
    }
  }
  baseline
}

///|
/// Wait until the process handle count falls back to
/// `baseline + tolerance`, failing after `deadline_ms`.
/// Transient sibling-test handles are absorbed by the wait; a real leak keeps
/// the count elevated forever and fails with the observed values.
async fn assert_no_handle_leak(
  baseline : UInt,
  tolerance? : UInt = 80U,
  deadline_ms? : Int = 4000,
) -> Unit {
  let step = 40
  let mut waited = 0
  let mut current = @server.get_handle_count()
  while current > baseline + tolerance && waited < deadline_ms {
    @async.sleep(step)
    waited += step
    current = @server.get_handle_count()
  }
  assert_true(current <= baseline + tolerance)
}
