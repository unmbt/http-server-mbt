///|
fn header(request : @core.Request, name : String) -> String? {
  let wanted = name.to_lower()
  for key, value in request.headers {
    if key.to_lower() == wanted {
      return Some(value)
    }
  }
  None
}

///|
fn normalize_root_join(root : String, relative : String) -> String {
  let norm_root = if root.length() > 1 &&
    (root.has_suffix("/") || root.has_suffix("\\")) {
    root[:root.length() - 1].to_owned()
  } else {
    root
  }
  if relative == "" {
    norm_root
  } else if relative.has_prefix("/") || relative.has_prefix("\\") {
    norm_root + relative
  } else {
    norm_root + "/" + relative
  }
}

///|
/// Escape characters for safe HTML rendering.
pub fn escape_html(s : String) -> String {
  let buf = StringBuilder()
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

///|
fn encode_path_segment(s : String) -> String {
  let bytes = @utf8.encode(s)
  let buf = StringBuilder()
  for b in bytes {
    let cp = b.to_int()
    if (cp >= 'A'.to_int() && cp <= 'Z'.to_int()) ||
      (cp >= 'a'.to_int() && cp <= 'z'.to_int()) ||
      (cp >= '0'.to_int() && cp <= '9'.to_int()) ||
      cp == '-'.to_int() ||
      cp == '_'.to_int() ||
      cp == '.'.to_int() ||
      cp == '~'.to_int() {
      buf.write_char(Int::unsafe_to_char(cp))
    } else {
      let hex = "0123456789ABCDEF"
      buf.write_char('%')
      buf.write_char(hex[(cp >> 4) & 0xF].to_int().unsafe_to_char())
      buf.write_char(hex[cp & 0xF].to_int().unsafe_to_char())
    }
  }
  buf.to_string()
}

///|
fn check_accepts_encoding(accept_header : String, encoding : String) -> Bool {
  let lower = accept_header.to_lower()
  let parts = lower.split(",").to_array()
  let wanted = encoding.to_lower()
  let mut accepted = false
  for p in parts {
    let item = p.trim().to_owned()
    if item.length() == 0 {
      continue
    }
    let subparts = item.split(";").to_array()
    let enc = subparts[0].trim().to_owned()
    let mut q_zero = false
    if subparts.length() > 1 {
      for i = 1; i < subparts.length(); i = i + 1 {
        let param = subparts[i].trim().to_owned()
        if param == "q=0" ||
          param == "q=0.0" ||
          param == "q=0.00" ||
          param == "q=0.000" {
          q_zero = true
        }
      }
    }
    if q_zero {
      if enc == wanted || enc == "*" {
        return false
      }
    } else if enc == wanted ||
      enc == "*" ||
      (wanted == "gzip" && (enc == "compress" || enc == "deflate")) {
      accepted = true
    }
  }
  accepted
}

///|
async fn StaticEngine::has_gzip_magic(self : StaticEngine, path : String) -> Bool {
  try {
    let f = self.open_file(path)
    defer f.close()
    if f.size < 2L { return false }
    let bytes = f.read(0L, 2)
    bytes.length() == 2 && bytes[0] == b'\x1f' && bytes[1] == b'\x8b'
  } catch {
    @native.NativeError::Missing => false
    e => raise e
  }
}

///|
fn format_file_size(size : Int64) -> String {
  if size < 1024L {
    size.to_string() + "B"
  } else if size < 1048576L {
    let kb = size.to_double() / 1024.0
    format_1dec(kb) + "k"
  } else if size < 1073741824L {
    let mb = size.to_double() / 1048576.0
    format_1dec(mb) + "M"
  } else {
    let gb = size.to_double() / 1073741824.0
    format_1dec(gb) + "G"
  }
}

///|
fn format_1dec(val : Double) -> String {
  let rounded = (val * 10.0 + 0.5).to_int64()
  let whole = rounded / 10L
  let frac = rounded % 10L
  whole.to_string() + "." + frac.to_string()
}

///|
fn format_listing_timestamp(epoch_sec : Int64) -> String {
  let days_since_epoch = (epoch_sec / 86400L).to_int()
  let mut rem_sec = (epoch_sec % 86400L).to_int()
  if rem_sec < 0 {
    rem_sec = rem_sec + 86400
  }
  let hour = rem_sec / 3600
  let minute = rem_sec % 3600 / 60

  let months = [
    "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov",
    "Dec",
  ]
  let mut y = 1970
  let mut d = days_since_epoch
  if d >= 0 {
    while true {
      let leap = (y % 4 == 0 && y % 100 != 0) || y % 400 == 0
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
      let leap = (y % 4 == 0 && y % 100 != 0) || y % 400 == 0
      let days_in_year = if leap { 366 } else { 365 }
      d = d + days_in_year
    }
  }
  let leap = (y % 4 == 0 && y % 100 != 0) || y % 400 == 0
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
  let pad_day = if day < 10 { "0" + day.to_string() } else { day.to_string() }
  let pad_hour = if hour < 10 {
    "0" + hour.to_string()
  } else {
    hour.to_string()
  }
  let pad_min = if minute < 10 {
    "0" + minute.to_string()
  } else {
    minute.to_string()
  }
  "\{pad_day}-\{months[m]}-\{y} \{pad_hour}:\{pad_min}"
}

///|
priv struct ListingEntry {
  name : String
  is_dir : Bool
  size : Int64
  mtime_sec : Int64
  mut is_companion : Bool
  mut has_br : Bool
  mut has_gz : Bool
}

///|
fn compare_entries(a : ListingEntry, b : ListingEntry) -> Int {
  let cmp = a.name.to_lower().compare(b.name.to_lower())
  if cmp != 0 {
    cmp
  } else {
    a.name.compare(b.name)
  }
}

///|
fn listing_header(title_path : String, _raw_query : String?) -> String {
  let buf = StringBuilder()
  let enc_title = escape_html(title_path)

  buf.write_string("<!doctype html>\n<html>\n<head>\n")
  buf.write_string("  <meta charset=\"utf-8\">\n")
  buf.write_string(
    "  <meta name=\"viewport\" content=\"width=device-width\">\n",
  )
  buf.write_string("  <title>Index of " + enc_title + "</title>\n")
  buf.write_string("  <style type=\"text/css\">\n")
  buf.write_string(
    "    body { font-family: sans-serif; margin: 2rem; }\n" +
    "    table { border-collapse: collapse; width: 100%; max-width: 960px; }\n" +
    "    td { padding: 4px 10px; }\n" +
    "    td.file-size { text-align: right; font-family: monospace; }\n" +
    "    td.last-modified { color: #666; font-size: 0.9em; }\n",
  )
  buf.write_string("  </style>\n</head>\n<body>\n")
  buf.write_string("<h1>Index of " + enc_title + "</h1>\n")
  buf.write_string("<table>\n")

  buf.to_string()
}

///|
fn listing_row(entry : ListingEntry, raw_query : String?) -> String {
  let buf = StringBuilder()
  let q_suffix = match raw_query { Some(q) if q.length() > 0 => "?" + escape_html(q); _ => "" }
    if entry.is_companion {
      return buf.to_string()
    }
    if entry.name == ".." {
      buf.write_string("<tr>")
      buf.write_string("<td class=\"last-modified\"></td>")
      buf.write_string("<td class=\"file-size\"></td>")
      buf.write_string(
        "<td class=\"display-name\"><a href=\"../" +
        q_suffix +
        "\">../</a></td>",
      )
      buf.write_string("</tr>\n")
      return buf.to_string()
    }
    let encoded_name = encode_path_segment(entry.name)
    let href = if entry.is_dir {
      "./" + encoded_name + "/" + q_suffix
    } else {
      "./" + encoded_name
    }
    let display_name = escape_html(entry.name) +
      (if entry.is_dir { "/" } else { "" })
    let size_str = if entry.is_dir { "" } else { format_file_size(entry.size) }
    let time_str = format_listing_timestamp(entry.mtime_sec)

    buf.write_string("<tr>")
    buf.write_string("<td class=\"last-modified\">" + time_str + "</td>")
    buf.write_string(
      "<td class=\"file-size\"><code>" + size_str + "</code></td>",
    )
    buf.write_string(
      "<td class=\"display-name\"><a href=\"" +
      href +
      "\">" +
      display_name +
      "</a>",
    )
    if entry.has_br {
      buf.write_string(
        " <span class=\"badge\"><a href=\"./" +
        encoded_name +
        ".br\">[br]</a></span>",
      )
    }
    if entry.has_gz {
      buf.write_string(
        " <span class=\"badge\"><a href=\"./" +
        encoded_name +
        ".gz\">[gz]</a></span>",
      )
    }
    buf.write_string("</td></tr>\n")

  buf.to_string()
}

///|
fn listing_footer(host : String) -> String {
  let buf = StringBuilder()
  buf.write_string("</table>\n")
  buf.write_string(
    "<br><address>http-server running @ " + escape_html(host) + "</address>\n",
  )
  buf.write_string("</body></html>")
  buf.to_string()
}

///|
fn render_directory_html(title_path : String, entries : Array[ListingEntry], raw_query : String?, host : String) -> String {
  let buf = StringBuilder()
  buf.write_string(listing_header(title_path, raw_query))
  for entry in entries { buf.write_string(listing_row(entry, raw_query)) }
  buf.write_string(listing_footer(host))
  buf.to_string()
}

///|
/// Pure HTML directory listing renderer for testing and embedding (AD-05).
pub fn render_directory_listing_html(
  title_path : String,
  entry_names : Array[(String, Bool)],
  raw_query? : String?,
  host? : String = "localhost",
) -> String {
  let entries : Array[ListingEntry] = []
  for item in entry_names {
    let (name, is_dir) = item
    entries.push({
      name,
      is_dir,
      size: 0L,
      mtime_sec: 0L,
      is_companion: false,
      has_br: false,
      has_gz: false,
    })
  }
  let q = match raw_query {
    Some(opt) => opt
    None => None
  }
  render_directory_html(title_path, entries, q, host)
}

///|
fn StaticEngine::make_terminal_404_response(
  self : StaticEngine,
  request : @core.Request,
) -> ResponsePlan {
  let text = "File not found. :("
  let body_bytes = @utf8.encode(text)
  let headers : Map[String, String] = Map([
    ("Content-Type", "text/plain; charset=UTF-8"),
    ("Content-Length", body_bytes.length().to_string()),
  ])
  @core.apply_security_headers(headers, self.config, request.meth)
  let body = if request.meth is Head {
    PlanBody::Empty
  } else {
    PlanBody::Bytes(body_bytes)
  }
  { status: 404, headers, body, }
}

///|
async fn StaticEngine::make_404_response(
  self : StaticEngine,
  request : @core.Request,
) -> ResponsePlan {
  let custom_404 = normalize_root_join(self.config.root, "404.html")
  let has_404_html = try
    self.exists(custom_404) && self.kind(custom_404) is @fs.FileKind::Regular
  catch {
    @native.NativeError::Missing => false
    e => raise e
  }
  if has_404_html {
    let file = self.open_file(custom_404)
    let size = file.size
    let headers : Map[String, String] = Map([
      ("Content-Type", "text/html; charset=UTF-8"),
      ("Content-Length", size.to_string()),
    ])
    @core.apply_security_headers(headers, self.config, request.meth)
    let body = if request.meth is Head {
      PlanBody::Empty
    } else {
      PlanBody::FileRegion(file, 0L, size)
    }
    if request.meth is Head { file.close() }
    { status: 404, headers, body, }
  } else {
    self.make_terminal_404_response(request)
  }
}

///|
/// Resolve and read one static request.
async fn StaticEngine::plan_request(
  self : StaticEngine,
  request : @core.Request,
) -> PlanResult {
  // 1. Evaluate security policies (Host whitelist, Basic Auth, OPTIONS preflight)
  let sec_decision = @core.evaluate_security_policies(self.config, request)
  match sec_decision {
    Unauthorized(headers, body) => {
      let b = if request.meth is Head {
        PlanBody::Empty
      } else {
        PlanBody::Bytes(body)
      }
      headers["Content-Type"] = "text/plain; charset=UTF-8"
      headers["Content-Length"] = body.length().to_string()
      return Handled({ status: 401, headers, body: b, })
    }
    Forbidden(headers, body) => {
      let b = if request.meth is Head {
        PlanBody::Empty
      } else {
        PlanBody::Bytes(body)
      }
      headers["Content-Type"] = "text/plain; charset=UTF-8"
      headers["Content-Length"] = body.length().to_string()
      return Handled({ status: 403, headers, body: b, })
    }
    Preflight(headers) => {
      headers["Content-Length"] = "0"
      return Handled({ status: 204, headers, body: PlanBody::Empty, })
    }
    Proceed => ()
  }

  // 2. HTTP method validation
  if request.meth is Other(_) {
    return Next
  }

  // 2.1 Robots.txt interception per D-03 / C042.04
  if self.config.robots {
    let raw_target_parts = request.target.split("?").to_array()
    if raw_target_parts[0] == "/robots.txt" {
      let body_bytes = @utf8.encode("User-agent: *\nDisallow: /\n")
      let headers : Map[String, String] = Map([
        ("Content-Type", "text/plain"),
        ("Content-Length", body_bytes.length().to_string()),
      ])
      @core.apply_security_headers(headers, self.config, request.meth)
      let body = if request.meth is Head {
        PlanBody::Empty
      } else {
        PlanBody::Bytes(body_bytes)
      }
      return Handled({ status: 200, headers, body, })
    }
  }

  // 3. Path resolution & root anchoring
  let resolved = @core.resolve_path(
    self.config.root,
    self.config.base_url,
    request.target,
  )
  let path = match resolved {
    Ok(p) => p
    Err(@core.PathError::OutsideBaseUrl(_)) => {
      // D-04 & C042.21: 403 Forbidden with empty body
      let headers : Map[String, String] = Map([("Content-Length", "0")])
      @core.apply_security_headers(headers, self.config, request.meth)
      return Handled({ status: 403, headers, body: PlanBody::Empty, })
    }
    Err(@core.PathError::TraversalForbidden(_)) => {
      let body_bytes = @utf8.encode("Access denied")
      let headers : Map[String, String] = Map([
        ("Content-Type", "text/plain; charset=UTF-8"),
        ("Content-Length", body_bytes.length().to_string()),
      ])
      @core.apply_security_headers(headers, self.config, request.meth)
      let body = if request.meth is Head {
        PlanBody::Empty
      } else {
        PlanBody::Bytes(body_bytes)
      }
      return Handled({ status: 403, headers, body, })
    }
    Err(@core.PathError::MalformedUri(_)) => {
      let body_bytes = @utf8.encode("Bad Request")
      let headers : Map[String, String] = Map([
        ("Content-Type", "text/plain; charset=UTF-8"),
        ("Content-Length", body_bytes.length().to_string()),
      ])
      @core.apply_security_headers(headers, self.config, request.meth)
      let body = if request.meth is Head {
        PlanBody::Empty
      } else {
        PlanBody::Bytes(body_bytes)
      }
      return Handled({ status: 400, headers, body, })
    }
    Err(@core.PathError::NotFound(_)) => {
      if self.config.proxy is Some(_) || !self.config.handle_error {
        return Next
      }
      return Handled(self.make_404_response(request))
    }
  }

  let raw_target_parts = request.target.split("?").to_array()
  let raw_path = raw_target_parts[0].to_owned()
  let raw_query = if raw_target_parts.length() > 1 {
    Some(raw_target_parts[1].to_owned())
  } else {
    None
  }

  // 4. Directory Handling
  let is_dir = try
    self.exists(path) && self.kind(path) is @fs.FileKind::Directory
  catch {
    @native.NativeError::Missing => false
    e => raise e
  }

  if is_dir {
    if !raw_path.has_suffix("/") {
      // Directory request without trailing slash
      if !self.config.auto_index && !self.config.show_dir {
        // C025 suppression
        return Handled(self.make_404_response(request))
      }
      let loc = @core.format_dir_redirect(raw_path, raw_query)
      let headers : Map[String, String] = Map([
        ("Location", loc),
        ("Content-Type", "text/html; charset=UTF-8"),
        ("Content-Length", "0"),
      ])
      @core.apply_security_headers(headers, self.config, request.meth)
      return Handled({ status: 302, headers, body: PlanBody::Empty, })
    }

    // Directory request with trailing slash
    let mut dir_file_chosen : (String, String, String?)? = None // (chosen_file, represented_path, content_encoding)
    if self.config.auto_index {
      let default_ext = self.config.default_ext.unwrap_or("html")
      let index_candidate = path + "/index." + default_ext
      let accept = header(request, "accept-encoding").unwrap_or("")

      if self.config.brotli && check_accepts_encoding(accept, "br") {
        let p = index_candidate + ".br"
        let p_exists = try
          self.exists(p) && self.kind(p) is @fs.FileKind::Regular
        catch {
          @native.NativeError::Missing => false
          e => raise e
        }
        if p_exists {
          dir_file_chosen = Some((p, index_candidate, Some("br")))
        }
      }

      if dir_file_chosen is None &&
        self.config.gzip &&
        check_accepts_encoding(accept, "gzip") {
        let p = index_candidate + ".gz"
        let p_exists = try
          self.exists(p) && self.kind(p) is @fs.FileKind::Regular
        catch {
          @native.NativeError::Missing => false
          e => raise e
        }
        if p_exists && self.has_gzip_magic(p) {
          dir_file_chosen = Some((p, index_candidate, Some("gzip")))
        }
      }

      if dir_file_chosen is None {
        let p_exists = try
          self.exists(index_candidate) &&
          self.kind(index_candidate) is @fs.FileKind::Regular
        catch {
          @native.NativeError::Missing => false
          e => raise e
        }
        if p_exists {
          dir_file_chosen = Some((index_candidate, index_candidate, None))
        }
      }
    }

    match dir_file_chosen {
      Some((chosen, represented, encoding)) =>
        return self.serve_file(request, chosen, represented, encoding)
      None => ()
    }

    // No index file found
    if self.config.show_dir {
      if !self.config.dir_overrides_404 && !self.config.has_fallback() {
        let root_404 = normalize_root_join(self.config.root, "404.html")
        let has_404 = try
          self.exists(root_404) && self.kind(root_404) is @fs.FileKind::Regular
        catch {
          @native.NativeError::Missing => false
          e => raise e
        }
        if has_404 {
          return Handled(self.make_404_response(request))
        }
      }

      // D-06: admit all metadata before building a listing. An unconsumed
      // listing retains its reservation, so slow clients cannot grow memory.
      if request.meth is Head {
        let headers : Map[String,String]=Map([("Content-Type","text/html; charset=UTF-8")])
        @core.apply_security_headers(headers,self.config,request.meth)
        return Handled({status:200,headers,body:Empty})
      }
      let mut metadata_charge=request.target.length()*32+16384
      self.runtime.reserve(directory=true,metadata_charge)
      let mut retained=false
      defer { if !retained { self.runtime.release(directory=true,metadata_charge) } }
      // Render HTML directory listing
      let (dir_names,name_charge) = self.readdir(
        path,
        include_hidden=self.config.show_dotfiles,
      )
      metadata_charge += name_charge

      let entries : Array[ListingEntry] = []
      let name_map : Map[String, ListingEntry] = Map([])

      for name in dir_names {
        if !self.config.show_dotfiles && name.has_prefix(".") {
          continue
        }
        let child_path = path + "/" + name
        let child = self.open_file(child_path) catch {
          @native.NativeError::Missing => continue
          e => raise e
        }
        let is_child_dir = child.kind == 2
        let size = if is_child_dir { 0L } else { child.size }
        let mtime_sec = child.mtime
        child.close()
        let entry : ListingEntry = {
          name,
          is_dir: is_child_dir,
          size,
          mtime_sec,
          is_companion: false,
          has_br: false,
          has_gz: false,
        }
        entries.push(entry)
        name_map[name] = entry
      }

      // $O(N) companion matching
      for entry in entries {
        if !entry.is_dir {
          if entry.name.has_suffix(".br") && entry.name.length() > 3 {
            let base = entry.name[:entry.name.length() - 3].to_owned()
            if name_map.contains(base) {
              entry.is_companion = true
              name_map[base].has_br = true
            }
          } else if entry.name.has_suffix(".gz") && entry.name.length() > 3 {
            let base = entry.name[:entry.name.length() - 3].to_owned()
            if name_map.contains(base) {
              entry.is_companion = true
              name_map[base].has_gz = true
            }
          }
        }
      }

      // Partition and sort ($O(N \log N)$)
      let dirs : Array[ListingEntry] = []
      let files : Array[ListingEntry] = []
      for entry in entries {
        if entry.is_companion {
          continue
        }
        if entry.is_dir {
          dirs.push(entry)
        } else {
          files.push(entry)
        }
      }
      dirs.sort_by(compare_entries)
      files.sort_by(compare_entries)

      let final_entries : Array[ListingEntry] = []
      let norm_root = normalize_root_join(self.config.root, "")
      let norm_path = normalize_root_join(path, "")
      if norm_path != norm_root {
        final_entries.push({
          name: "..",
          is_dir: true,
          size: 0L,
          mtime_sec: 0L,
          is_companion: false,
          has_br: false,
          has_gz: false,
        })
      }
      for d in dirs {
        final_entries.push(d)
      }
      for f in files {
        final_entries.push(f)
      }

      let host = header(request, "host").unwrap_or("localhost")
      let display_title = if raw_path.has_suffix("/") {
        raw_path
      } else {
        raw_path + "/"
      }
      let headers : Map[String, String] = Map([
        ("Content-Type", "text/html; charset=UTF-8"),
      ])
      @core.apply_security_headers(headers, self.config, request.meth)
      let body = if request.meth is Head {
        PlanBody::Empty
      } else {
        PlanBody::Listing({ entries: final_entries, title: display_title, query: raw_query, host, stage: 0, index: 0, pending: b"", position: 0, metadata_charge })
      }
      retained=true
      return Handled({ status: 200, headers, body, })
    }

    // Neither auto_index with existing index nor show_dir -> 404
    if self.config.proxy is Some(_) || !self.config.handle_error {
      return Next
    }
    return Handled(self.make_404_response(request))
  }

  // 5. Regular File Representation Selection & Pre-Compression
  let mut file_candidate : (String, String, String?)? = None
  let accept = header(request, "accept-encoding").unwrap_or("")

  // 5a. forceContentEncoding directly requesting .br or .gz
  if self.config.force_content_encoding {
    if path.has_suffix(".br") && path.length() > 3 {
      let exists = try
        self.exists(path) && self.kind(path) is @fs.FileKind::Regular
      catch {
        @native.NativeError::Missing => false
        e => raise e
      }
      if exists {
        let represented = path[:path.length() - 3].to_owned()
        file_candidate = Some((path, represented, Some("br")))
      }
    } else if path.has_suffix(".gz") && path.length() > 3 {
      let exists = try
        self.exists(path) && self.kind(path) is @fs.FileKind::Regular
      catch {
        @native.NativeError::Missing => false
        e => raise e
      }
      if exists {
        let represented = path[:path.length() - 3].to_owned()
        file_candidate = Some((path, represented, Some("gzip")))
      }
    }
  }

  // 5b. Pre-compressed Brotli negotiation
  if file_candidate is None &&
    self.config.brotli &&
    check_accepts_encoding(accept, "br") {
    let p = path + ".br"
    let exists = try
      self.exists(p) && self.kind(p) is @fs.FileKind::Regular
    catch {
      @native.NativeError::Missing => false
      e => raise e
    }
    if exists {
      file_candidate = Some((p, path, Some("br")))
    }
  }

  // 5c. Pre-compressed Gzip negotiation
  if file_candidate is None &&
    self.config.gzip &&
    check_accepts_encoding(accept, "gzip") {
    let p = path + ".gz"
    let exists = try
      self.exists(p) && self.kind(p) is @fs.FileKind::Regular
    catch {
      @native.NativeError::Missing => false
      e => raise e
    }
    if exists && self.has_gzip_magic(p) {
      file_candidate = Some((p, path, Some("gzip")))
    }
  }

  // 5d. Direct regular file
  if file_candidate is None {
    let exists = try
      self.exists(path) && self.kind(path) is @fs.FileKind::Regular
    catch {
      @native.NativeError::Missing => false
      e => raise e
    }
    if exists {
      file_candidate = Some((path, path, None))
    }
  }

  // 5e. Default extension completion
  if file_candidate is None && self.config.default_ext is Some(ext) {
    if !@core.has_file_extension(path) {
      let p = path + "." + ext
      let exists = try
        self.exists(p) && self.kind(p) is @fs.FileKind::Regular
      catch {
        @native.NativeError::Missing => false
        e => raise e
      }
      if exists {
        file_candidate = Some((p, p, None))
      }
    }
  }

  // 5f. If regular file found, serve it!
  match file_candidate {
    Some((chosen, represented, encoding)) =>
      return self.serve_file(request, chosen, represented, encoding)
    None => ()
  }

  // 6. SPA & Try-Files Fallback on 404 Condition
  if self.config.has_fallback() {
    let fallback_target = self.config
      .fallback_target_file()
      .unwrap_or("index.html")
    let fallback_path = normalize_root_join(self.config.root, fallback_target)
    let fallback_exists = try
      self.exists(fallback_path) &&
      self.kind(fallback_path) is @fs.FileKind::Regular
    catch {
      @native.NativeError::Missing => false
      e => raise e
    }
    if fallback_exists {
      return self.serve_file(request, fallback_path, fallback_target, None)
    } else {
      // Terminal 404: fallback file missing on disk (D-04 line 136)
      return Handled(self.make_terminal_404_response(request))
    }
  }

  if self.config.proxy is Some(_) || !self.config.handle_error {
    return Next
  }

  Handled(self.make_404_response(request))
}

///|
/// Serve a resolved regular file representation with full RFC HTTP/1.1 features:
/// ETag, Last-Modified, Cache-Control, Range (206/416), 304 freshness, HEAD suppression, D-17 mutation detection.
async fn StaticEngine::serve_file(
  self : StaticEngine,
  request : @core.Request,
  chosen : String,
  represented_path : String,
  content_encoding : String?,
) -> PlanResult {
  let file = self.open_file(chosen)
  errdefer file.close()
  if file.kind != 1 { raise ServerError::FileChanged("chosen representation became a directory") }
  if content_encoding == Some("gzip") {
    let magic=if file.size >= 2L { file.read(0L,2) } else { b"" }
    if magic.length()!=2 || magic[0]!=b'\x1f' || magic[1]!=b'\x8b' {
      raise ServerError::FileChanged("chosen gzip representation changed before opening")
    }
  }
  let file_size = file.size
  let mtime_sec = file.mtime

  let mime_type = @core.resolve_content_type(
    represented_path,
    self.mime_registry,
    "application/octet-stream",
  )

  let server_etag = @core.EntityTag::from_metadata(
    file_size,
    mtime_sec,
    self.config.weak_etags,
  )
  let etag_str = server_etag.to_header_value()
  let last_modified = @core.format_http_date(mtime_sec)
  let cache_control = self.config.effective_cache_control()

  let headers : Map[String, String] = Map([
    ("Content-Type", mime_type),
    ("Cache-Control", cache_control),
    ("Accept-Ranges", "bytes"),
    ("ETag", etag_str),
    ("Last-Modified", last_modified),
  ])

  match content_encoding {
    Some(enc) => {
      headers["Content-Encoding"] = enc
      headers["Vary"] = "Accept-Encoding"
    }
    None => ()
  }

  let mut status = 200
  let mut body : PlanBody = FileRegion(file, 0L, file_size)

  // Range evaluation (RFC 7233)
  if header(request, "if-range") is None && header(request, "range") is Some(range_header) {
    let range_result = @core.parse_range_spec(range_header, file_size)
    match range_result {
      Satisfiable(r) => {
        status = 206
        let slice_len = r.end - r.start + 1L
        headers["Content-Range"] = @core.format_content_range(
          r.start,
          r.end,
          file_size,
        )
        headers["Content-Length"] = slice_len.to_string()
        body = FileRegion(file, r.start, slice_len)
      }
      NotSatisfiable => {
        status = 416
        headers["Content-Range"] = @core.format_content_range_unsatisfiable(
          file_size,
        )
        let msg = "Requested range not satisfiable"
        let msg_bytes = @utf8.encode(msg)
        headers["Content-Type"] = "text/plain; charset=UTF-8"
        headers["Content-Length"] = msg_bytes.length().to_string()
        body = Bytes(msg_bytes)
      }
      NotApplicable => headers["Content-Length"] = file_size.to_string()
    }
  } else {
    headers["Content-Length"] = file_size.to_string()
  }

  // Conditional request evaluation (RFC 7232) -> 304 Not Modified
  if status == 200 {
    let inm = header(request, "if-none-match")
    let ims = header(request, "if-modified-since")
    if @core.should_return_304(
        inm,
        ims,
        mtime_sec,
        server_etag,
        self.config.weak_compare,
      ) {
      let fresh_headers : Map[String, String] = Map([
        ("ETag", etag_str),
        ("Last-Modified", last_modified),
        ("Cache-Control", cache_control),
        ("Content-Length", "0"),
      ])
      match content_encoding {
        Some(_) => fresh_headers["Vary"] = "Accept-Encoding"
        None => ()
      }
      @core.apply_security_headers(fresh_headers, self.config, request.meth)
      file.close()
      return Handled({
        status: 304,
        headers: fresh_headers,
        body: PlanBody::Empty,
      })
    }
  }

  // HEAD method suppresses body
  if request.meth is Head {
    body = PlanBody::Empty
  }

  // D-17 In-Flight Mutation Check
  file.check()
  if !(body is FileRegion(_, _, _)) { file.close() }

  // Apply configured security headers
  @core.apply_security_headers(headers, self.config, request.meth)

  Handled({ status, headers, body, })
}
