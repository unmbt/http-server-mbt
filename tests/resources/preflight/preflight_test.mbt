///|
/// R-SAFE/R-N13/R-N16, D-10/D-18, T-025/T-034.
/// This package has its own test process. Serialize its async probes as well:
/// process-wide counts must not include another test's sockets or files.
let probe_lock : @async.Mutex = @async.Mutex()

///|
fn handle_count() -> UInt raise {
  let count = @server.get_handle_count()
  assert_true(count > 0U)
  count
}

///|
fn assert_no_handle_growth(before : UInt, after : UInt) -> Unit raise {
  // Unrelated runtime cleanup may lower the count. No positive tolerance:
  // even one additional retained handle must fail this isolated probe.
  if after > before {
    fail("process handle count grew: before=\{before}, after=\{after}")
  }
}

///|
async fn assert_preflight_rejected(
  config : @core.Config,
  acceptor? : &@server.Acceptor,
) -> Unit {
  let mut rejected = false
  @server.with_server_at(config, 0, acceptor?, _server => {
    fail("preflight unexpectedly started the server")
  }) catch {
    @core.ConfigError::InvalidTls(_) => rejected = true
    err => raise err
  }
  assert_true(rejected)
}

///|
test "preflight handle probe: CI sample 244 to 243 is not a leak" {
  assert_no_handle_growth(244U, 243U)
}

///|
async test "preflight handle probe: a retained file fails and a released file passes" {
  probe_lock.acquire()
  defer probe_lock.release()
  // Initialize async filesystem support before taking a baseline.
  let warmup = @fs.open("testdata/public/hello.txt", mode=ReadOnly)
  warmup.close()
  let before = handle_count()
  let held = @fs.open("testdata/public/hello.txt", mode=ReadOnly)
  defer held.close()
  let with_file = handle_count()
  assert_true(with_file > before)
  let mut detected = false
  assert_no_handle_growth(before, with_file) catch {
    Failure::Failure(message) => {
      assert_true(message.contains("process handle count grew"))
      detected = true
    }
    err => raise err
  }
  assert_true(detected)
  held.close()
  let after_close = handle_count()
  assert_true(after_close < with_file)
  assert_no_handle_growth(with_file, after_close)
  assert_no_handle_growth(before, after_close)
}

///|
// Moved from server/acceptor_test.mbt to isolate resource accounting.
async test "server acceptor: preflight TLS rejection releases resources and incurs 0 handle leaks" {
  probe_lock.acquire()
  defer probe_lock.release()
  let config : @core.Config = {
    ..@core.Config::default("testdata/public"),
    cert_file: Some("testdata/tls/server_cert.pem"),
    key_file: Some("testdata/tls/server_key.pem"),
  }
  assert_preflight_rejected(config)
  let before = handle_count()
  for _ in 0..<5 {
    assert_preflight_rejected(config)
  }
  assert_no_handle_growth(before, handle_count())
}

///|
// Moved from server/preflight_test.mbt; all four configurations
// are now exercised both with the default acceptor and with PlainAcceptor.
async test "preflight: 100-iteration preflight rejection stress incurs 0 handle leaks" {
  probe_lock.acquire()
  defer probe_lock.release()
  let configs : Array[@core.Config] = [
    {
      ..@core.Config::default("testdata/public"),
      cert_file: Some("testdata/tls/server_cert.pem"),
      key_file: Some("testdata/tls/server_key.pem"),
    },
    {
      ..@core.Config::default("testdata/public"),
      cert_file: Some("testdata/tls/server_cert.pem"),
      key_file: None,
    },
    {
      ..@core.Config::default("testdata/public"),
      cert_file: None,
      key_file: Some("testdata/tls/server_key.pem"),
    },
    {
      ..@core.Config::default("testdata/public"),
      cert_file: Some("nonexistent_cert.pem"),
      key_file: Some("nonexistent_key.pem"),
    },
  ]
  let plain = @server.PlainAcceptor::new()
  for config in configs {
    assert_preflight_rejected(config)
    assert_preflight_rejected(config, acceptor=plain)
  }
  let before = handle_count()
  for i in 0..<100 {
    let config = configs[i % 4]
    if i % 8 < 4 {
      assert_preflight_rejected(config)
    } else {
      assert_preflight_rejected(config, acceptor=plain)
    }
  }
  assert_no_handle_growth(before, handle_count())
}
