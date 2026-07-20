extern "c" fn ext_print_ips(port : Int) = "ext_print_ips"
extern "c" fn ext_register_ctrl_c() = "ext_register_ctrl_c"

pub(all) struct Config {
  port : Int
  addr : String
  dir_listing : Bool
  ext : String
  cache_time : Int
  cors : Bool
  proxy : String?
  root_dir : String
}

fn get_version() -> String {
  let target = "\"version\":"
  let json = moon_mod_json
  let mut idx = -1
  let mut i = 0
  while i <= json.length() - target.length() {
    let mut matched = true
    let mut j = 0
    while j < target.length() {
      if json[i + j] != target[j] {
        matched = false
        break
      }
      j += 1
    }
    if matched {
      idx = i
      break
    }
    i += 1
  }
  
  if idx >= 0 {
    let mut k = idx + target.length()
    while k < json.length() && (json[k] == ' ' || json[k] == '\t') {
      k += 1
    }
    if k < json.length() && json[k] == '"' {
      k += 1
      let start = k
      while k < json.length() && json[k] != '"' {
        k += 1
      }
      return json[start:k].to_string()
    }
  }
  "unknown"
}

fn print_banner(config : Config) -> Unit {
  let y = "\u001b[33m"
  let c = "\u001b[36m"
  let r = "\u001b[31m"
  let g = "\u001b[32m"
  let rst = "\u001b[39m"

  let cors_str = if config.cors { c + "true" + rst } else { r + "disabled" + rst }
  let dir_listing_str = if config.dir_listing { c + "visible" + rst } else { r + "not visible" + rst }
  let ext_str = if config.ext == "" { r + "none" + rst } else { c + config.ext + rst }
  
  println("\{y}Starting up http-server, serving \{rst}\{c}\{config.root_dir}\{rst}")
  println("\{y}\nhttp-server version: \{rst}\{c}\{get_version()}\{rst}")
  println("\{y}\nhttp-server settings: \{rst}")
  println("\{y}CORS: \{rst}\{cors_str}")
  println("\{y}Cache: \{rst}\{c}\{config.cache_time} seconds\{rst}")
  println("\{y}Connection Timeout: \{rst}\{c}120 seconds\{rst}")
  println("\{y}Directory Listings: \{rst}\{dir_listing_str}")
  println("\{y}AutoIndex: \{rst}\{c}visible\{rst}")
  println("\{y}Serve GZIP Files: \{rst}\{r}false\{rst}")
  println("\{y}Serve Brotli Files: \{rst}\{r}false\{rst}")
  println("\{y}Default File Extension: \{rst}\{ext_str}")
  
  println("\{y}\nAvailable on:\{rst}")
  if config.addr == "0.0.0.0" {
    println("  http://127.0.0.1:\{g}\{config.port}\{rst}")
    ext_print_ips(config.port)
  } else {
    println("  http://\{config.addr}:\{g}\{config.port}\{rst}")
  }

  match config.proxy {
    Some(proxy_url) => println("Unhandled requests will be served from: " + proxy_url)
    None => ()
  }
  
  println("Hit CTRL-C to stop the server")
}

pub async fn start_server(config : Config) -> Unit raise {
  let env_args = @env.args()
  for i = 0; i < env_args.length(); i = i + 1 {
    if env_args[i] == "-v" || env_args[i] == "--version" {
      println(get_version())
      return
    }
  }

  let addr_with_port = @socket.Addr::parse("\{config.addr}:\{config.port}")
  let server = @http.Server::Server(addr_with_port)

  print_banner(config)
  ext_register_ctrl_c()

  server.run_forever(async fn(req, reader, conn) {
    handle_request(config, req, reader, conn)
  })
}

fn get_extension(path : String) -> String {
  let mut i = path.length() - 1
  while i >= 0 {
    let ch = path[i]
    if ch == '.' {
      return path[i + 1:].to_string()
    }
    if ch == '/' || ch == '\\' {
      break
    }
    i -= 1
  }
  ""
}

fn get_mime_type(ext : String) -> String {
  match ext {
    "html" | "htm" => "text/html"
    "js" => "application/javascript"
    "css" => "text/css"
    "json" => "application/json"
    "png" => "image/png"
    "jpg" | "jpeg" => "image/jpeg"
    "gif" => "image/gif"
    "svg" => "image/svg+xml"
    "txt" => "text/plain"
    "xml" => "text/xml"
    "pdf" => "application/pdf"
    "mp4" => "video/mp4"
    "mp3" => "audio/mpeg"
    "wasm" => "application/wasm"
    _ => "application/octet-stream"
  }
}

