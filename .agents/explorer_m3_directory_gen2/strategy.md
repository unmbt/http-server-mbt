# Implementation Strategy: Directory Handling & HTML Directory Listing

## 1. Executive Summary & Scope Boundary

In Milestone 3, the `http-server-mbt` static file serving engine must deliver complete, robust, and specification-compliant directory handling. This encompasses three core capabilities:
1. **302 Found Directory Redirect**: Automatic trailing-slash redirection (`/dir` -> `/dir/`) preserving raw URL percent-encoding and query parameters, with intentional suppression when directory features are disabled (C025).
2. **Directory Index Resolution**: Seamless resolution of `index.html` (or configured default extension) when requesting a directory with a trailing slash, fully integrated with Brotli (`.br`) and gzip (`.gz`) pre-compression negotiation (CC-23).
3. **HTML Directory Listing View (`show_dir = true`)**: Modern, accessible, secure directory index HTML generation featuring:
   - $O(N)$ identification and badge grouping of `.br` / `.gz` companion files using hash set lookups.
   - $O(N \log N)$ case-insensitive natural sorting (directories first, files second, parent `..` at top).
   - Strict HTML entity escaping (`<` -> `&#x3C;`, `>` -> `&#x3E;`, `&` -> `&#x26;`, `"` -> `&#x22;`, `'` -> `&#x27;`) and URL percent-encoding (`+` -> `%2B`, spaces -> `%20`, query `&` -> `&#x26;`).
   - Human-readable file sizes (`B`, `k`, `M`, `G`) and UTC last-modified timestamps.
   - Dotfile filtering controlled by `show_dotfiles`.
   - Precedence arbitration between custom `404.html` and directory listing via `dir_overrides_404` (C016, CC-19).

---

## 2. Directory Redirect (302 Found)

### 2.1 Behavior Contract & Trigger Conditions
When a request target is received:
1. `req.target` is resolved against `config.root` and `config.base_url` using `@core.resolve_path`.
2. If the resolved path exists and is a directory (`@fs.kind(path) is @fs.FileKind::Directory`):
   - Check whether the requested URI pathname ends with a trailing slash (`/`).
   - If the request pathname does **not** end with `/` (e.g. `/subdir`, `/base/subdir?foo=bar`, `/%E4%B8%AD%E6%96%87`, `/subdir_with%20space`):
     - **Suppression Condition (C025)**: If both `config.auto_index == false` AND `config.show_dir == false`, **do NOT issue a redirect**. Return `404 Not Found` (`"File not found. :("`).
     - **Redirect Condition**: If either `config.auto_index == true` OR `config.show_dir == true`, issue an HTTP `302 Found` response.

### 2.2 Location Header Formatting
The `Location` header must preserve:
- The base mount prefix (`base_url`).
- Existing URL percent-encoding in the path (e.g. `%E4%B8%AD%E6%96%87` must remain `%E4%B8%AD%E6%96%87/`, not decoded raw UTF-8).
- Unencoded spaces in the raw path must be normalized to `%20` (CC-20: `subdir_with space` -> `subdir_with%20space/`).
- Query parameters intact (e.g. `?foo=bar`, `?夫=巴` encoded as `?%E5%A4%AB=%E5%B7%B4`, CC-11, CC-13).

The redirect location is computed using `@core.format_dir_redirect(raw_path, raw_query)`:
```moonbit
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
```

### 2.3 Response Specification
- Status: `302 Found`
- Headers:
  - `Location: <formatted_url>`
  - `Content-Type: text/html; charset=UTF-8`
  - `Content-Length: 0`
- Body: `b""`

---

## 3. Directory Index Resolution

### 3.1 Candidate Resolution
When the requested path is a directory and ends with `/`:
1. Check `config.auto_index`:
   - If `config.auto_index == true`:
     Look for `index.<default_ext>` (defaulting to `index.html`) inside the directory:
     `let index_path = dir_path + "/index." + config.default_ext.unwrap_or("html")`
