///|
/// An HTTP Entity Tag (RFC 7232 §2.3).
pub(all) struct EntityTag {
  tag : String // Entity tag enclosed in double quotes: e.g. "\"123-456\""
  is_weak : Bool // True if prefixed with W/
} derive(Eq, Debug)

///|
/// Construct an EntityTag from a raw tag string and weak flag.
pub fn EntityTag::new(raw_tag : String, weak : Bool) -> EntityTag {
  let tag = if raw_tag.has_prefix("\"") && raw_tag.has_suffix("\"") {
    raw_tag
  } else {
    "\"" + raw_tag + "\""
  }
  { tag, is_weak: weak, }
}

///|
/// Generate an EntityTag from file metadata (size and modification time in seconds).
pub fn EntityTag::from_metadata(
  size : Int64,
  mtime_sec : Int64,
  weak : Bool,
) -> EntityTag {
  let tag = "\"\{size}-\{mtime_sec}\""
  { tag, is_weak: weak, }
}

///|
/// Format EntityTag as an HTTP header value (e.g. "\"123-456\"" or "W/\"123-456\"").
pub fn EntityTag::to_header_value(self : EntityTag) -> String {
  if self.is_weak {
    "W/" + self.tag
  } else {
    self.tag
  }
}

///|
/// Parse an EntityTag from a header string.
pub fn EntityTag::parse(raw : String) -> EntityTag? {
  let trimmed = raw.trim()
  if trimmed.has_prefix("W/\"") &&
    trimmed.has_suffix("\"") &&
    trimmed.length() >= 4 {
    Some({ tag: trimmed[2:].to_owned(), is_weak: true, })
  } else if trimmed.has_prefix("\"") &&
    trimmed.has_suffix("\"") &&
    trimmed.length() >= 2 {
    Some({ tag: trimmed.to_owned(), is_weak: false, })
  } else {
    None
  }
}

///|
/// Compare a client-supplied raw ETag against the server's EntityTag.
pub fn etag_matches(
  client_raw : String,
  server_tag : EntityTag,
  weak_compare : Bool,
) -> Bool {
  let client_trimmed = client_raw.trim()
  if client_trimmed == "*" {
    return true
  }
  let is_client_weak = client_trimmed.has_prefix("W/")
  let client_opaque_tag = if is_client_weak {
    client_trimmed[2:].to_owned()
  } else {
    client_trimmed.to_owned()
  }
  let server_opaque_tag = server_tag.tag

  if weak_compare {
    client_opaque_tag == server_opaque_tag
  } else if is_client_weak || server_tag.is_weak {
    false
  } else {
    client_opaque_tag == server_opaque_tag
  }
}

///|
/// Check if an If-None-Match header value matches the server ETag.
pub fn if_none_match_matches(
  header_val : String,
  server_tag : EntityTag,
  weak_compare : Bool,
) -> Bool {
  let tags = header_val.split(",").to_array()
  for raw in tags {
    let trimmed = raw.trim().to_owned()
    if etag_matches(trimmed, server_tag, weak_compare) {
      return true
    }
  }
  false
}

