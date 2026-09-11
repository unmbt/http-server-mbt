///|
/// Active fallback mode for unrouted requests.
pub(all) enum FallbackMode {
  None
  Spa
  TryFiles(String)
} derive(Eq, Debug)

///|
/// Normalize a URL mount prefix per D-04.
pub fn normalize_base_url(value : String) -> String raise ConfigError {
  if value == "" || value == "/" {
    return "/"
  }
  if value.contains("?") ||
    value.contains("#") ||
    value.contains("\\") ||
    value.contains("\u0000") ||
    value.contains("\r") ||
    value.contains("\n") {
    raise ConfigError::InvalidBaseUrl("base_url contains invalid characters")
  }
  if value.contains("..") || value.contains("//") {
    raise ConfigError::InvalidBaseUrl(
      "base_url contains dot segments or consecutive slashes",
    )
  }
  let prefixed = if value[0] == '/' { value } else { "/" + value }
  if prefixed.length() > 1 && prefixed[prefixed.length() - 1] == '/' {
    prefixed[:prefixed.length() - 1].to_owned()
  } else {
    prefixed
  }
}

///|
/// Resolve base_url and base_dir aliases.
pub fn resolve_base_url(
  base_url : String?,
  base_dir : String?,
) -> String raise ConfigError {
  match (base_url, base_dir) {
    (None, None) => "/"
    (Some(u), None) => normalize_base_url(u)
    (None, Some(d)) => normalize_base_url(d)
    (Some(u), Some(d)) => {
      let norm_u = normalize_base_url(u)
      let norm_d = normalize_base_url(d)
      if norm_u != norm_d {
        raise ConfigError::ConflictingBaseUrl(
          "conflicting --base-url '\{u}' and --base-dir '\{d}'",
        )
      }
      norm_u
    }
  }
}

///|
/// Match a decoded request path against the normalized base_url using strict
/// component boundary matching. Returns Some(relative_path) on match, or None
/// if the request falls outside the base_url mount.
pub fn match_and_strip_base_url(
  base_url : String,
  decoded_path : String,
) -> String? {
  if base_url == "/" {
    if decoded_path.length() > 0 && decoded_path[0] == '/' {
      Some(decoded_path[1:].to_owned())
    } else if decoded_path == "" {
      Some("")
    } else {
      None
    }
  } else {
    let base_len = base_url.length()
    if decoded_path == base_url {
      Some("")
    } else if decoded_path.length() > base_len &&
      decoded_path.has_prefix(base_url) &&
      decoded_path[base_len] == '/' {
      Some(decoded_path[base_len + 1:].to_owned())
    } else {
      None
    }
  }
}

///|
/// Formats the Location header for a directory 302 redirect, ensuring
/// trailing slash is added before query and base_url is preserved.
pub fn format_dir_redirect(raw_path : String, raw_query : String?) -> String {
  let path_with_slash = if raw_path.has_suffix("/") {
    raw_path
  } else {
    raw_path + "/"
  }
  match raw_query {
    Some(q) if q.length() > 0 => path_with_slash + "?" + q
    _ => path_with_slash
  }
}