2. **Pre-Compression Negotiation (CC-23)**:
   The index file must pass through content negotiation before reading:
   - If `config.brotli` is enabled, client sends `Accept-Encoding: ... br ...`, and `index_path + ".br"` exists:
     Serve `index_path + ".br"` with `Content-Encoding: br`, `Content-Type: text/html; charset=UTF-8`.
   - Else if `config.gzip` is enabled, client sends `Accept-Encoding: ... gzip ...`, and `index_path + ".gz"` exists:
     Serve `index_path + ".gz"` with `Content-Encoding: gzip`, `Content-Type: text/html; charset=UTF-8`.
   - Else if `index_path` exists and is a regular file:
     Serve `index_path` with `Content-Type: text/html; charset=UTF-8`.
3. Standard Static Caching & Slicing:
   - Evaluates `If-None-Match` and `If-Modified-Since` -> `304 Not Modified` if matched.
   - Evaluates `Range` header -> `206 Partial Content` or `416 Range Not Satisfiable`.
   - Supports `HEAD` method (suppresses body).

If no index file exists, execution proceeds to Directory Listing / 404 Resolution.

---

## 4. HTML Directory Listing (`show_dir = true`)

### 4.1 Precedence Arbitration (`dir_overrides_404`)
In original `http-server` (ecstatic), the presence of a custom `404.html` file in the root interacts with directory listing when no `index.html` exists:
- If `config.show_dir == true` AND `config.dir_overrides_404 == true`:
  Directory listing takes precedence -> returns `200 OK` with HTML directory listing (C016.01).
- If `config.show_dir == true` AND `config.dir_overrides_404 == false`:
  If root contains `404.html`, serve root `404.html` with status `404 Not Found` (C016.02, CC-19).
  If root does not contain `404.html`, render HTML directory listing with status `200 OK`.
- If `config.show_dir == false`:
  Return `404 Not Found` (serve custom `404.html` if present, else plain text `File not found. :(`).

### 4.2 Entry Collection & Dotfile Filtering
1. Read directory entries using `@fs.readdir(dir_path, include_hidden=config.show_dotfiles)`.
2. If `config.show_dotfiles == false`:
   Exclude any entry where `entry_name.has_prefix(".")`.
3. Parent Directory Link (`..`):
   If `dir_path` is not the server root directory (i.e. we are in a subdirectory), synthesize a `..` entry to allow parent folder navigation.

### 4.3 $O(N)$ Companion Files Matching Algorithm
To avoid cluttering the view with redundant rows for pre-compressed assets (e.g. `bundle.js`, `bundle.js.gz`, `bundle.js.br`):
1. **Pass 1 ($O(N)$)**: Insert all entry names into a `Map[String, EntryIndex]` or `Set[String]`.
2. **Pass 2 ($O(N)$)**: For each file ending in `.br` or `.gz`:
   - If ending with `.br` and `base = name[..len-3]` exists in the name set:
     - Mark this `.br` entry as `is_companion = true`.
     - Mark the base entry as having a Brotli companion (`has_br = true`).
   - If ending with `.gz` and `base = name[..len-3]` exists in the name set:
     - Mark this `.gz` entry as `is_companion = true`.
     - Mark the base entry as having a gzip companion (`has_gz = true`).
   - If no uncompressed counterpart exists:
     - The compressed file is standalone; render it with an indicator (e.g. `bundle.js* (bundle.js.gz)` per ecstatic).
3. **Presentation**:
   - Files with companions display badges (e.g., `[br]`, `[gz]`) with direct download links.
   - Redundant companion rows are hidden or grouped, drastically reducing noise.

### 4.4 $O(N \log N)$ Case-Insensitive Natural Sorting
1. Separate entries into:
   - Parent directory `..` (always fixed at position 0).
   - Subdirectories (`is_dir == true`).
   - Regular files (`is_dir == false`, excluding companions if grouped).
2. Sort subdirectories and regular files independently using case-insensitive ordering:
   ```moonbit
   fn compare_entries(a : DirEntry, b : DirEntry) -> Int {
     let cmp = a.name.to_lower().compare(b.name.to_lower())
     if cmp != 0 { cmp } else { a.name.compare(b.name) }
   }
   ```
3. Assemble sorted list: `[..] + sorted(dirs) + sorted(files)`.
Total complexity is strictly $O(N \log N)$.

### 4.5 Strict HTML & URL Escaping Specifications

