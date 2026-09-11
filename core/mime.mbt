///|
/// Standard static web asset MIME table (60+ standard types).
let standard_mime_table : Map[String, String] = Map([
  // Text & Documents
  ("html", "text/html"),
  ("htm", "text/html"),
  ("css", "text/css"),
  ("txt", "text/plain"),
  ("text", "text/plain"),
  ("csv", "text/csv"),
  ("tsv", "text/tab-separated-values"),
  ("md", "text/markdown"),
  ("markdown", "text/markdown"),
  ("xml", "application/xml"),
  ("yaml", "text/yaml"),
  ("yml", "text/yaml"),
  ("rtf", "application/rtf"),
  ("vtt", "text/vtt"),
  // JavaScript & Web Formats
  ("js", "application/javascript"),
  ("mjs", "application/javascript"),
  ("cjs", "application/javascript"),
  ("json", "application/json"),
  ("map", "application/json"),
  ("wasm", "application/wasm"),
  ("webmanifest", "application/manifest+json"),
  // Images
  ("png", "image/png"),
  ("jpg", "image/jpeg"),
  ("jpeg", "image/jpeg"),
  ("gif", "image/gif"),
  ("webp", "image/webp"),
  ("svg", "image/svg+xml"),
  ("svgz", "image/svg+xml"),
  ("ico", "image/x-icon"),
  ("bmp", "image/bmp"),
  ("tiff", "image/tiff"),
  ("tif", "image/tiff"),
  ("avif", "image/avif"),
  // Audio
  ("mp3", "audio/mpeg"),
  ("wav", "audio/wav"),
  ("ogg", "audio/ogg"),
  ("oga", "audio/ogg"),
  ("m4a", "audio/mp4"),
  ("flac", "audio/flac"),
  ("aac", "audio/aac"),
  // Video
  ("mp4", "video/mp4"),
  ("webm", "video/webm"),
  ("ogv", "video/ogg"),
  ("mov", "video/quicktime"),
  ("m4v", "video/x-m4v"),
  ("mkv", "video/x-matroska"),
  // Fonts
  ("woff", "font/woff"),
  ("woff2", "font/woff2"),
  ("ttf", "font/ttf"),
  ("otf", "font/otf"),
  ("eot", "application/vnd.ms-fontobject"),
  // Archives & Binary
  ("pdf", "application/pdf"),
  ("zip", "application/zip"),
  ("gz", "application/gzip"),
  ("br", "application/x-brotli"),
  ("tar", "application/x-tar"),
  ("7z", "application/x-7z-compressed"),
  ("rar", "application/vnd.rar"),
  ("bin", "application/octet-stream"),
  ("exe", "application/octet-stream"),
])

///|
/// A registry mapping file extensions to MIME content types.
pub(all) struct MimeRegistry {
  table : Map[String, String]
}

///|
/// Create a new MimeRegistry initialized with the standard static web asset table.
pub fn MimeRegistry::new() -> MimeRegistry {
  let table = Map([])
  for k, v in standard_mime_table {
    table[k] = v
  }
  { table, }
}

///|
/// Register a custom extension mapping (e.g. "opml" -> "application/xml").
/// Strips leading dot and lowercases extension.
pub fn MimeRegistry::set(
  self : MimeRegistry,
  ext : String,
  mime_type : String,
) -> Unit {
  let clean_ext = normalize_extension(ext)
  if clean_ext.length() > 0 {
    self.table[clean_ext] = mime_type
  }
}

///|
/// Alias for set to register an extension mapping.
pub fn MimeRegistry::register(
  self : MimeRegistry,
  ext : String,
  mime_type : String,
) -> Unit {
  self.set(ext, mime_type)
}

///|
/// Register multiple custom mappings from a map.
pub fn MimeRegistry::set_all(
  self : MimeRegistry,
  overrides : Map[String, String],
) -> Unit {
  for k, v in overrides {
    self.set(k, v)
  }
}

///|
/// Normalize an extension string: strips leading dots and converts to lowercase.
pub fn normalize_extension(raw : String) -> String {
  let mut s = raw
  while s.has_prefix(".") {
    s = s[1:].to_owned()
  }
  s.to_lower()
}

///|
fn rfind_slash(s : String) -> Int? {
  let len = s.length()
  for i = len - 1; i >= 0; i = i - 1 {
    if s[i].to_int() == '/'.to_int() || s[i].to_int() == '\\'.to_int() {
      return Some(i)
    }
  }
  None
}

