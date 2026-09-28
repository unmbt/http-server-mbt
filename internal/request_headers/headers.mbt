///|
pub suberror InvalidHeader

///|
pub fn token(text : String) -> Bool {
  if text.is_empty() {
    return false
  }
  for c in text {
    if !((c >= 'a' && c <= 'z') ||
      (c >= 'A' && c <= 'Z') ||
      (c >= '0' && c <= '9') ||
      "!#$%&'*+-.^_`|~".contains(c.to_string())) {
      return false
    }
  }
  true
}

///|
pub fn add(
  headers : Map[String, String],
  name : String,
  raw : String,
) -> Unit raise InvalidHeader {
  if !token(name) {
    raise InvalidHeader
  }
  // Validate before trimming: CR/LF must never disappear as whitespace.
  for c in raw {
    if (c < ' ' && c != '\t') || c == '\u007f' {
      raise InvalidHeader
    }
  }
  let key = name.to_lower()
  let value = raw.trim().to_owned()
  if headers.contains(key) &&
    (
      key == "host" ||
      key == "authorization" ||
      key == "content-length" ||
      key == "transfer-encoding"
    ) {
    raise InvalidHeader
  }
  if (key == "content-length" && headers.contains("transfer-encoding")) ||
    (key == "transfer-encoding" && headers.contains("content-length")) {
    raise InvalidHeader
  }
  if key == "content-length" &&
    (value.is_empty() || value.iter().any(c => c < '0' || c > '9')) {
    raise InvalidHeader
  }
  headers[key] = match headers.get(key) {
    Some(old) => old + (if key == "cookie" { "; " } else { "," }) + value
    None => value
  }
}
