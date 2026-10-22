///|
/// R-N10 / N-15. Identical executable fixtures on Native and WasmGC.
fn run(
  config : @core.Config,
  request : @core.Request,
  files : Map[String, (Bytes, Int32)],
) -> @static_plan.Response? raise {
  let opened : Map[Int32, Bytes] = Map([])
  let mut token = 1
  let mime = @core.MimeRegistry::new()
  let mut step = @static_plan.start(config, request, mime)
  for ;; {
    step = match step {
      Open(path, k) =>
        match
          files.get(
            if path.has_suffix("/") {
              path[:path.length() - 1].to_owned()
            } else {
              path
            },
          ) {
          None => k(None)
          Some((bytes, kind)) => {
            let id = token
            token += 1
            opened[id] = bytes
            k(
              Some({
                token: id,
                kind,
                size: bytes.length().to_int64(),
                mtime: 1700000000L,
              }),
            )
          }
        }
      Prefix(file, count, k) => {
        let bytes = opened[file.token]
        k(bytes[:Int32::min(count, bytes.length())].to_owned())
      }
      List(_, k) =>
        k([
          {
            name: "<x>.txt",
            is_dir: false,
            size: 14L,
            mtime_sec: 1700000000L,
            is_companion: false,
            has_br: false,
            has_gz: false,
          },
          {
            name: "<x>.txt.gz",
            is_dir: false,
            size: 12L,
            mtime_sec: 1700000000L,
            is_companion: false,
            has_br: false,
            has_gz: false,
          },
          {
            name: "中文",
            is_dir: true,
            size: 0L,
            mtime_sec: 1700000000L,
            is_companion: false,
            has_br: false,
            has_gz: false,
          },
        ])
      Done(r) => return Some(r)
      Next => return None
    }
  }
}

///|
fn req(
  target : String,
  meth~ : @core.Method = Get,
  headers~ : Map[String, String] = Map([]),
) -> @core.Request {
  { meth, target, headers, }
}

///|
fn files() -> Map[String, (Bytes, Int32)] {
  Map([
    ("/site", (b"", 2)),
    ("/site/hello.txt", (b"hello moonbit\n", 1)),
    ("/site/index.html", (b"<h1>site</h1>", 1)),
    ("/site/hello.txt.gz", (b"\x1f\x8bgzip", 1)),
    ("/site/hello.txt.br", (b"brotli", 1)),
    ("/site/dir", (b"", 2)),
  ])
}

///|
test "N-15 shared GET HEAD range/cache precedence and 64-bit region" {
  let c = @core.Config::middleware_default("/site")
  for
    (headers, status, length) in [
      (Map([]), 200, 14L),
      (Map([("range", "bytes=2-5")]), 206, 4L),
      (Map([("range", "3-5")]), 206, 3L),
      (Map([("range", "bytes=999-")]), 416, 0L),
      (Map([("if-none-match", "W/\"14-1700000000\"")]), 304, 0L),
      (
        Map([("range", "bytes=2-5"), ("if-none-match", "W/\"14-1700000000\"")]),
        206,
        4L,
      ),
      (
        Map([("range", "bytes=2-5"), ("if-range", "W/\"14-1700000000\"")]),
        200,
        14L,
      ),
    ] {
    let r = run(c, req("/hello.txt", headers~), files()).unwrap()
    assert_eq(r.status, status)
    if r.body is FileRegion(_, _, n) {
      assert_eq(n, length)
    }
    let head = run(c, req("/hello.txt", meth=Head, headers~), files()).unwrap()
    assert_eq(head.status, status)
    assert_true(head.body is Empty)
  }
}

///|
test "N-15 representation negotiation gzip magic and MIME" {
  let c = { ..@core.Config::middleware_default("/site"), brotli: true, }
  for
    (accept, encoding, length) in [
      ("br,gzip", "br", 6L),
      ("gzip", "gzip", 6L),
      ("br;q=0,gzip", "gzip", 6L),
    ] {
    let r = run(
      c,
      req("/hello.txt", headers=Map([("accept-encoding", accept)])),
      files(),
    ).unwrap()
    assert_eq(r.headers["Content-Encoding"], encoding)
    assert_eq(r.headers["Vary"], "Accept-Encoding")
    assert_true(r.body is FileRegion(_, _, n) && n == length)
  }
  let invalid = files()
  invalid["/site/hello.txt.gz"] = (b"invalid", 1)
  let r = run(
    c,
    req("/hello.txt", headers=Map([("accept-encoding", "gzip")])),
    invalid,
  ).unwrap()
  assert_true(!r.headers.contains("Content-Encoding"))
}

