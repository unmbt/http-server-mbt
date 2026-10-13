///|
/// R-N10 / D-13 / T-029. A platform-neutral, suspension-explicit planner.
/// Tokens are adapter-owned leases, never file descriptors or GC addresses.
pub(all) struct File {
  token : Int
  kind : Int
  size : Int64
  mtime : Int64
}

///|
pub(all) enum Body {
  Empty
  Bytes(Bytes)
  FileRegion(File, Int64, Int64)
  Listing(ListingStream)
}

///|
pub(all) struct Response {
  status : Int
  headers : Map[String, String]
  body : Body
}

///|
pub(all) enum Step {
  Open(String, (File?) -> Step raise)
  Prefix(File, Int, (Bytes) -> Step raise)
  List(String, (Array[ListingEntry]) -> Step raise)
  Done(Response)
  Next
}

///|
pub suberror Changed

///|
pub(all) struct ListingStream {
  entries : Array[ListingEntry]
  title : String
  query : String?
  host : String
  mut stage : Int
  mut index : Int
  mut pending : Bytes
  mut position : Int
}

///|
pub fn ListingStream::read(self : ListingStream, limit : Int) -> Bytes {
  if limit <= 0 {
    return b""
  }
  while self.position == self.pending.length() {
    let text = match self.stage {
      0 => {
        self.stage = 1
        listing_header(self.title, self.query)
      }
      1 =>
        if self.index < self.entries.length() {
          let entry = self.entries[self.index]
          self.index += 1
          listing_row(entry, self.query)
        } else {
          self.stage = 2
          listing_footer(self.host)
        }
      _ => return b""
    }
    self.pending = @utf8.encode(text)
    self.position = 0
  }
  let count = Int::min(limit, self.pending.length() - self.position)
  let result = self.pending[self.position:self.position + count].to_owned()
  self.position += count
  result
}

///|
pub fn ListingStream::close(self : ListingStream) -> Unit {
  self.entries.clear()
  self.pending = b""
  self.position = 0
  self.stage = 2
}

///|
priv struct Planner {
  config : @core.Config
  request : @core.Request
  mime : @core.MimeRegistry
}

///|
fn Planner::header(self : Planner, name : String) -> String? {
  @core.find_header_case_insensitive(self.request.headers, name)
}

///|
fn join(root : String, path : String) -> String {
  let root = if root.length() > 1 &&
    (root.has_suffix("/") || root.has_suffix("\\")) {
    root[:root.length() - 1].to_owned()
  } else {
    root
  }
  if path == "" {
    root
  } else {
    root + "/" + path
  }
}

///|
fn Planner::response(
  self : Planner,
  status : Int,
  headers : Map[String, String],
  body : Body,
) -> Step {
  @core.apply_security_headers(headers, self.config, self.request.meth)
  Done({
    status,
    headers,
    body: if self.request.meth is Head {
      Empty
    } else {
      body
    },
  })
}

///|
fn Planner::text(self : Planner, status : Int, text : String) -> Step {
  let bytes = @utf8.encode(text)
  self.response(
    status,
    Map([
      ("Content-Type", "text/plain; charset=UTF-8"),
      ("Content-Length", bytes.length().to_string()),
    ]),
    Bytes(bytes),
  )
}

///|
fn Planner::terminal(self : Planner) -> Step {
  self.text(404, "File not found. :(")
}

///|
fn Planner::not_found(self : Planner) -> Step {
  Open(join(self.config.root, "404.html"), fn(file) {
    match file {
      Some(f) if f.kind == 1 =>
        self.response(
          404,
          Map([
            ("Content-Type", "text/html; charset=UTF-8"),
            ("Content-Length", f.size.to_string()),
          ]),
          FileRegion(f, 0L, f.size),
        )
      _ => self.terminal()
    }
  })
}

///|
fn accepts(value : String, encoding : String) -> Bool {
  let mut accepted = false
  for part in value.to_lower().split(",") {
    let parts = part.trim().split(";").to_array()
    let name = parts[0].trim()
    let zero = parts[1:]
      .iter()
      .any(p => {
        let p = p.trim()
        p == "q=0" || p == "q=0.0" || p == "q=0.00" || p == "q=0.000"
      })
    if zero && (name == encoding || name == "*") {
      return false
    }
    if !zero &&
      (
        name == encoding ||
        name == "*" ||
        (encoding == "gzip" && (name == "compress" || name == "deflate"))
      ) {
      accepted = true
    }
  }
  accepted
}

///|
fn Planner::representations(
  self : Planner,
  path : String,
  index : Bool,
) -> Array[(String, String, String?)] {
  let c = self.config
  let values = []
  if !index && c.force_content_encoding {
    if path.has_suffix(".br") && path.length() > 3 {
      values.push((path, path[:path.length() - 3].to_owned(), Some("br")))
    } else if path.has_suffix(".gz") && path.length() > 3 {
      values.push((path, path[:path.length() - 3].to_owned(), Some("gzip")))
    }
  }
  let accept = self.header("accept-encoding").unwrap_or("")
  if c.brotli && accepts(accept, "br") {
    values.push((path + ".br", path, Some("br")))
  }
  if c.gzip && accepts(accept, "gzip") {
    values.push((path + ".gz", path, Some("gzip")))
  }
  values.push((path, path, None))
  if !index && c.default_ext is Some(ext) && !@core.has_file_extension(path) {
    values.push((path + "." + ext, path + "." + ext, None))
  }
  values
}