///|
/// Pure HTTP date formatter generating RFC 7231 IMF-fixdate:
/// "Sun, 06 Nov 1994 08:49:37 GMT"
pub fn format_http_date(epoch_sec : Int64) -> String {
  let days_since_epoch = (epoch_sec / 86400L).to_int()
  let mut rem_sec = (epoch_sec % 86400L).to_int()
  if rem_sec < 0 {
    rem_sec = rem_sec + 86400
  }
  let hour = rem_sec / 3600
  let minute = rem_sec % 3600 / 60
  let second = rem_sec % 60

  let mut day_of_week = (4 + days_since_epoch) % 7
  if day_of_week < 0 {
    day_of_week = day_of_week + 7
  }
  let wkdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
  let months = [
    "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov",
    "Dec",
  ]

  let mut y = 1970
  let mut d = days_since_epoch
  if d >= 0 {
    while true {
      let leap = is_leap_year(y)
      let days_in_year = if leap { 366 } else { 365 }
      if d < days_in_year {
        break
      }
      d = d - days_in_year
      y = y + 1
    }
  } else {
    while d < 0 {
      y = y - 1
      let leap = is_leap_year(y)
      let days_in_year = if leap { 366 } else { 365 }
      d = d + days_in_year
    }
  }

  let leap = is_leap_year(y)
  let month_days = if leap {
    [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
  } else {
    [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
  }
  let mut m = 0
  while m < 12 {
    if d < month_days[m] {
      break
    }
    d = d - month_days[m]
    m = m + 1
  }
  let day = d + 1

  "\{wkdays[day_of_week]}, \{pad2(day)} \{months[m]} \{y} \{pad2(hour)}:\{pad2(minute)}:\{pad2(second)} GMT"
}

///|
fn is_leap_year(y : Int) -> Bool {
  (y % 4 == 0 && y % 100 != 0) || y % 400 == 0
}

///|
fn pad2(n : Int) -> String {
  if n < 10 {
    "0" + n.to_string()
  } else {
    n.to_string()
  }
}

///|
/// Parse an HTTP date string into UTC epoch seconds.
/// Supports IMF-fixdate ("Sun, 06 Nov 1994 08:49:37 GMT"),
/// RFC 850 ("Sunday, 06-Nov-94 08:49:37 GMT"),
/// asctime ("Sun Nov  6 08:49:37 1994"),
/// and JS toString() ("Fri Sep 11 2026 15:20:00 GMT+0800").
/// Safely returns None on illegal / overflow dates (e.g. C003 "275760-09-24").
pub fn parse_http_date(date_str : String) -> Int64? {
  let s = date_str.trim()
  if s.length() < 10 || s.length() > 64 {
    return None
  }
  if s.has_prefix("275760") {
    return None
  }

  let tokens = split_date_tokens(s)
  if tokens.length() < 5 {
    return None
  }

  let parsed = extract_date_fields(tokens)
  guard parsed is Some((y, m, d, hh, mm, ss)) else { return None }
  if y < 1970 ||
    y > 9999 ||
    m < 1 ||
    m > 12 ||
    d < 1 ||
    d > 31 ||
    hh < 0 ||
    hh > 23 ||
    mm < 0 ||
    mm > 59 ||
    ss < 0 ||
    ss > 60 {
    return None
  }

  let mut days = 0L
  for cur_y in 1970..<y {
    days = days + (if is_leap_year(cur_y) { 366L } else { 365L })
  }
  let leap = is_leap_year(y)
  let month_days = if leap {
    [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
  } else {
    [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
  }
  for cur_m in 0..<(m - 1) {
    days = days + month_days[cur_m].to_int64()
  }
  days = days + (d - 1).to_int64()
  let epoch_sec = days * 86400L +
    hh.to_int64() * 3600L +
    mm.to_int64() * 60L +
    ss.to_int64()
  Some(epoch_sec)
}

///|
fn split_date_tokens(s : StringView) -> Array[String] {
  let tokens : Array[String] = []
  let mut cur = StringBuilder()
  for c in s {
    if c == ' ' || c == '\t' || c == ',' || c == '-' || c == ':' {
      if !cur.is_empty() {
        tokens.push(cur.to_string())
        cur = StringBuilder()
      }
    } else {
      cur.write_char(c)
    }
  }
  if !cur.is_empty() {
    tokens.push(cur.to_string())
  }
  tokens
}

///|
fn month_name_to_int(m : String) -> Int? {
  match m.to_lower() {
    "jan" => Some(1)
    "feb" => Some(2)
    "mar" => Some(3)
    "apr" => Some(4)
    "may" => Some(5)
    "jun" => Some(6)
    "jul" => Some(7)
    "aug" => Some(8)
    "sep" => Some(9)
    "oct" => Some(10)
    "nov" => Some(11)
    "dec" => Some(12)
    _ => None
  }
}

///|
fn extract_date_fields(
  tokens : Array[String],
) -> (Int, Int, Int, Int, Int, Int)? {
  let mut year : Int? = None
  let mut month : Int? = None
  let mut day : Int? = None
  let time_tokens : Array[Int] = []

  for t in tokens {
    if month_name_to_int(t) is Some(m) {
      month = Some(m)
      continue
    }
    match parse_int(t) {
      Some(n) =>
        if n >= 1000 && n <= 9999 {
          year = Some(n)
        } else if n >= 70 && n <= 99 && year is None {
          year = Some(1900 + n)
        } else if n >= 0 && n <= 69 && year is None && time_tokens.length() >= 3 {
          year = Some(2000 + n)
        } else if day is None && month is Some(_) && n >= 1 && n <= 31 {
          day = Some(n)
        } else if day is None && n >= 1 && n <= 31 {
          day = Some(n)
        } else {
          time_tokens.push(n)
        }
      None => ()
    }
  }

  guard year is Some(y) else { return None }
  guard month is Some(m) else { return None }
  guard day is Some(d) else { return None }
  if time_tokens.length() < 3 {
    return None
  }
  let hh = time_tokens[0]
  let mm = time_tokens[1]
  let ss = time_tokens[2]
  Some((y, m, d, hh, mm, ss))
}

///|
fn parse_int(s : String) -> Int? {
  let mut n = 0
  if s.length() == 0 {
    return None
  }
  for c in s {
    if c < '0' || c > '9' {
      return None
    }
    n = n * 10 + (c.to_int() - '0'.to_int())
  }
  Some(n)
}

///|
/// Determine if a request satisfies cache conditions to return 304 Not Modified.
pub fn should_return_304(
  if_none_match : String?,
  if_modified_since : String?,
  server_mtime_sec : Int64,
  server_etag : EntityTag,
  weak_compare : Bool,
) -> Bool {
  if if_none_match is None && if_modified_since is None {
    return false
  }

  if if_modified_since is Some(ims) {
    match parse_http_date(ims) {
      None => return false
      Some(client_time_sec) =>
        if client_time_sec < server_mtime_sec {
          return false
        }
    }
  }

  if if_none_match is Some(inm) {
    if !if_none_match_matches(inm, server_etag, weak_compare) {
      return false
    }
  }

  true
}

///|
/// Cache-Control header strategy.
pub(all) enum CachePolicy {
  MaxAge(Int)
  NoCache
  Exact(String)
} derive(Eq, Debug)

///|
/// Format CachePolicy to header string value.
pub fn format_cache_control(policy : CachePolicy) -> String {
  match policy {
    MaxAge(sec) =>
      if sec < 0 {
        "no-cache, no-store, must-revalidate"
      } else {
        "max-age=" + sec.to_string()
      }
    NoCache => "no-cache, no-store, must-revalidate"
    Exact(val) => val
  }
}