///|
test "N-15 BaseURL fallback preserves security Next and missing fallback" {
  let c = {
    ..@core.Config::middleware_default("/site"),
    base_url: "/app",
    spa: true,
  }
  assert_eq(run(c, req("/app/missing.js"), files()).unwrap().status, 200)
  assert_eq(run(c, req("/outside"), files()).unwrap().status, 403)
  assert_eq(run(c, req("/app/%2e%2e/private"), files()).unwrap().status, 403)
  assert_true(run(c, req("/app/missing", meth=Other("POST")), files()) is None)
  let missing = files()
  missing.remove("/site/index.html")
  assert_eq(run(c, req("/app/missing"), missing).unwrap().status, 404)
  let auth = { ..c, basic_auth: Some(("u", "p")), }
  assert_eq(run(auth, req("/app/missing"), files()).unwrap().status, 401)
  let next = { ..c, spa: false, handle_error: false, }
  assert_true(run(next, req("/app/missing"), files()) is None)
}

///|
test "N-15 streamed directory chunks preserve UTF8 bytes and escaping" {
  let c = @core.Config::middleware_default("/site")
  let redirect = run(c, req("/dir?x=1"), files()).unwrap()
  assert_eq(redirect.status, 302)
  assert_eq(redirect.headers["Location"], "/dir/?x=1")
  let r = run(c, req("/dir/?x=%22", headers=Map([("host", "<evil>")])), files()).unwrap()
  guard r.body is Listing(stream) else { fail("expected streaming directory") }
  let result : Array[Byte] = []
  for ;; {
    let bytes = stream.read(7)
    if bytes.is_empty() {
      break
    }
    assert_true(bytes.length() <= 7)
    for b in bytes {
      result.push(b)
    }
  }
  let text = @utf8.decode(Bytes::from_array(result))
  assert_true(text.contains("中文"))
  assert_true(text.contains("&#x3C;x&#x3E;.txt"))
  assert_true(text.contains("[gz]"))
  assert_true(!text.contains("<evil>"))
  stream.close()
  assert_true(stream.read(7).is_empty())
}

///|
test "N-15 configuration decoder rejects unsupported capability and limits" {
  for
    value in [
      ({ "proxy": "http://example.com" } : Json),
      ({ "limits": { "body_block_bytes": 0 } } : Json),
      ({ "spa": true, "try_files": "index.html" } : Json),
    ] {
    let failed = try {
      ignore(@static_plan.decode_config(value))
      false
    } catch {
      _ => true
    }
    assert_true(failed)
  }
}

///|
test "N-15 offsets above JavaScript integer precision remain exact" {
  let c = { ..@core.Config::middleware_default("/site"), gzip: false, }
  let request = req(
    "/huge.bin",
    headers=Map([("range", "bytes=9007199254740993-9007199254740996")]),
  )
  let mut step = @static_plan.start(c, request, @core.MimeRegistry::new())
  for ;; {
    step = match step {
      Open(_, k) =>
        k(
          Some({
            token: 1,
            kind: 1,
            size: 9007199254741999L,
            mtime: 1700000000L,
          }),
        )
      Done(r) => {
        assert_eq(r.status, 206)
        assert_true(
          r.body is FileRegion(_, offset, length) &&
          offset == 9007199254740993L &&
          length == 4L,
        )
        assert_eq(
          r.headers["Content-Range"],
          "bytes 9007199254740993-9007199254740996/9007199254741999",
        )
        break
      }
      _ => fail("unexpected operation for binary representation")
    }
  }
}

///|
test "N-15 forced invalid gzip retains Native FILE_CHANGED behavior" {
  let c = {
    ..@core.Config::middleware_default("/site"),
    force_content_encoding: true,
  }
  let fixtures = files()
  fixtures["/site/invalid.gz"] = (b"not gzip", 1)
  let changed = try {
    ignore(run(c, req("/invalid.gz"), fixtures))
    false
  } catch {
    @static_plan.Changed => true
    _ => false
  }
  assert_true(changed)
}
