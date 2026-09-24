///|
/// Empirical Challenger 2 Stress Test Suite for Milestone 4 Gate Verification
/// Tests:
/// 1. Negative offsets, negative lengths, non-existent files, out-of-bounds ranges
/// 2. HEAD body suppression over TransmitFile routes (200, 206, 302, 404, large files)
/// 3. Conditional ETag (304) handling over server socket
/// 4. Resource cleanup and handle leak bounds
///

///|
async fn ch2_test_request(
  port : Int,
  raw_req : String,
) -> (Int, Map[String, String], Bytes) {
  let addr = @socket.Addr::new(0x7F000001, port)
  let conn = @socket.Tcp::connect(addr)
  defer conn.close()
  conn.write(raw_req)
  let status_line = match conn.read_until("\r\n") {
    Some(s) => s
    None => abort("ch2: no status line")
  }
  let parts = status_line.split(" ").to_array()
  let status = if parts.length() >= 2 {
    let mut n = 0
    for c in parts[1] {
      if c >= '0' && c <= '9' {
        n = n * 10 + (c.to_int() - '0'.to_int())
      }
    }
    n
  } else {
    0
  }
  let headers : Map[String, String] = Map([])
  for ;; {
    let line = match conn.read_until("\r\n") {
      Some(s) => s
      None => break
    }
    if line.length() == 0 {
      break
    }
    match line.find(":") {
      Some(idx) => {
        let key = line[:idx].to_lower()
        let val = line[idx + 1:].trim().to_owned()
        headers[key.to_owned()] = val
      }
      None => ()
    }
  }
  let content_len = match headers.get("content-length") {
    Some(len_str) => {
      let mut n = 0
      for c in len_str {
        if c >= '0' && c <= '9' {
          n = n * 10 + (c.to_int() - '0'.to_int())
        }
      }
      n
    }
    None => 0
  }
  let body = if !raw_req.has_prefix("HEAD") && status != 304 && content_len > 0 {
    conn.read_exactly(content_len)
  } else {
    b""
  }
  (status, headers, body)
}

///|
async test "challenger2: Negative offsets, lengths, non-existent files and invalid ranges" {
  let config = @core.Config::default("testdata/public")
  @server.with_server_at(config, 0, async fn(server) {
    defer server.stop()
    let port = server.port()

    // Warm up
    for _ in 0..<3 {
      let (s, _, _) = ch2_test_request(
        port, "GET /hello.txt HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n",
      )
      assert_eq(s, 200)
    }
    let before_handles = handle_leak_baseline()

    let addr = @socket.Addr::new(0x7F000001, port)
    let conn = @socket.Tcp::connect(addr)
    defer conn.close()

    // 1. Direct transmit_file edge cases
    // Negative offset
    let r1 = test_transmit_file(
      conn.fd(),
      "testdata/public/hello.txt",
      -1L,
      10L,
    )
    assert_true(r1 < 0)

    let r2 = test_transmit_file(
      conn.fd(),
      "testdata/public/hello.txt",
      -1000L,
      5L,
    )
    assert_true(r2 < 0)

    // Negative length
    let r3 = test_transmit_file(
      conn.fd(),
      "testdata/public/hello.txt",
      0L,
      -1L,
    )
    assert_true(r3 < 0)

    let r4 = test_transmit_file(
      conn.fd(),
      "testdata/public/hello.txt",
      0L,
      -500L,
    )
    assert_true(r4 < 0)

    // Both negative
    let r5 = test_transmit_file(
      conn.fd(),
      "testdata/public/hello.txt",
      -5L,
      -5L,
    )
    assert_true(r5 < 0)

    // Zero length: no-op success
    let r6 = test_transmit_file(
      conn.fd(),
      "testdata/public/hello.txt",
      0L,
      0L,
    )
    assert_eq(r6, 0)

    // Non-existent file
    let r7 = test_transmit_file(
      conn.fd(),
      "testdata/public/nonexistent_xyz.txt",
      0L,
      10L,
    )
    assert_true(r7 < 0)

    // Empty path
    let r8 = test_transmit_file(conn.fd(), "", 0L, 10L)
    assert_true(r8 < 0)

    // Directory path (cannot TransmitFile a directory)
    let r9 = test_transmit_file(
      conn.fd(),
      "testdata/public/subfolder",
      0L,
      10L,
    )
    assert_true(r9 < 0)

    // Offset beyond file size (hello.txt is 14 bytes)
    let r10 = test_transmit_file(
      conn.fd(),
      "testdata/public/hello.txt",
      20L,
      5L,
    )
    assert_true(r10 < 0)

    // Offset + length beyond file size
    let r11 = test_transmit_file(
      conn.fd(),
      "testdata/public/hello.txt",
      10L,
      10L,
    )
    assert_true(r11 < 0)

    // 2. Server socket HTTP requests with edge cases
    // Non-existent file -> 404
    let (s_404, _h_404, b_404) = ch2_test_request(
      port, "GET /does_not_exist_404.txt HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n",
    )
    assert_eq(s_404, 404)
    assert_true(
      @utf8.decode_lossy(b_404).contains("Custom 404") ||
      @utf8.decode_lossy(b_404).contains("File not found"),
    )

    // Non-existent file with Range header -> still 404 (404 takes precedence over Range)
    let (s_404_range, _, _) = ch2_test_request(
      port, "GET /does_not_exist_404.txt HTTP/1.1\r\nHost: localhost\r\nRange: bytes=0-10\r\nConnection: close\r\n\r\n",
    )
    assert_eq(s_404_range, 404)

    // Invalid negative Range syntax -> 416
    let (s_neg_range, h_neg_range, _) = ch2_test_request(
      port, "GET /hello.txt HTTP/1.1\r\nHost: localhost\r\nRange: bytes=-10-20\r\nConnection: close\r\n\r\n",
    )
    assert_eq(s_neg_range, 416)
    assert_eq(h_neg_range.get("content-range"), Some("bytes */14"))

    // Inverted Range (start > end) -> 416
    let (s_inv_range, h_inv_range, _) = ch2_test_request(
      port, "GET /hello.txt HTTP/1.1\r\nHost: localhost\r\nRange: bytes=10-5\r\nConnection: close\r\n\r\n",
    )
    assert_eq(s_inv_range, 416)
    assert_eq(h_inv_range.get("content-range"), Some("bytes */14"))

    // Out-of-bounds Range (start >= total) -> 416
    let (s_oob_range, h_oob_range, _) = ch2_test_request(
      port, "GET /hello.txt HTTP/1.1\r\nHost: localhost\r\nRange: bytes=50-100\r\nConnection: close\r\n\r\n",
    )
    assert_eq(s_oob_range, 416)
    assert_eq(h_oob_range.get("content-range"), Some("bytes */14"))

    // Valid Suffix Range: bytes=-4 -> "bit\n" (last 4 bytes of "hello moonbit\n")
    let (s_suf, h_suf, b_suf) = ch2_test_request(
      port, "GET /hello.txt HTTP/1.1\r\nHost: localhost\r\nRange: bytes=-4\r\nConnection: close\r\n\r\n",
    )
    assert_eq(s_suf, 206)
    assert_eq(h_suf.get("content-range"), Some("bytes 10-13/14"))
    assert_eq(h_suf.get("content-length"), Some("4"))
    assert_eq(@utf8.decode_lossy(b_suf), "bit\n")

    // Valid single-byte Range: bytes=0-0 -> "h"
    let (s_single, h_single, b_single) = ch2_test_request(
      port, "GET /hello.txt HTTP/1.1\r\nHost: localhost\r\nRange: bytes=0-0\r\nConnection: close\r\n\r\n",
    )
    assert_eq(s_single, 206)
    assert_eq(h_single.get("content-range"), Some("bytes 0-0/14"))
    assert_eq(h_single.get("content-length"), Some("1"))
    assert_eq(@utf8.decode_lossy(b_single), "h")

    assert_no_handle_leak(before_handles)
  })
}

