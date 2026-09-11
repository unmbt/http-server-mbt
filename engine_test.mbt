///|
/// Static engine tests mirror the portable static cases (C001-C008, C010-C015).
async test "static get, head and missing" {
  let config : @core.Config = {
    root: "testdata/public",
    base_url: "/",
    default_ext: Some("html"),
    gzip: false,
    brotli: false,
    auto_index: true,
    show_dir: true,
    show_dotfiles: false,
    cache_control: "max-age=3600",
  }
  let engine = StaticEngine::new(config)
  let get = engine.handle({
    method: @core.Method::Get,
    target: "/hello.txt",
    headers: Map([]),
  })
  match get {
    Handled(response) => {
      assert_eq(response.status, 200)
      assert_eq(response.body.length(), 14)
      assert_true(response.headers.contains("Content-Type"))
      response.close()
    }
    _ => fail("expected handled response")
  }
  let head = engine.handle({
    method: @core.Method::Head,
    target: "/hello.txt",
    headers: Map([]),
  })
  match head {
    Handled(response) => assert_eq(response.body.length(), 0)
    _ => fail("expected head")
  }
  let missing = engine.handle({
    method: @core.Method::Get,
    target: "/missing",
    headers: Map([]),
  })
  match missing {
    Handled(response) => assert_eq(response.status, 404)
    _ => fail("expected 404")
  }
}

///|
async test "range and conditional request" {
  let config : @core.Config = {
    root: "testdata/public",
    base_url: "/",
    default_ext: None,
    gzip: false,
    brotli: false,
    auto_index: true,
    show_dir: true,
    show_dotfiles: false,
    cache_control: "max-age=3600",
  }
  let engine = StaticEngine::new(config)
  let ranged = engine.handle({
    method: @core.Method::Get,
    target: "/hello.txt",
    headers: Map([("Range", "bytes=0-4")]),
  })
  let tag = match ranged {
    Handled(response) => {
      assert_eq(response.status, 206)
      assert_eq(response.body.length(), 5)
      response.headers["ETag"]
    }
    _ => fail("expected range")
  }
  let cached = engine.handle({
    method: @core.Method::Get,
    target: "/hello.txt",
    headers: Map([("If-None-Match", tag)]),
  })
  match cached {
    Handled(response) => assert_eq(response.status, 304)
    _ => fail("expected 304")
  }
}