///|
fn Planner::choose(
  self : Planner,
  choices : Array[(String, String, String?)],
  index : Int,
  missing : () -> Step,
) -> Step {
  if index >= choices.length() {
    return missing()
  }
  let (path, represented, encoding) = choices[index]
  Open(path, fn(file) {
    match file {
      Some(f) if f.kind == 1 =>
        if encoding == Some("gzip") {
          Prefix(f, 2, fn(bytes) raise {
            if bytes.length() == 2 && bytes[0] == b'\x1f' && bytes[1] == b'\x8b' {
              self.serve(f, represented, encoding)
            } else if index == 0 &&
              self.config.force_content_encoding &&
              path.has_suffix(".gz") &&
              represented != path {
              raise Changed
            } else {
              self.choose(choices, index + 1, missing)
            }
          })
        } else {
          self.serve(f, represented, encoding)
        }
      _ => self.choose(choices, index + 1, missing)
    }
  })
}

///|
fn Planner::serve(
  self : Planner,
  file : File,
  path : String,
  encoding : String?,
) -> Step {
  // Only uncompressed text may be sniffed; the read is bounded by D-03.
  let mime = @core.resolve_content_type(
    path,
    self.mime,
    "application/octet-stream",
  )
  if encoding is None && @core.is_text_mime(mime) && file.size > 0L {
    Prefix(file, 1024, fn(bytes) {
      self.file_response(file, path, encoding, Some(bytes))
    })
  } else {
    self.file_response(file, path, encoding, None)
  }
}

///|
fn Planner::file_response(
  self : Planner,
  file : File,
  path : String,
  encoding : String?,
  sample : Bytes?,
) -> Step {
  let c = self.config
  let mime = match sample {
    Some(bytes) =>
      @core.resolve_content_type(
        path,
        self.mime,
        "application/octet-stream",
        sample_bytes=bytes,
      )
    None =>
      @core.resolve_content_type(path, self.mime, "application/octet-stream")
  }
  let tag = @core.EntityTag::from_metadata(file.size, file.mtime, c.weak_etags)
  let headers = Map([
    ("Content-Type", mime),
    ("Cache-Control", c.effective_cache_control()),
    ("Accept-Ranges", "bytes"),
    ("ETag", tag.to_header_value()),
    ("Last-Modified", @core.format_http_date(file.mtime)),
    ("Content-Length", file.size.to_string()),
  ])
  if encoding is Some(enc) {
    headers["Content-Encoding"] = enc
    headers["Vary"] = "Accept-Encoding"
  }
  let mut status = 200
  let mut body = Body::FileRegion(file, 0L, file.size)
  if self.header("if-range") is None && self.header("range") is Some(range) {
    match @core.parse_range_spec(range, file.size) {
      Satisfiable(r) => {
        status = 206
        headers["Content-Range"] = @core.format_content_range(
          r.start,
          r.end,
          file.size,
        )
        headers["Content-Length"] = (r.end - r.start + 1L).to_string()
        body = FileRegion(file, r.start, r.end - r.start + 1L)
      }
      NotSatisfiable => {
        status = 416
        let bytes = @utf8.encode("Requested range not satisfiable")
        headers["Content-Range"] = @core.format_content_range_unsatisfiable(
          file.size,
        )
        headers["Content-Length"] = bytes.length().to_string()
        headers["Content-Type"] = "text/plain; charset=UTF-8"
        body = Bytes(bytes)
      }
      NotApplicable => ()
    }
  }
  if status == 200 &&
    @core.should_return_304(
      self.header("if-none-match"),
      self.header("if-modified-since"),
      file.mtime,
      tag,
      c.weak_compare,
    ) {
    let headers = Map([
      ("ETag", tag.to_header_value()),
      ("Last-Modified", @core.format_http_date(file.mtime)),
      ("Cache-Control", c.effective_cache_control()),
      ("Content-Length", "0"),
    ])
    if encoding is Some(_) {
      headers["Vary"] = "Accept-Encoding"
    }
    return self.response(304, headers, Empty)
  }
  self.response(status, headers, body)
}