///|
async test "challenger2: HEAD body suppression across TransmitFile routes and large files" {
  let config = @core.Config::default("testdata/public")
  let large_file = "testdata/public/ch2_head_large.dat"
  let large_size = 1500000 // 1.5MB
  let large_bytes = Bytes::makei(large_size, fn(i) { (i % 256).to_byte() })
  @fs.write_file(large_file, large_bytes)
  defer (@fs.remove(large_file) catch { _ => () })

  @server.with_server_at(config, 0, async fn(server) {
    defer server.stop()
    let port = server.port()

    // 1. HEAD on standard small TransmitFile file (/hello.txt)
    let (s1, h1, b1) = ch2_test_request(
      port, "HEAD /hello.txt HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n",
    )
    assert_eq(s1, 200)
    assert_eq(h1.get("content-length"), Some("14"))
    assert_eq(h1.get("content-type"), Some("text/plain; charset=UTF-8"))
    assert_true(h1.contains("etag"))
    assert_true(h1.contains("last-modified"))
    assert_eq(b1.length(), 0)

    // 2. HEAD on 1.5MB large TransmitFile file
    let (s2, h2, b2) = ch2_test_request(
      port, "HEAD /ch2_head_large.dat HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n",
    )
    assert_eq(s2, 200)
    assert_eq(h2.get("content-length"), Some("1500000"))
    assert_eq(b2.length(), 0)

    // 3. HEAD with Range header on TransmitFile file
    let (s3, h3, b3) = ch2_test_request(
      port, "HEAD /hello.txt HTTP/1.1\r\nHost: localhost\r\nRange: bytes=0-4\r\nConnection: close\r\n\r\n",
    )
    assert_eq(s3, 206)
    assert_eq(h3.get("content-range"), Some("bytes 0-4/14"))
    assert_eq(h3.get("content-length"), Some("5"))
    assert_eq(b3.length(), 0)

    // 4. HEAD on directory redirect (302)
    let (s4, h4, b4) = ch2_test_request(
      port, "HEAD /subfolder HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n",
    )
    assert_eq(s4, 302)
    assert_eq(h4.get("location"), Some("/subfolder/"))
    assert_eq(h4.get("content-length"), Some("0"))
    assert_eq(b4.length(), 0)

    // 5. HEAD on 404 missing file
    let (s5, _h5, b5) = ch2_test_request(
      port, "HEAD /nonexistent_file_ch2.txt HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n",
    )
    assert_eq(s5, 404)
    assert_eq(b5.length(), 0)

    // 6. HEAD on index.html
    let (s6, h6, b6) = ch2_test_request(
      port, "HEAD /index.html HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n",
    )
    assert_eq(s6, 200)
    assert_eq(b6.length(), 0)
    assert_eq(h6.get("content-type"), Some("text/html; charset=UTF-8"))
  })
}

