///|
/// HTTP methods supported by the static engine.
pub(all) enum Method {
  Get
  Head
  Other(String)
} derive(Eq, Debug)

///|
/// A parsed HTTP request used by the static engine.
pub(all) struct Request {
  pub method : Method
  pub target : String
  pub headers : Map[String, String]
}

///|
/// Normalized static-server configuration.
pub(all) struct Config {
  pub root : String
  pub base_url : String
  pub default_ext : String?
  pub gzip : Bool
  pub brotli : Bool
  pub auto_index : Bool
  pub show_dir : Bool
  pub show_dotfiles : Bool
  pub cache_control : String
}

///|
/// Build the documented server defaults for a filesystem root.
pub fn Config::default(root : String) -> Config {
  {
    root,
    base_url: "/",
    default_ext: Some("html"),
    gzip: false,
    brotli: false,
    auto_index: true,
    show_dir: true,
    show_dotfiles: false,
    cache_control: "max-age=3600",
  }
}

///|
/// A response body range, inclusive at both ends.
pub(all) struct ByteRange {
  pub start : Int64
  pub end : Int64
} derive(Eq, Debug)

///|
/// Normalize a URL mount prefix.
pub fn normalize_base_url(value : String) -> String raise {
  if value == "" || value == "/" {
    return "/"
  }
  if value.contains("?") ||
    value.contains("#") ||
    value.contains("\\") ||
    value.contains("\x00") {
    raise ConfigError::InvalidBaseUrl("base_url contains invalid characters")
  }
  let prefixed = if value[0] == '/' { value } else { "/" + value }
  let trimmed : String = if prefixed[prefixed.length() - 1] == '/' {
    prefixed[:prefixed.length() - 1].to_owned()
  } else {
    prefixed
  }
  if trimmed.contains("..") || trimmed.contains("//") {
    raise ConfigError::InvalidBaseUrl("base_url contains a dot segment")
  }
  trimmed
}

///|
/// Validate a user supplied root-relative path.
pub fn validate_relative_path(path : String) -> Bool {
  if path == "" ||
    path[0] == '/' ||
    path.contains("\x00") ||
    path.contains("\\") {
    false
  } else {
    let parts = path.split("/").to_array()
    for part in parts {
      if part == ".." {
        return false
      }
    }
    true
  }
}

///|
/// Parse a byte range in the compatibility forms accepted by http-server.
pub fn parse_range(value : String, size : Int64) -> ByteRange? {
  let raw = if value.has_prefix("bytes=") { value[6:] } else { value }
  let pieces = raw.split("-").to_array()
  if pieces.length() != 2 || size <= 0 {
    return None
  }
  let start = parse_i64(pieces[0])
  let end0 = parse_i64(pieces[1])
  if start < 0 {
    return None
  }
  if start >= size {
    return None
  }
  let end = if end0 < 0 || end0 >= size { size - 1L } else { end0 }
  if end < start {
    None
  } else {
    Some({ start, end, })
  }
}

///|
/// Configuration failures happen before a listener is created.
fn parse_i64(value : StringView) -> Int64 {
  let mut n = 0L
  if value.length() == 0 {
    return -1L
  }
  for c in value {
    if c < '0' || c > '9' {
      return -1L
    }
    n = n * 10L + (c.to_int() - '0'.to_int()).to_int64()
  }
  n
}

///|
/// Configuration failures happen before a listener is created.
pub suberror ConfigError {
  InvalidBaseUrl(String)
  InvalidRoot(String)
} derive(Debug)