#### HTML Entity Escaping (C019, C023)
Display names, page titles, header paths, and query parameters must be escaped to prevent XSS:
- `&` -> `&#x26;` (matches C023: `href="./subdir/?a=1&#x26;b=2"`)
- `<` -> `&#x3C;` (matches C019: `&#x3C;dir&#x3E;`)
- `>` -> `&#x3E;` (matches C019: `&#x3C;dir&#x3E;`)
- `"` -> `&#x22;`
- `'` -> `&#x27;`

#### URL Percent-Encoding (C022, C024)
Hrefs for files and directories must be safely percent-encoded:
- `+` MUST be encoded as `%2B` (C022: `href="./aname%2Baplus.txt"`).
- Spaces MUST be encoded as `%20` (C024: `href="./subdir_with%20space/"`).
- Reserved characters `#`, `?`, `%`, `/` encoded appropriately.
- Multibyte UTF-8 codepoints encoded as `%XX%XX...` byte sequences.
- Directory hrefs append `/` and inherit the original query string (with HTML escaping).

### 4.6 File Size & Timestamp Formatting
- **File Size**:
  - Directories: blank `""`.
  - `< 1024 B`: `"{bytes}B"` (e.g. `0B`, `412B`).
  - `1 KiB ~ 1 MiB`: `{bytes / 1024.0:.1f}k` (e.g. `1.5k`).
  - `1 MiB ~ 1 GiB`: `{bytes / 1048576.0:.1f}M` (e.g. `3.2M`).
  - `>= 1 GiB`: `{bytes / 1073741824.0:.1f}G`.
- **Last Modified Timestamp**:
  - Formatted as `DD-Mon-YYYY HH:MM` UTC (e.g. `11-Sep-2026 08:30`).

---

## 5. Concrete Architecture & Implementation Sketch

### 5.1 Pure Helper Functions (in `core` or `engine`)

```moonbit
///| Escape special HTML characters to hexadecimal HTML entities.
pub fn escape_html(s : String) -> String {
  let buf = StringBuilder::new()
  for c in s {
    match c {
      '&' => buf.write_string("&#x26;")
      '<' => buf.write_string("&#x3C;")
      '>' => buf.write_string("&#x3E;")
      '"' => buf.write_string("&#x22;")
      '\'' => buf.write_string("&#x27;")
      _ => buf.write_char(c)
    }
  }
  buf.to_string()
}

///| URL-encode a single path segment (equivalent to encodeURIComponent).
pub fn encode_path_segment(s : String) -> String {
  let bytes = @utf8.encode(s)
  let buf = StringBuilder::new()
  for b in bytes {
    let cp = b.to_int()
    if (cp >= 'A'.to_int() && cp <= 'Z'.to_int()) ||
       (cp >= 'a'.to_int() && cp <= 'z'.to_int()) ||
       (cp >= '0'.to_int() && cp <= '9'.to_int()) ||
       cp == '-'.to_int() || cp == '_'.to_int() || cp == '.'.to_int() ||
       cp == '!'.to_int() || cp == '~'.to_int() || cp == '*'.to_int() ||
       cp == '\''.to_int() || cp == '('.to_int() || cp == ')'.to_int() {
      buf.write_char(Int::unsafe_to_char(cp))
    } else {
      let hex = "0123456789ABCDEF"
      buf.write_char('%')
      buf.write_char(hex[(cp >> 4) & 0xF])
      buf.write_char(hex[cp & 0xF])
    }
  }
  buf.to_string()
}
```

### 5.2 Directory Listing Generation

