///|
/// D-13/T-029: private JSON control bridge. Bodies never use JSON except small
/// generated chunks. Int64 metadata is decimal text, not a JS Number.
priv struct Pending {
  mut step : @plan.Step
  mut serial : Int
}

///|
let requests : Map[Int, Pending] = Map([])

///|
let configurations : Array[@core.Config] = []

///|
let mimes : Array[@core.MimeRegistry] = []

///|
priv suberror ProtocolError

///|
pub fn abi_version() -> Int {
  1
}

///|
fn error_json(error : Error) -> String {
  (
    {
      "kind": "error",
      "code": if error is @plan.Changed {
        "FILE_CHANGED"
      } else {
        "INVALID_REQUEST"
      },
      "message": error.to_string(),
    } : Json).stringify()
}

///|
pub fn configure(text : String) -> String {
  try {
    guard configurations.is_empty() else { raise ProtocolError }
    let config = @plan.decode_config(@json.parse(text))
    configurations.push(config)
    let mime = @core.MimeRegistry::new()
    mime.set_all(config.mime_types)
    mimes.push(mime)
    (
      {
        "kind": "configured",
        "limits": {
          "file_workers": config.limits.file_workers,
          "queued_operations": config.limits.queued_operations,
          "connections": config.limits.connections,
          "body_block_bytes": config.limits.body_block_bytes,
          "body_buffer_bytes": config.limits.body_buffer_bytes,
          "directory_metadata_bytes": config.limits.directory_metadata_bytes,
        },
        "fallback": match config.fallback_target_file() {
          Some(s) => s.to_json()
          None => Json::null()
        },
      } : Json).stringify()
  } catch {
    e => error_json(e)
  }
}

///|
fn text_field(value : Json, key : String) -> String raise {
  guard value is Object(obj) && obj.get(key) is Some(String(s)) else {
    raise ProtocolError
  }
  s
}

///|
fn number_field(value : Json, key : String) -> Int raise {
  guard value is Object(obj) &&
    obj.get(key) is Some(Number(n, ..)) &&
    n >= 0 &&
    n <= 2147483647 &&
    n.to_int().to_double() == n else {
    raise ProtocolError
  }
  n.to_int()
}

///|
fn file_of(value : Json) -> @plan.File raise {
  {
    token: number_field(value, "token"),
    kind: number_field(value, "type"),
    size: @string.parse_int64(text_field(value, "size")),
    mtime: @string.parse_int64(text_field(value, "mtime")),
  }
}

///|
fn emit(id : Int, p : Pending) -> String {
  let value : Json = match p.step {
    Open(path, _) =>
      { "kind": "open", "id": id, "serial": p.serial, "path": path }
    Prefix(file, count, _) =>
      {
        "kind": "prefix",
        "id": id,
        "serial": p.serial,
        "token": file.token,
        "count": count,
      }
    List(path, _) =>
      { "kind": "list", "id": id, "serial": p.serial, "path": path }
    Next => { "kind": "next" }
    Done(response) => {
      let headers : Array[Json] = []
      for k, v in response.headers {
        headers.push([k.to_json(), v.to_json()])
      }
      let body : Json = match response.body {
        Empty => { "type": "empty", "length": "0" }
        Bytes(bytes) =>
          { "type": "bytes", "length": bytes.length().to_string() }
        Listing(_) => { "type": "listing", "length": Json::null() }
        FileRegion(f, offset, length) =>
          {
            "type": "file",
            "token": f.token,
            "offset": offset.to_string(),
            "length": length.to_string(),
          }
      }
      {
        "kind": "handled",
        "status": response.status,
        "headers": headers,
        "body": body,
      }
    }
  }
  value.stringify()
}

///|
pub fn begin_request(id : Int, text : String) -> String {
  try {
    guard !configurations.is_empty() && !requests.contains(id) && id >= 0 else {
      raise ProtocolError
    }
    let value = @json.parse(text)
    let verb = text_field(value, "method")
    let target = text_field(value, "target")
    guard @request_headers.token(verb) &&
      !target.is_empty() &&
      !target.iter().any(c => c <= ' ' || c == '\u007f') else {
      raise ProtocolError
    }
    let headers : Map[String, String] = Map([])
    guard value is Object(obj) && obj.get("headers") is Some(Array(items)) else {
      raise ProtocolError
    }
    for pair in items {
      guard pair is [String(name), String(value)] else { raise ProtocolError }
      @request_headers.add(headers, name, value)
    }
    guard !(headers.contains("content-length") &&
      headers.contains("transfer-encoding")) else {
      raise ProtocolError
    }
    let request : @core.Request = {
      meth: match verb {
        "GET" => Get
        "HEAD" => Head
        _ => Other(verb)
      },
      target,
      headers,
    }
    let pending = Pending::{
      step: @plan.start(configurations[0], request, mimes[0]),
      serial: 0,
    }
    requests[id] = pending
    emit(id, pending)
  } catch {
    e => error_json(e)
  }
}

///|
pub fn complete(id : Int, serial : Int, text : String) -> String {
  try {
    guard requests.get(id) is Some(p) && p.serial == serial else {
      raise ProtocolError
    }
    let value = @json.parse(text)
    p.step = match p.step {
      Open(_, k) => k(if value is Null { None } else { Some(file_of(value)) })
      Prefix(_, _, k) => {
        guard value is Array(items) else { raise ProtocolError }
        let bytes = []
        for item in items {
          guard item is Number(n, ..) &&
            n >= 0 &&
            n <= 255 &&
            n.to_int().to_double() == n else {
            raise ProtocolError
          }
          bytes.push(n.to_int().to_byte())
        }
        k(Bytes::from_array(bytes))
      }
      List(_, k) => {
        guard value is Array(items) else { raise ProtocolError }
        let entries : Array[@plan.ListingEntry] = []
        for item in items {
          let file = file_of(item)
          entries.push({
            name: text_field(item, "name"),
            is_dir: file.kind == 2,
            size: file.size,
            mtime_sec: file.mtime,
            is_companion: false,
            has_br: false,
            has_gz: false,
          })
        }
        k(entries)
      }
      _ => raise ProtocolError
    }
    p.serial += 1
    emit(id, p)
  } catch {
    e => error_json(e)
  }
}

///|
pub fn take_chunk(id : Int, offset : Int, count : Int) -> String {
  try {
    guard requests.get(id) is Some(p) &&
      p.step is Done(response) &&
      offset >= 0 &&
      count > 0 &&
      count <= configurations[0].limits.body_block_bytes else {
      raise ProtocolError
    }
    let bytes = match response.body {
      Empty => b""
      Bytes(bytes) => {
        guard offset <= bytes.length() else { raise ProtocolError }
        bytes[offset:offset + Int::min(count, bytes.length() - offset)].to_owned()
      }
      Listing(stream) => stream.read(count)
      _ => raise ProtocolError
    }
    let values : Array[Json] = []
    for b in bytes {
      values.push(b.to_int().to_json())
    }
    values.to_json().stringify()
  } catch {
    e => error_json(e)
  }
}

///|
pub fn release(id : Int) -> Unit {
  requests.remove(id)
}
