///|
/// Return the first value associated with an option.
pub fn first_value(matches : @argparse.Matches, name : String) -> String? {
  match matches.values.get(name) {
    Some([value, ..]) => Some(value)
    _ => None
  }
}

///|
/// Parse an integer string with an optional leading minus sign.
pub fn parse_integer(s : String) -> Int? {
  if s.length() == 0 {
    return None
  }
  let chars = s.to_array()
  let mut is_neg = false
  let mut start = 0
  if chars[0] == '-' {
    is_neg = true
    start = 1
  }
  if start >= chars.length() {
    return None
  }
  let mut n = 0
  for i = start; i < chars.length(); i = i + 1 {
    let c = chars[i]
    if c < '0' || c > '9' {
      return None
    }
    n = n * 10 + c.to_int() - '0'.to_int()
  }
  if is_neg {
    Some(-n)
  } else {
    Some(n)
  }
}

///|
/// Parse a CLI port, preserving the original decimal truncation behavior.
pub fn parse_port(value : String) -> Int? {
  let s = match value.find(".") {
    Some(idx) => value[:idx].to_owned()
    None => value
  }
  if s.length() == 0 {
    return None
  }
  let mut n = 0
  for c in s {
    if c < '0' || c > '9' {
      return None
    }
    n = n * 10 + c.to_int() - '0'.to_int()
    if n > 65535 {
      return None
    }
  }
  if n < 1 || n > 65535 {
    None
  } else {
    Some(n)
  }
}

///|
/// Parse a cache duration or an explicit max-age directive.
pub fn parse_cache(val : String) -> Result[(Int, String?), String] {
  if val.has_prefix("max-age=") {
    let sec_str = val["max-age=".length():].to_owned()
    match parse_integer(sec_str) {
      Some(sec) =>
        if sec < 0 {
          Err("cache seconds in max-age cannot be negative")
        } else {
          Ok((sec, Some(val)))
        }
      None => Err("invalid cache value: '\{val}'")
    }
  } else {
    match parse_integer(val) {
      Some(sec) =>
        if sec < -1 {
          Err("cache duration cannot be less than -1")
        } else {
          Ok((sec, None))
        }
      None => Err("invalid cache value: '\{val}'")
    }
  }
}

///|
/// Parse Basic Auth credentials in `username:password` form.
pub fn parse_auth(val : String) -> Result[(String, String), String] {
  match val.find(":") {
    Some(idx) => {
      let username = val[:idx].to_owned()
      let password = val[idx + 1:].to_owned()
      if username.length() == 0 {
        return Err("auth username cannot be empty")
      }
      if username.contains("\u0000") || password.contains("\u0000") {
        return Err("auth credentials cannot contain null bytes")
      }
      Ok((username, password))
    }
    None => Err("invalid auth format: expected username:password")
  }
}