///|
fn rfind_char(s : String, c : Char) -> Int? {
  let len = s.length()
  let target = c.to_int()
  for i = len - 1; i >= 0; i = i - 1 {
    if s[i].to_int() == target {
      return Some(i)
    }
  }
  None
}

///|
/// Extract file extension from a path, filename, or bare extension string.
pub fn extract_extension(path_or_filename : String) -> String {
  // 1. Strip query string or hash if present
  let clean_path = path_or_filename.split("?").to_array()[0]
  .split("#")
  .to_array()[0].to_owned()
  // 2. Get last path component
  let slash_idx = rfind_slash(clean_path)
  let filename = match slash_idx {
    Some(idx) => clean_path[idx + 1:].to_owned()
    None => clean_path
  }
  // 3. Find dot in filename
  let dot_idx = rfind_char(filename, '.')
  match dot_idx {
    Some(idx) => filename[idx + 1:].to_owned().to_lower()
    None => filename.to_lower()
  }
}

///|
/// Lookup MIME type for a given path or extension, falling back to default_type.
pub fn MimeRegistry::lookup(
  self : MimeRegistry,
  path_or_ext : String,
  default_type? : String = "application/octet-stream",
) -> String {
  let ext = extract_extension(path_or_ext)
  match self.table.get(ext) {
    Some(mime) => mime
    None => default_type
  }
}

///|
/// Parse Apache .types format file content into an extension -> mime_type Map.
pub fn parse_types(content : String) -> Map[String, String] {
  let result = Map([])
  let lines = content.split("\n").to_array()
  for raw_line in lines {
    let raw_stripped = if raw_line.has_suffix("\r") {
      raw_line[:raw_line.length() - 1]
    } else {
      raw_line
    }
    let line = raw_stripped.trim().to_owned()
    if line.length() == 0 || line.has_prefix("#") {
      continue
    }
    let parts = split_whitespace(line)
    if parts.length() < 2 {
      continue
    }
    let mime_type = parts[0]
    for i = 1; i < parts.length(); i = i + 1 {
      let ext = normalize_extension(parts[i])
      if ext.length() > 0 {
        result[ext] = mime_type
      }
    }
  }
  result
}

///|
/// Helper to split line by spaces or tabs.
fn split_whitespace(s : String) -> Array[String] {
  let tokens : Array[String] = []
  let mut current = StringBuilder()
  for c in s {
    if c == ' ' || c == '\t' {
      if !current.is_empty() {
        tokens.push(current.to_string())
        current = StringBuilder()
      }
    } else {
      current.write_char(c)
    }
  }
  if !current.is_empty() {
    tokens.push(current.to_string())
  }
  tokens
}

///|
/// Determine if a MIME content-type is text-based requiring charset decoration.
pub fn is_text_mime(mime : String) -> Bool {
  mime.has_prefix("text/") ||
  mime == "application/javascript" ||
  mime == "application/json" ||
  mime == "application/xml"
}

///|
/// Normalize charset label to WHATWG canonical format.
pub fn normalize_charset(raw : String) -> String {
  let lower = raw.trim().to_owned().to_lower()
  if lower == "utf-8" || lower == "utf8" {
    "UTF-8"
  } else if lower == "iso-8859-6" || lower == "iso8859-6" || lower == "arabic" {
    "ISO-8859-6"
  } else if lower == "shift_jis" || lower == "shift-jis" || lower == "sjis" {
    "Shift_JIS"
  } else if lower == "euc-jp" {
    "EUC-JP"
  } else if lower == "gbk" || lower == "gb2312" {
    "GBK"
  } else if lower == "gb18030" {
    "gb18030"
  } else if lower == "big5" {
    "Big5"
  } else if lower == "windows-1252" || lower == "iso-8859-1" {
    "windows-1252"
  } else {
    raw.trim().to_owned()
  }
}

