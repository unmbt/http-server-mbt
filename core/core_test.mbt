///|
/// BaseURL and path validation cover the URL safety contract (R-003, C001-C008).
test "normalize base url" {
  assert_eq(normalize_base_url("/") catch { _ => "error" }, "/")
  assert_eq(normalize_base_url("docs/") catch { _ => "error" }, "/docs")
  assert_eq(normalize_base_url("/api/v1") catch { _ => "error" }, "/api/v1")
  let invalid = try {
    ignore(normalize_base_url("../x"))
    false
  } catch {
    _ => true
  }
  assert_true(invalid)
}

///|
test "relative paths reject traversal" {
  assert_true(validate_relative_path("index.html"))
  assert_true(validate_relative_path("a/b.txt"))
  assert_false(validate_relative_path("../secret"))
  assert_false(validate_relative_path("a/../secret"))
  assert_false(validate_relative_path("a\\b"))
  assert_false(validate_relative_path("/absolute"))
}

///|
test "byte ranges" {
  assert_eq(parse_range("bytes=0-4", 10L), Some({ start: 0L, end: 4L, }))
  assert_eq(parse_range("bytes=5-", 10L), Some({ start: 5L, end: 9L, }))
  assert_eq(parse_range("bytes=-5", 10L), None)
  assert_eq(parse_range("bytes=20-30", 10L), None)
  assert_eq(parse_range("bytes=8-2", 10L), None)
}