```moonbit
pub struct ListingEntry {
  name : String
  is_dir : Bool
  size : Int64
  mtime_sec : Int64
  mut is_companion : Bool
  mut has_br : Bool
  mut has_gz : Bool
}

pub fn render_directory_html(
  title_path : String,
  entries : Array[ListingEntry],
  raw_query : String?,
  host : String,
) -> String {
  let buf = StringBuilder::new()
  let enc_title = escape_html(title_path)
  let q_suffix = match raw_query {
    Some(q) if q.length() > 0 => "?" + escape_html(q)
    _ => ""
  }

  buf.write_string("<!doctype html>\n<html>\n<head>\n")
  buf.write_string("  <meta charset=\"utf-8\">\n")
  buf.write_string("  <meta name=\"viewport\" content=\"width=device-width\">\n")
  buf.write_string("  <title>Index of " + enc_title + "</title>\n")
  buf.write_string("  <style type=\"text/css\">\n")
  buf.write_string("    body { font-family: sans-serif; margin: 2rem; }\n")
  buf.write_string("    table { border-collapse: collapse; width: 100%; max-width: 960px; }\n")
  buf.write_string("    td { padding: 4px 10px; }\n")
  buf.write_string("    td.file-size { text-align: right; font-family: monospace; }\n")
  buf.write_string("    td.last-modified { color: #666; font-size: 0.9em; }\n")
  buf.write_string("  </style>\n</head>\n<body>\n")
  buf.write_string("<h1>Index of " + enc_title + "</h1>\n")
  buf.write_string("<table>\n")

  for entry in entries {
    if entry.is_companion {
      continue
    }
    let encoded_name = encode_path_segment(entry.name)
    let href = if entry.is_dir {
      "./" + encoded_name + "/" + q_suffix
    } else {
      "./" + encoded_name
    }
    let display_name = escape_html(entry.name) + (if entry.is_dir { "/" } else { "" })
    let size_str = if entry.is_dir { "" } else { format_file_size(entry.size) }
    let time_str = format_timestamp(entry.mtime_sec)

    buf.write_string("<tr>")
    buf.write_string("<td class=\"last-modified\">" + time_str + "</td>")
    buf.write_string("<td class=\"file-size\"><code>" + size_str + "</code></td>")
    buf.write_string("<td class=\"display-name\"><a href=\"" + href + "\">" + display_name + "</a>")
    if entry.has_br {
      buf.write_string(" <span class=\"badge\"><a href=\"./" + encoded_name + ".br\">[br]</a></span>")
    }
    if entry.has_gz {
      buf.write_string(" <span class=\"badge\"><a href=\"./" + encoded_name + ".gz\">[gz]</a></span>")
    }
    buf.write_string("</td></tr>\n")
  }

  buf.write_string("</table>\n")
  buf.write_string("<br><address>http-server running @ " + escape_html(host) + "</address>\n")
  buf.write_string("</body></html>")
  buf.to_string()
}
```

---

## 6. Verification and Test Migration Plan

### 6.1 Targeted Test Cases from Matrix
- **CC-10**: `subdir` -> 302, `Location: subdir/` (or `/base/subdir/`).
- **CC-11**: `subdir?foo=bar` -> 302, `Location: subdir/?foo=bar`.
- **CC-12**: `%E4%B8%AD%E6%96%87` -> 302, `Location: %E4%B8%AD%E6%96%87/`.
- **CC-13**: `%E4%B8%AD%E6%96%87?%E5%A4%AB=%E5%B7%B4` -> 302, `Location: %E4%B8%AD%E6%96%87/?%E5%A4%AB=%E5%B7%B4`.
- **CC-14**: `subdir/` -> 200, serves `index.html`.
- **CC-19**: `emptyDir/` -> 404, serves `404.html` when `dir_overrides_404 == false`.
- **CC-20**: `subdir_with space` -> 302, `Location: subdir_with%20space/`.
- **CC-21**: `subdir_with space/index.html` -> 200.
- **CC-23**: `gzip/` (with `accept-encoding: gzip`) -> 200, serves `index.html.gz`.
- **C016.01**: `dir_overrides_404=true` + `show_dir=true` -> 200 with directory listing containing `Index of /directory/`.
- **C016.02**: `dir_overrides_404=false` + `show_dir=true` -> 404 with `404file`.
- **C019**: Pathname encoding with `<dir>` -> HTML output contains `&#x3C;dir&#x3E;`.
- **C022**: ShowDir href encoding with `+` -> href contains `./aname%2Baplus.txt`.
- **C023**: ShowDir search encoding with `?a=1&b=2` -> href contains `./subdir/?a=1&#x26;b=2`.
- **C024**: ShowDir with spaces -> directory listing accessible, hrefs encoded.
- **C025**: Trailing slash when `show_dir=false` and `auto_index=false` -> 404 without redirect.
- **C042.03**: Root directory listing contains `./file` and `./canYouSeeMe`.
