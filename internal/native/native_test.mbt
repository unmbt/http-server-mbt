///|
async test "native rooted lease and bounded worker completion" {
  let runtime = @native.Runtime::new(workers=2, capacity=8)
  defer runtime.close()
  let root = runtime.open_root("testdata/public")
  defer root.close()
  let file = root.open("hello.txt")
  defer file.close()
  assert_eq(file.size, 14L)
  assert_eq(file.read(0L, 14), b"hello moonbit\n")
  file.check()
  let (names, charge) = root.names(1048576L)
  defer runtime.release(directory=true, charge)
  assert_true(names.contains("hello.txt"))
}

///|
test "io_uring capability probe is conservative" {
  let available = @native.io_uring_available()
  let capabilities = @native.io_uring_capabilities()
  if !available {
    // Setup may succeed even when the READ opcode is unavailable.  Preserve
    // that partial capability information for diagnostics instead of
    // treating it as an unavailable probe.
    assert_true((capabilities & 3U) != 3U)
  } else {
    assert_true((capabilities & 1U) != 0U)
    assert_true((capabilities & (1U << 1)) != 0U)
  }
}

///|
/// N-07: an explicit experiment either performs a real bounded file read or
/// is rejected before any native work is submitted.  This runs the same
/// Runtime/File path used by StaticEngine, while remaining valid on Windows
/// and macOS where the Linux experiment is intentionally unavailable.
async test "io_uring explicit backend reads or rejects before work" {
  let available = @native.io_uring_available()
  let maybe_runtime : @native.Runtime? = Some(
    @native.Runtime::new(workers=1, capacity=4, backend="io_uring"),
  ) catch {
    @native.NativeError::Unsupported => None
    _ => fail("io_uring failed with an unexpected native error")
  }
  match maybe_runtime {
    None => assert_false(available)
    Some(runtime) => {
      defer runtime.close()
      assert_true(available)
      let root = runtime.open_root("testdata/public")
      defer root.close()
      let file = root.open("hello.txt")
      defer file.close()
      assert_eq(file.read(0L, 14), b"hello moonbit\n")
    }
  }
}

///|
/// N-07: auto keeps the stable backend fallback usable on hosts where the
/// experiment is blocked by the kernel or sandbox, and uses the experimental
/// read path when the capability probe succeeds.
async test "io backend auto serves a file on every native host" {
  let runtime = @native.Runtime::new(workers=1, capacity=4, backend="auto")
  defer runtime.close()
  let root = runtime.open_root("testdata/public")
  defer root.close()
  let file = root.open("hello.txt")
  defer file.close()
  assert_eq(file.read(0L, 14), b"hello moonbit\n")
}