async fn serve_file(conn : @http.ServerConnection, path : String, mime : String, cors : Bool, cache_time : Int) -> Unit {
  let bytes = try {
    @fs.read_file_to_bytes(path)
  } catch {
    _ => {
      conn.send_response(500, "Internal Server Error")
      conn.end_response()
      return
    }
  }
  
  let headers = { "Content-Type": mime, "Content-Length": bytes.length().to_string() }
  if cors {
    headers["Access-Control-Allow-Origin"] = "*"
  }
  if cache_time > 0 {
    headers["Cache-Control"] = "public, max-age=\{cache_time}"
  }

  conn.send_response(200, "OK", extra_headers=headers)
  
  let mut offset = 0
  let total = bytes.length()
  while offset < total {
    let written = conn.write_once(bytes, offset~, len=total - offset)
    if written == 0 {
      break
    }
    offset += written
  }
  
  conn.end_response()
}

async fn serve_dir_listing(conn : @http.ServerConnection, req_path : String, local_path : String) -> Unit {
  let files = try {
    @fs.read_dir(local_path)
  } catch {
    _ => {
      conn.send_response(500, "Internal Server Error")
      conn.end_response()
      return
    }
  }

  let mut html = "<html><head><title>Index of \{req_path}</title></head><body>"
  html += "<h1>Index of \{req_path}</h1><hr><ul>"
  if req_path != "/" {
    html += "<li><a href=\"../\">../</a></li>"
  }
  
  let mut i = 0
  while i < files.length() {
    let file = files[i]
    let path = if req_path.has_suffix("/") { req_path + file } else { req_path + "/" + file }
    html += "<li><a href=\"\{path}\">\{file}</a></li>"
    i += 1
  }
  
  html += "</ul><hr></body></html>"
  let headers = { "Content-Type": "text/html", "Content-Length": html.length().to_string() }
  conn.send_response(200, "OK", extra_headers=headers)
  conn.write_string(html)
  conn.end_response()
}

async fn proxy_request(conn : @http.ServerConnection, proxy_url : String, req : @http.Request, config : Config, reader : &@io.Reader) -> Unit {
  let mut proxy_base = proxy_url
  if proxy_base.has_suffix("/") {
    proxy_base = proxy_base[:proxy_base.length() - 1].to_string()
  }
  let uri = proxy_base + req.path
  let client = try {
    @http.Client::Client(uri)
  } catch {
    _ => {
      let _ = conn.send_response(502, "Bad Gateway")
      let _ = conn.end_response()
      return
    }
  }

  let extra_headers = Map::new()
  req.headers.each(fn(k, v) {
    let lower = k.to_lower()
    if lower != "host" && lower != "transfer-encoding" {
      extra_headers.set(k, v)
    }
  })

  try {
    let _ = client.request(req.meth, req.path, extra_headers=extra_headers)
    let _ = client.write_reader(reader)
    let res = client.end_request()

    let _ = conn.send_response(res.code, res.reason, extra_headers=res.headers)
    let _ = conn.write_reader(client)
    let _ = conn.end_response()
  } catch {
    _ => {
      let _ = conn.send_response(502, "Bad Gateway")
      let _ = conn.end_response()
    }
  }
  client.close()
}

async fn handle_request(
  config : Config,
  req : @http.Request,
  reader : &@io.Reader,
  conn : @http.ServerConnection
) -> Unit {
  let mut req_path = req.path
  
  if req_path.contains("?") {
    let mut i = 0
    while i < req_path.length() {
      if req_path[i] == '?' {
        req_path = req_path[:i].to_string()
        break
      }
      i += 1
    }
  }
  
  println("[\{@debug.to_string(req.meth)}] \{req_path}")
  
  if req_path.contains("..") {
    conn.send_response(403, "Forbidden")
    conn.end_response()
    return
  }

  let mut local_path = config.root_dir
  if local_path.has_suffix("/") == false && local_path.has_suffix("\\") == false {
    local_path += "/"
  }
  if req_path.has_prefix("/") {
    local_path += req_path[1:].to_string()
  } else {
    local_path += req_path
  }

  let is_dir = try { @fs.is_dir(local_path) } catch { _ => false }
  
  if is_dir {
    let index_file = local_path + (if local_path.has_suffix("/") { "index.html" } else { "/index.html" })
    let has_index = try { @fs.is_file(index_file) } catch { _ => false }
    if has_index {
      serve_file(conn, index_file, "text/html", config.cors, config.cache_time)
      return
    }

    if config.dir_listing {
      serve_dir_listing(conn, req_path, local_path)
      return
    }
  } else {
    let is_file = try { @fs.is_file(local_path) } catch { _ => false }
    if is_file {
      let mut ext = get_extension(local_path)
      if ext == "" {
        ext = config.ext
      }
      let mime = get_mime_type(ext)
      serve_file(conn, local_path, mime, config.cors, config.cache_time)
      return
    }
  }

  match config.proxy {
    Some(proxy_url) => proxy_request(conn, proxy_url, req, config, reader)
    None => {
      let content = "Not Found"
      conn.send_response(404, "Not Found", extra_headers={"Content-Length": content.length().to_string()})
      conn.write_string(content)
      conn.end_response()
    }
  }
}
