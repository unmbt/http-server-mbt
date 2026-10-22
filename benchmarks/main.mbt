///|
extern "C" fn monotonic_ns() -> Int64 = "hs_benchmark_monotonic_ns"

///|
fn option(args : ArrayView[String], name : String, fallback : String) -> String {
  for i = 0; i < args.length(); i = i + 1 {
    if args[i] == name && i + 1 < args.length() {
      return args[i + 1]
    }
    if args[i].has_prefix(name + "=") {
      return args[i][name.length() + 1:].to_owned()
    }
  }
  fallback
}

///|
fn positive_int(value : String, fallback : Int) -> Int {
  if value.length() == 0 {
    return fallback
  }
  let mut parsed = 0
  for c in value {
    if c < '0' || c > '9' {
      return fallback
    }
    parsed = parsed * 10 + c.to_int() - '0'.to_int()
  }
  if parsed > 0 {
    parsed
  } else {
    fallback
  }
}

///|
fn request_for(path : String) -> @core.Request {
  { meth: @core.Method::Get, target: path, headers: Map([]), }
}

///|
/// Run a repeatable in-process static-file benchmark.
///
/// The benchmark exercises the same StaticEngine planning and bounded file
/// read path used by the server. It intentionally reports raw measurements
/// without treating a local machine as a performance gate.
async fn main {
  let args = @env.args()
  let root = option(args, "--root", "testdata/public")
  let path = option(args, "--path", "/hello.txt")
  let backend = option(args, "--io-backend", "platform")
  let iterations = positive_int(option(args, "--iterations", "1000"), 1000)
  let warmup = positive_int(option(args, "--warmup", "10"), 10)
  let config = { ..@core.Config::default(root), io_backend: backend, }
  let engine = @root.StaticEngine::open(config)
  defer engine.close()
  let request = request_for(path)
  for _ in 0..<warmup {
    match engine.handle(request) {
      @root.HandleResult::Handled(response) => {
        ignore(response.to_bytes(max_bytes=16 * 1024 * 1024))
        response.close()
      }
      @root.HandleResult::Next => fail("benchmark request was delegated")
      @root.HandleResult::Error(_) => fail("benchmark error")
    }
  }
  let start = monotonic_ns()
  let mut bytes = 0L
  for _ in 0..<iterations {
    match engine.handle(request) {
      @root.HandleResult::Handled(response) => {
        let body = response.to_bytes(max_bytes=16 * 1024 * 1024)
        bytes += body.length().to_int64()
        response.close()
      }
      @root.HandleResult::Next => fail("benchmark request was delegated")
      @root.HandleResult::Error(_) => fail("benchmark error")
    }
  }
  let elapsed = monotonic_ns() - start
  let elapsed = if elapsed > 0L { elapsed } else { 1L }
  let requests_per_second = iterations.to_double() *
    1_000_000_000.0 /
    elapsed.to_double()
  let mib_per_second = bytes.to_double() *
    1_000_000_000.0 /
    (elapsed.to_double() * 1024.0 * 1024.0)
  println("backend=\{backend}")
  println("io_uring_available=\{@root.io_uring_available()}")
  println("io_uring_capabilities=\{@root.io_uring_capabilities()}")
  println("path=\{path}")
  println("iterations=\{iterations}")
  println("bytes=\{bytes}")
  println("elapsed_ns=\{elapsed}")
  println("requests_per_second=\{requests_per_second}")
  println("mib_per_second=\{mib_per_second}")
}
