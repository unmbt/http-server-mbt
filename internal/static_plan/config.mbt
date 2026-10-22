///|
priv suberror InvalidConfig

///|
fn str(value : Json) -> String raise {
  guard value is String(s) else { raise InvalidConfig }
  s
}

///|
fn boolean(value : Json) -> Bool raise {
  guard value is True || value is False else { raise InvalidConfig }
  value is True
}

///|
fn integer(value : Json) -> Int32 raise {
  guard value is Number(n, ..) &&
    n >= -2147483648.0 &&
    n <= 2147483647.0 &&
    n.to_int().to_double() == n else {
    raise InvalidConfig
  }
  n.to_int()
}

///|
fn optional_string(value : Json) -> String? raise {
  if value is Null {
    None
  } else {
    Some(str(value))
  }
}

///|
fn string_map(value : Json) -> Map[String, String] raise {
  guard value is Object(obj) else { raise InvalidConfig }
  let result = Map([])
  for k, v in obj {
    result[k] = str(v)
  }
  result
}

///|
pub fn decode_config(value : Json) -> @core.Config raise {
  guard value is Object(obj) else { raise InvalidConfig }
  let root = match obj.get("root") {
    Some(v) => str(v)
    None => "."
  }
  let mut c = @core.Config::middleware_default(root)
  for key, v in obj {
    if [
        "port", "address", "idle_timeout_ms", "cert_file", "key_file", "key_passphrase",
        "ca_file", "secure", "proxy", "proxy_all", "proxy_options", "proxy_config",
        "websocket", "silent", "log_ip",
      ].contains(key) {
      raise InvalidConfig
    }
    c = match key {
      "root" => { ..c, root: str(v), }
      "port" => { ..c, port: integer(v), }
      "address" => { ..c, address: str(v), }
      "base_url" => { ..c, base_url: @core.normalize_base_url(str(v)), }
      "default_ext" => { ..c, default_ext: optional_string(v), }
      "spa" => { ..c, spa: boolean(v), }
      "try_files" => { ..c, try_files: optional_string(v), }
      "gzip" => { ..c, gzip: boolean(v), }
      "brotli" => { ..c, brotli: boolean(v), }
      "force_content_encoding" => { ..c, force_content_encoding: boolean(v), }
      "auto_index" => { ..c, auto_index: boolean(v), }
      "show_dir" => { ..c, show_dir: boolean(v), }
      "show_dotfiles" => { ..c, show_dotfiles: boolean(v), }
      "dir_overrides_404" => { ..c, dir_overrides_404: boolean(v), }
      "cache_seconds" => { ..c, cache_seconds: integer(v), }
      "cache_control" => { ..c, cache_control: optional_string(v), }
      "weak_etags" => { ..c, weak_etags: boolean(v), }
      "weak_compare" => { ..c, weak_compare: boolean(v), }
      "cors" => { ..c, cors: boolean(v), }
      "cors_headers" => { ..c, cors_headers: optional_string(v), }
      "coop" => { ..c, coop: boolean(v), }
      "coop_header" => { ..c, coop_header: optional_string(v), }
      "pna" => { ..c, pna: boolean(v), }
      "robots" => { ..c, robots: boolean(v), }
      "handle_error" => { ..c, handle_error: boolean(v), }
      "idle_timeout_ms" => { ..c, idle_timeout_ms: integer(v), }
      "mime_types" => { ..c, mime_types: string_map(v), }
      "custom_headers" => { ..c, custom_headers: string_map(v), }
      "basic_auth" => {
        guard v is [String(user), String(password)] else { raise InvalidConfig }
        { ..c, basic_auth: Some((user, password)), }
      }
      "host_whitelist" => {
        guard v is Array(items) else { raise InvalidConfig }
        let hosts = []
        for item in items {
          hosts.push(str(item))
        }
        { ..c, host_whitelist: hosts, }
      }
      "cert_file" => { ..c, cert_file: optional_string(v), }
      "key_file" => { ..c, key_file: optional_string(v), }
      "key_passphrase" => { ..c, key_passphrase: optional_string(v), }
      "ca_file" => { ..c, ca_file: optional_string(v), }
      "secure" => { ..c, secure: boolean(v), }
      "proxy" => { ..c, proxy: optional_string(v), }
      "proxy_all" => { ..c, proxy_all: optional_string(v), }
      "proxy_options" => { ..c, proxy_options: string_map(v), }
      "proxy_config" => { ..c, proxy_config: optional_string(v), }
      "websocket" => { ..c, websocket: boolean(v), }
      "silent" => { ..c, silent: boolean(v), }
      "log_ip" => { ..c, log_ip: boolean(v), }
      "limits" => {
        guard v is Object(fields) else { raise InvalidConfig }
        let mut l = c.limits
        for name, number in fields {
          let n = integer(number)
          l = match name {
            "file_workers" => { ..l, file_workers: n, }
            "queued_operations" => { ..l, queued_operations: n, }
            "connections" => { ..l, connections: n, }
            "body_block_bytes" => { ..l, body_block_bytes: n, }
            "body_buffer_bytes" => { ..l, body_buffer_bytes: n, }
            "directory_metadata_bytes" => { ..l, directory_metadata_bytes: n, }
            _ => raise InvalidConfig
          }
        }
        { ..c, limits: l, }
      }
      _ => raise InvalidConfig
    }
  }

  if c.has_tls() || c.has_proxy() || c.websocket {
    raise InvalidConfig
  }
  c.validate()
  c
}
