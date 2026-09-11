///|
/// A response body range, inclusive at both ends.
pub(all) struct ByteRange {
  start : Int64
  end : Int64
} derive(Eq, Debug)

///|
/// Result of evaluating an HTTP Range request.
pub(all) enum RangeResult {
  Satisfiable(ByteRange)
  NotSatisfiable
  NotApplicable
} derive(Eq, Debug)

///|
/// Parse an HTTP Range header string according to RFC 7233 and ecstatic compatibility.
pub fn parse_range_spec(header_val : String, total : Int64) -> RangeResult {
  let trimmed = header_val.trim()
  let raw = if trimmed.has_prefix("bytes=") {
    trimmed[6:].trim()
  } else {
    trimmed
  }
  // If unit is another unit (e.g. items=...), ignore Range (RFC 7233 §3.1)
  if find_char_view(raw, '=') is Some(_) {
    return NotApplicable
  }
  if total <= 0L {
    return NotSatisfiable
  }

  let dash_idx = match find_char_view(raw, '-') {
    Some(pos) => pos
    None => return NotApplicable
  }
  let part_start = raw[:dash_idx].trim()
  let part_end = raw[dash_idx + 1:].trim()

  // Suffix range: "-len"
  if part_start.length() == 0 {
    guard parse_i64_strict(part_end) is Some(suffix_len) else {
      return NotSatisfiable
    }
    if suffix_len <= 0L {
      return NotSatisfiable
    }
    let start = if suffix_len >= total { 0L } else { total - suffix_len }
    let end = total - 1L
    return Satisfiable({ start, end, })
  }

  // Prefix range: "start-" or Full range: "start-end"
  guard parse_i64_strict(part_start) is Some(start) else {
    return NotSatisfiable
  }
  if start < 0L || start >= total {
    return NotSatisfiable
  }

  if part_end.length() == 0 {
    // "start-" -> start to EOF
    return Satisfiable({ start, end: total - 1L, })
  }

  guard parse_i64_strict(part_end) is Some(raw_end) else {
    return NotSatisfiable
  }
  if raw_end < start {
    // Inverted range e.g. "333-222" (C004.05)
    return NotSatisfiable
  }

  // Clamp end to EOF e.g. "3-500" (C004.02)
  let end = if raw_end >= total { total - 1L } else { raw_end }
  Satisfiable({ start, end, })
}

///|
/// Strict parsing of a non-negative Int64 from StringView.
fn parse_i64_strict(s : StringView) -> Int64? {
  if s.length() == 0 {
    return None
  }
  let mut n = 0L
  for c in s {
    let cp = c.to_int()
    if cp < '0'.to_int() || cp > '9'.to_int() {
      return None
    }
    n = n * 10L + (cp - '0'.to_int()).to_int64()
  }
  Some(n)
}

///|
/// Format Content-Range header for a successful 206 response.
/// e.g. "bytes 3-5/11"
pub fn format_content_range(
  start : Int64,
  end : Int64,
  total : Int64,
) -> String {
  "bytes \{start}-\{end}/\{total}"
}

///|
/// Format Content-Range header for an unsatisfiable 416 response.
/// e.g. "bytes */11" (per C004.03)
pub fn format_content_range_unsatisfiable(total : Int64) -> String {
  "bytes */\{total}"
}

///|
/// Legacy compatibility helper matching original core.parse_range.
pub fn parse_range(value : String, size : Int64) -> ByteRange? {
  match parse_range_spec(value, size) {
    Satisfiable(r) => Some(r)
    _ => None
  }
}
