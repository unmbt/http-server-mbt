///|
test "N-13 shared request normalization rejects ambiguity and controls" {
  let headers = Map([])
  @request_headers.add(headers, "Accept", " text/plain ")
  @request_headers.add(headers, "accept", "application/json")
  assert_eq(headers["accept"], "text/plain,application/json")
  @request_headers.add(headers, "Cookie", "a=1")
  @request_headers.add(headers, "cookie", "b=2")
  assert_eq(headers["cookie"], "a=1; b=2")
  for
    (name, value) in [
      ("Bad\tName", "v"),
      ("X", "\r\nv"),
      ("X", "v\u0000"),
      ("Content-Length", "-1"),
    ] {
    let rejected = try {
      @request_headers.add(Map([]), name, value)
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
  @request_headers.add(headers, "Host", "localhost")
  let rejected = try {
    @request_headers.add(headers, "host", "other")
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
}