///|
async test "challenger2: Conditional ETag 304 handling over server socket" {
  let config = @core.Config::default("testdata/public")

  @server.with_server_at(config, 0, async fn(server) {
    defer server.stop()
    let port = server.port()

    // 1. Initial GET to retrieve valid ETag and Last-Modified
    let (s1, h1, b1) = ch2_test_request(
      port, "GET /hello.txt HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n",
    )
    assert_eq(s1, 200)
    assert_eq(b1.length(), 14)
    guard h1.get("etag") is Some(etag) else { abort("missing etag header") }
    guard h1.get("last-modified") is Some(last_mod) else {
      abort("missing last-modified header")
    }

    // 2. Exact match If-None-Match -> 304 Not Modified
    let (s2, h2, b2) = ch2_test_request(
      port,
      "GET /hello.txt HTTP/1.1\r\nHost: localhost\r\nIf-None-Match: \{etag}\r\nConnection: close\r\n\r\n",
    )
    assert_eq(s2, 304)
    assert_eq(h2.get("etag"), Some(etag))
    assert_eq(b2.length(), 0)

    // 3. Wildcard If-None-Match: * -> 304 Not Modified
    let (s3, _h3, b3) = ch2_test_request(
      port, "GET /hello.txt HTTP/1.1\r\nHost: localhost\r\nIf-None-Match: *\r\nConnection: close\r\n\r\n",
    )
    assert_eq(s3, 304)
    assert_eq(b3.length(), 0)

    // 4. Comma-separated list containing matching ETag -> 304 Not Modified
    let (s4, _h4, b4) = ch2_test_request(
      port,
      "GET /hello.txt HTTP/1.1\r\nHost: localhost\r\nIf-None-Match: \"xyz-dummy\", \{etag}, \"another-tag\"\r\nConnection: close\r\n\r\n",
    )
    assert_eq(s4, 304)
    assert_eq(b4.length(), 0)

    // 5. Non-matching ETag -> 200 OK with full body
    let (s5, _h5, b5) = ch2_test_request(
      port, "GET /hello.txt HTTP/1.1\r\nHost: localhost\r\nIf-None-Match: \"nonmatching-etag\"\r\nConnection: close\r\n\r\n",
    )
    assert_eq(s5, 200)
    assert_eq(b5.length(), 14)
    assert_eq(@utf8.decode_lossy(b5), "hello moonbit\n")

    // 6. Matching If-Modified-Since -> 304 Not Modified
    let (s6, _h6, b6) = ch2_test_request(
      port,
      "GET /hello.txt HTTP/1.1\r\nHost: localhost\r\nIf-Modified-Since: \{last_mod}\r\nConnection: close\r\n\r\n",
    )
    assert_eq(s6, 304)
    assert_eq(b6.length(), 0)

    // 7. Future If-Modified-Since -> 304 Not Modified
    let parsed_last_mod = @core.parse_http_date(last_mod)
    assert_true(parsed_last_mod is Some(_))
    let future_sec = match parsed_last_mod {
      Some(sec) => sec + 86400L
      None => 2000000000L
    }
    let future_date = @core.format_http_date(future_sec)
    let (s7, _h7, b7) = ch2_test_request(
      port,
      "GET /hello.txt HTTP/1.1\r\nHost: localhost\r\nIf-Modified-Since: \{future_date}\r\nConnection: close\r\n\r\n",
    )
    assert_eq(s7, 304)
    assert_eq(b7.length(), 0)

    // 8. Past If-Modified-Since (1990) -> 200 OK with full body
    let (s8, _h8, b8) = ch2_test_request(
      port, "GET /hello.txt HTTP/1.1\r\nHost: localhost\r\nIf-Modified-Since: Mon, 01 Jan 1990 00:00:00 GMT\r\nConnection: close\r\n\r\n",
    )
    assert_eq(s8, 200)
    assert_eq(b8.length(), 14)
    assert_eq(@utf8.decode_lossy(b8), "hello moonbit\n")

    // 9. HEAD with matching If-None-Match -> 304 Not Modified
    let (s9, _h9, b9) = ch2_test_request(
      port,
      "HEAD /hello.txt HTTP/1.1\r\nHost: localhost\r\nIf-None-Match: \{etag}\r\nConnection: close\r\n\r\n",
    )
    assert_eq(s9, 304)
    assert_eq(b9.length(), 0)
  })
}