///|
/// Sniff character encoding from the first <= 1024 bytes of an HTML document.
pub fn sniff_html_charset(bytes : Bytes) -> String? {
  let len = if bytes.length() > 1024 { 1024 } else { bytes.length() }
  if len >= 3 &&
    bytes[0] == b'\xef' &&
    bytes[1] == b'\xbb' &&
    bytes[2] == b'\xbf' {
    return Some("UTF-8")
  }
  if len >= 2 && bytes[0] == b'\xff' && bytes[1] == b'\xfe' {
    return Some("UTF-16LE")
  }
  if len >= 2 && bytes[0] == b'\xfe' && bytes[1] == b'\xff' {
    return Some("UTF-16BE")
  }

  // Search ASCII text for <meta ... charset ...>
  let mut i = 0
  while i < len {
    if bytes[i] == b'<' {
      if i + 5 < len &&
        (bytes[i + 1] == b'm' || bytes[i + 1] == b'M') &&
        (bytes[i + 2] == b'e' || bytes[i + 2] == b'E') &&
        (bytes[i + 3] == b't' || bytes[i + 3] == b'T') &&
        (bytes[i + 4] == b'a' || bytes[i + 4] == b'A') &&
        (bytes[i + 5] == b' ' || bytes[i + 5] == b'\t' || bytes[i + 5] == b'\n') {
        let tag_start = i
        let mut tag_end = i + 5
        while tag_end < len && bytes[tag_end] != b'>' {
          tag_end = tag_end + 1
        }

        let mut j = tag_start + 5
        while j + 7 <= tag_end {
          if (bytes[j] == b'c' || bytes[j] == b'C') &&
            (bytes[j + 1] == b'h' || bytes[j + 1] == b'H') &&
            (bytes[j + 2] == b'a' || bytes[j + 2] == b'A') &&
            (bytes[j + 3] == b'r' || bytes[j + 3] == b'R') &&
            (bytes[j + 4] == b's' || bytes[j + 4] == b'S') &&
            (bytes[j + 5] == b'e' || bytes[j + 5] == b'E') &&
            (bytes[j + 6] == b't' || bytes[j + 6] == b'T') {
            let mut k = j + 7
            while k < tag_end && (bytes[k] == b' ' || bytes[k] == b'\t') {
              k = k + 1
            }
            if k < tag_end && bytes[k] == b'=' {
              k = k + 1
              while k < tag_end && (bytes[k] == b' ' || bytes[k] == b'\t') {
                k = k + 1
              }
              let quote = if k < tag_end &&
                (bytes[k] == b'"' || bytes[k] == b'\'') {
                let q = bytes[k]
                k = k + 1
                Some(q)
              } else {
                None
              }
              let val_start = k
              while k < tag_end {
                match quote {
                  Some(q) => if bytes[k] == q { break }
                  None =>
                    if bytes[k] == b' ' ||
                      bytes[k] == b'\t' ||
                      bytes[k] == b'\r' ||
                      bytes[k] == b'\n' ||
                      bytes[k] == b'>' ||
                      bytes[k] == b'/' ||
                      bytes[k] == b';' ||
                      bytes[k] == b'"' ||
                      bytes[k] == b'\'' {
                      break
                    }
                }
                k = k + 1
              }
              let buf = StringBuilder()
              for b_idx = val_start; b_idx < k; b_idx = b_idx + 1 {
                buf.write_char(Int::unsafe_to_char(bytes[b_idx].to_int()))
              }
              let raw_charset = buf.to_string()
              if raw_charset.length() > 0 {
                return Some(normalize_charset(raw_charset))
              }
            }
          }
          j = j + 1
        }
      }
    }
    i = i + 1
  }
  None
}

///|
/// Formulate full Content-Type header with appropriate charset.
pub fn resolve_content_type(
  path : String,
  registry : MimeRegistry,
  default_type : String,
  sample_bytes? : Bytes,
) -> String {
  let base_mime = registry.lookup(path, default_type~)
  if !is_text_mime(base_mime) {
    return base_mime
  }
  if base_mime == "text/html" {
    match sample_bytes {
      Some(bytes) =>
        match sniff_html_charset(bytes) {
          Some(cs) => base_mime + "; charset=" + cs
          None => base_mime + "; charset=UTF-8"
        }
      None => base_mime + "; charset=UTF-8"
    }
  } else {
    base_mime + "; charset=UTF-8"
  }
}

///|
/// Check if the path's filename component has an extension.
pub fn has_file_extension(path : String) -> Bool {
  let clean_path = path.split("?").to_array()[0].split("#").to_array()[0].to_owned()
  let slash_idx = rfind_slash(clean_path)
  let filename = match slash_idx {
    Some(idx) => clean_path[idx + 1:].to_owned()
    None => clean_path
  }
  let dot_idx = rfind_char(filename, '.')
  match dot_idx {
    Some(idx) => idx > 0
    None => false
  }
}

///|
/// Append default extension to an extensionless path.
pub fn apply_default_ext(path : String, default_ext : String) -> String {
  let clean_ext = if default_ext.has_prefix(".") {
    default_ext[1:].to_owned()
  } else {
    default_ext
  }
  if has_file_extension(path) || clean_ext.length() == 0 {
    path
  } else {
    path + "." + clean_ext
  }
}