///|
fn Planner::listing(
  self : Planner,
  path : String,
  raw_path : String,
  query : String?,
) -> Step {
  let headers = Map([("Content-Type", "text/html; charset=UTF-8")])
  if self.request.meth is Head {
    return self.response(200, headers, Empty)
  }
  List(path, fn(entries) {
    let visible = entries.filter(e => {
      self.config.show_dotfiles || !e.name.has_prefix(".")
    })
    let names = Map([])
    for entry in visible {
      names[entry.name] = entry
    }
    for entry in visible {
      if !entry.is_dir &&
        entry.name.length() > 3 &&
        (entry.name.has_suffix(".br") || entry.name.has_suffix(".gz")) {
        if names.get(entry.name[:entry.name.length() - 3].to_owned())
          is Some(base) {
          entry.is_companion = true
          if entry.name.has_suffix(".br") {
            base.has_br = true
          } else {
            base.has_gz = true
          }
        }
      }
    }
    let dirs = visible.filter(e => e.is_dir && !e.is_companion)
    let files = visible.filter(e => !e.is_dir && !e.is_companion)
    dirs.sort_by(compare_entries)
    files.sort_by(compare_entries)
    let all = []
    if path != join(self.config.root, "") {
      all.push({
        name: "..",
        is_dir: true,
        size: 0L,
        mtime_sec: 0L,
        is_companion: false,
        has_br: false,
        has_gz: false,
      })
    }
    for e in dirs {
      all.push(e)
    }
    for e in files {
      all.push(e)
    }
    self.response(
      200,
      headers,
      Listing({
        entries: all,
        title: raw_path,
        query,
        host: self.header("host").unwrap_or("localhost"),
        stage: 0,
        index: 0,
        pending: b"",
        position: 0,
      }),
    )
  })
}

///|
fn Planner::directory(
  self : Planner,
  path : String,
  raw_path : String,
  query : String?,
) -> Step {
  let c = self.config
  if !raw_path.has_suffix("/") {
    if !c.auto_index && !c.show_dir {
      return self.not_found()
    }
    return self.response(
      302,
      Map([
        ("Location", @core.format_dir_redirect(raw_path, query)),
        ("Content-Type", "text/html; charset=UTF-8"),
        ("Content-Length", "0"),
      ]),
      Empty,
    )
  }
  let missing = fn() {
    if c.show_dir {
      if !c.dir_overrides_404 && !c.has_fallback() {
        Open(join(c.root, "404.html"), fn(f) {
          if f is Some(file) && file.kind == 1 {
            self.not_found()
          } else {
            self.listing(path, raw_path, query)
          }
        })
      } else {
        self.listing(path, raw_path, query)
      }
    } else if !c.handle_error || c.proxy is Some(_) {
      Next
    } else {
      self.not_found()
    }
  }
  if c.auto_index {
    let name = join(path, "index." + c.default_ext.unwrap_or("html"))
    self.choose(self.representations(name, true), 0, missing)
  } else {
    missing()
  }
}

///|
pub fn start(
  config : @core.Config,
  request : @core.Request,
  mime : @core.MimeRegistry,
) -> Step {
  let p = Planner::{ config, request, mime, }
  match @core.evaluate_security_policies(config, request) {
    Unauthorized(headers, bytes) => {
      headers["Content-Type"] = "text/plain; charset=UTF-8"
      headers["Content-Length"] = bytes.length().to_string()
      return p.response(401, headers, Bytes(bytes))
    }
    Forbidden(headers, bytes) => {
      headers["Content-Type"] = "text/plain; charset=UTF-8"
      headers["Content-Length"] = bytes.length().to_string()
      return p.response(403, headers, Bytes(bytes))
    }
    Preflight(headers) => {
      headers["Content-Length"] = "0"
      return p.response(204, headers, Empty)
    }
    Proceed => ()
  }
  if request.meth is Other(_) {
    return Next
  }
  let parts = request.target.split("?").to_array()
  let raw_path = parts[0].to_owned()
  let query = if parts.length() > 1 { Some(parts[1].to_owned()) } else { None }
  if config.robots && raw_path == "/robots.txt" {
    let bytes = @utf8.encode("User-agent: *\nDisallow: /\n")
    return p.response(
      200,
      Map([
        ("Content-Type", "text/plain"),
        ("Content-Length", bytes.length().to_string()),
      ]),
      Bytes(bytes),
    )
  }
  let path = match
    @core.resolve_path(config.root, config.base_url, request.target) {
    Ok(path) => path
    Err(@core.PathError::OutsideBaseUrl(_)) =>
      return p.response(403, Map([("Content-Length", "0")]), Empty)
    Err(@core.PathError::TraversalForbidden(_)) =>
      return p.text(403, "Access denied")
    Err(@core.PathError::MalformedUri(_)) => return p.text(400, "Bad Request")
    Err(@core.PathError::NotFound(_)) =>
      return if config.handle_error && config.proxy is None {
        p.not_found()
      } else {
        Next
      }
  }
  Open(path, fn(file) {
    if file is Some(f) && f.kind == 2 {
      return p.directory(path, raw_path, query)
    }
    p.choose(p.representations(path, false), 0, fn() {
      if config.has_fallback() {
        let fallback = join(
          config.root,
          config.fallback_target_file().unwrap_or("index.html"),
        )
        p.choose(p.representations(fallback, true), 0, fn() { p.terminal() })
      } else if !config.handle_error || config.proxy is Some(_) {
        Next
      } else {
        p.not_found()
      }
    })
  })
}
