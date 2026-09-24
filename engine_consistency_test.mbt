///|
/// R-N15 / D-17 / T-033: metadata-only validators cannot authorize a resume.
async test "N-20 If-Range requires a reliable validator" {
  let engine = @http-server-mbt.StaticEngine::open(@core.Config::default("testdata/public"))
  defer engine.close()
  let req : @core.Request = {
    meth: Get,
    target: "/hello.txt",
    headers: Map([("Range", "bytes=0-4"), ("If-Range", "\"unknown\"")]),
  }
  match engine.handle(req) {
    Handled(response) => {
      assert_eq(response.status, 200)
      assert_eq(response.to_bytes(max_bytes=16777216), b"hello moonbit\n")
    }
    _ => fail("expected a complete representation")
  }
}

///|
async test "N-20 truncation is an error rather than EOF" {
  let dir=@fs.tmpdir(prefix="hs-truncate-")
  defer @fs.rmdir(dir,recursive=true)
  let path = dir+"/n20_truncate.txt"
  @fs.write_file(path, "original bytes")
  defer @fs.remove(path)
  let engine = @http-server-mbt.StaticEngine::open(@core.Config::default(dir))
  defer engine.close()
  let req : @core.Request = { meth: Get, target: "/n20_truncate.txt", headers: Map([]) }
  match engine.handle(req) {
    Handled(response) => {
      @fs.write_file(path, "x")
      let mut rejected = false
      try { ignore(response.to_bytes(max_bytes=16777216)) } catch { _ => rejected = true }
      assert_true(rejected)
    }
    _ => fail("expected a file response")
  }
}
