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
  @plan.escape_html(s)
}

///|
/// Pure HTML directory listing renderer shared with the Wasm engine.
pub fn render_directory_listing_html(
  title_path : String,
  entry_names : Array[(String, Bool)],
  raw_query? : String?,
  host? : String = "localhost",
) -> String {
  @plan.render_directory_listing_html(
    title_path,
    entry_names,
    raw_query=raw_query.unwrap_or(None),
    host~,
  )
}

///|
/// D-13: execute the same pure decision machine used by the Wasm host.
async fn StaticEngine::plan_request(
  self : StaticEngine,
  request : @core.Request,
) -> PlanResult {
  let files : Map[Int, @native.File] = Map([])
  let mut next_token = 0
  let mut retained = -1
  let mut charge = 0
  let mut retain_listing = false
  defer {
    for token, file in files {
      if token != retained {
        file.close()
      }
    }
    if !retain_listing {
      self.runtime.release(directory=true, charge)
    }
  }
  let mut step = @plan.start(self.config, request, self.mime_registry)
  for ;; {
    step = match step {
      Open(path, complete) => {
        let file = Some(self.open_file(path)) catch {
          @native.NativeError::Missing => None
          e => raise e
        }
        match file {
          None => complete(None)
          Some(file) => {
            let token = next_token
            next_token += 1
            files[token] = file
            complete(
              Some({
                token,
                kind: file.kind,
                size: file.size,
                mtime: file.mtime,
              }),
            )
          }
        }
      }
      Prefix(file, count, complete) => {
        let f = files[file.token]
        complete(
          f.read(
            0L,
            if file.size < count.to_int64() {
              file.size.to_int()
            } else {
              count
            },
          ),
        )
      }
      List(path, complete) => {
        let base = request.target.length() * 32 + 16384
        self.runtime.reserve(directory=true, base)
        charge += base
        let dir = self.open_file(path)
        defer dir.close()
        let (names, name_charge) = dir.names(
          self.config.limits.directory_metadata_bytes.to_int64(),
        )
        charge += name_charge
        let entries : Array[@plan.ListingEntry] = []
        for name in names {
          if !self.config.show_dotfiles && name.has_prefix(".") {
            continue
          }
          let file = self.open_file(path + "/" + name) catch {
            @native.NativeError::Missing => continue
            e => raise e
          }
          entries.push({
            name,
            is_dir: file.kind == 2,
            size: if file.kind == 2 {
              0L
            } else {
              file.size
            },
            mtime_sec: file.mtime,
            is_companion: false,
            has_br: false,
            has_gz: false,
          })
          file.close()
        }
        complete(entries)
      }
      Next => return Next
      Done(response) => {
        // Even HEAD/304 and generated errors must finish all opened observations.
        for file in files.values() {
          file.check()
        }
        let body = match response.body {
          Empty => PlanBody::Empty
          Bytes(bytes) => PlanBody::Bytes(bytes)
          FileRegion(file, offset, length) => {
            retained = file.token
            PlanBody::FileRegion(files[file.token], offset, length)
          }
          Listing(stream) => {
            retain_listing = true
            PlanBody::Listing({ stream, metadata_charge: charge, })
          }
        }
        return Handled({
          status: response.status,
          headers: response.headers,
          body,
        })
      }
    }
  }
}
