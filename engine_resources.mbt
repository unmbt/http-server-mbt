///|
priv struct EngineOwner { mut closing : Bool; mut planning : Int; idle : @async.CondVar }
///|
pub struct StaticEngine {
  config : @core.Config
  priv mime_registry : @core.MimeRegistry
  priv root : @native.File
  priv runtime : @native.Runtime
  priv owner : EngineOwner
  priv responses : Map[Int, BodyState]
  priv mut next_id : Int
}
///|
pub(all) enum HandleResult { Handled(Response); Next; Error(ServerError) }
///|
pub suberror ServerError {
  InvalidRequest(String)
  Forbidden(String)
  Io(String)
  FileChanged(String)
  Closed
  Busy
  Overloaded
}
///|
pub fn ServerError::invalid_request(message : String) -> ServerError { InvalidRequest(message) }
///|
pub fn ServerError::forbidden(message : String) -> ServerError { Forbidden(message) }
///|
pub fn ServerError::io(message : String) -> ServerError { Io(message) }
///|
priv enum PlanBody { Empty; Bytes(Bytes); FileRegion(@native.File, Int64, Int64); Listing(ListingStream) }
///|
priv struct ListingStream {
  entries : Array[ListingEntry]
  title : String
  query : String?
  host : String
  mut stage : Int
  mut index : Int
  mut pending : Bytes
  mut position : Int
  metadata_charge : Int
}
///|
fn ListingStream::read(self : ListingStream, limit : Int) -> Bytes {
  while self.position == self.pending.length() {
    let text = match self.stage {
      0 => { self.stage=1; listing_header(self.title, self.query) }
      1 => if self.index < self.entries.length() {
        let entry=self.entries[self.index]
        self.index += 1
        listing_row(entry,self.query)
      } else { self.stage=2; listing_footer(self.host) }
      _ => return b""
    }
    self.pending=@utf8.encode(text)
    self.position=0
  }
  let end = if self.pending.length()-self.position > limit { self.position+limit } else { self.pending.length() }
  let chunk=self.pending[self.position:end].to_owned()
  self.position=end
  chunk
}
///|
priv struct ResponsePlan { status : Int; headers : Map[String, String]; body : PlanBody }
///|
priv enum PlanResult { Handled(ResponsePlan); Next }
///|
priv struct BodyState {
  body : PlanBody
  mut cursor : Int64
  mut closed : Bool
  mut reading : Bool
  idle : @async.CondVar
  runtime : @native.Runtime
  mut body_charge : Int
  mut released : Bool
}
///|
pub struct Response {
  status : Int
  headers : Map[String, String]
  priv state : BodyState
  priv owner : EngineOwner
  priv registry : Map[Int, BodyState]
  priv id : Int
  priv block_size : Int
}
///|
/// Open and validate a Native static engine. Pair with async close, or prefer with_engine.
pub async fn StaticEngine::open(config : @core.Config) -> StaticEngine {
  config.validate()
  let runtime = @native.Runtime::new(workers=config.limits.file_workers, capacity=config.limits.queued_operations, body_bytes=config.limits.body_buffer_bytes, directory_bytes=config.limits.directory_metadata_bytes, connections=config.limits.connections)
  errdefer runtime.close()
  let root = runtime.open_root(config.root)
  let mime_registry = @core.MimeRegistry::new()
  mime_registry.set_all(config.mime_types)
  { config, mime_registry, root, runtime, owner: { closing: false, planning: 0, idle: @async.CondVar::Cond() }, responses: Map([]), next_id: 0 }
}
///|
pub async fn[T] with_engine(config : @core.Config, handler : async (StaticEngine) -> T) -> T {
  let engine = StaticEngine::open(config)
  defer engine.close()
  handler(engine)
}
///|
async fn BodyState::close(self : BodyState) -> Unit {
  self.closed = true
  @async.protect_from_cancel(() => {
    match self.body { FileRegion(file, _, _) => file.close(); _ => () }
    while self.reading { self.idle.wait() }
    match self.body {
      Listing(stream) => {
        stream.entries.clear(); stream.pending=b""; stream.position=0; stream.stage=2
        if !self.released { self.runtime.release(directory=true,stream.metadata_charge) }
      }
      _ => ()
    }
    if !self.released {
      self.runtime.release(directory=false,self.body_charge)
      self.released=true
    }
  })
}
///|
pub async fn StaticEngine::close(self : StaticEngine) -> Unit {
  self.owner.closing = true
  self.runtime.stop()
  @async.protect_from_cancel(() => {
    while self.owner.planning > 0 { self.owner.idle.wait() }
    for state in self.responses.values().to_array() { state.close() }
    self.responses.clear()
    self.root.close()
    self.runtime.close()
  })
}
///|
fn map_native_error(e : Error) -> ServerError {
  match e {
    ServerError::InvalidRequest(s) => InvalidRequest(s)
    ServerError::Forbidden(s) => Forbidden(s)
    ServerError::Io(s) => Io(s)
    ServerError::FileChanged(s) => FileChanged(s)
    ServerError::Closed => Closed
    ServerError::Busy => Busy
    ServerError::Overloaded => Overloaded
    @native.NativeError::FileChanged => FileChanged("opened representation changed")
    @native.NativeError::Forbidden => Forbidden("path is outside the root or inaccessible")
    @native.NativeError::Overloaded => Overloaded
    @native.NativeError::Closed => Closed
    @native.NativeError::Busy => Busy
    _ => Io("native file operation failed")
  }
}
///|
pub async fn StaticEngine::handle(self : StaticEngine, request : @core.Request) -> HandleResult {
  if self.owner.closing { return Error(Closed) }
  self.owner.planning += 1
  defer { self.owner.planning -= 1; self.owner.idle.broadcast() }
  let result = self.plan_request(request) catch { e => return Error(map_native_error(e)) }
  match result {
    Next => Next
    Handled(plan) => {
      let state : BodyState = { body: plan.body, cursor: 0L, closed: false, reading: false, idle: @async.CondVar::Cond(), runtime: self.runtime, body_charge: 0, released: false }
      if self.owner.closing { state.close(); return Error(Closed) }
      let charge=match plan.body { Empty => 0; Bytes(b) => b.length()*2; _ => self.config.limits.body_block_bytes*2 }
      self.runtime.reserve(directory=false,charge) catch { e => { state.close(); return Error(map_native_error(e)) } }
      state.body_charge=charge
      let id = self.next_id
      self.next_id += 1
      self.responses[id] = state
      Handled({ status: plan.status, headers: plan.headers, state, owner: self.owner, registry: self.responses, id, block_size: self.config.limits.body_block_bytes })
    }
  }
}
///|
pub fn Response::body_length(self : Response) -> Int64 {
  match self.state.body { Empty => 0L; Bytes(b) => b.length().to_int64(); FileRegion(_, _, n) => n; Listing(_) => -1L }
}
///|
/// None denotes a streaming body whose length is not precomputed.
pub fn Response::content_length(self : Response) -> Int64? {
  let n=self.body_length()
  if n<0L { None } else { Some(n) }
}
///|
/// Revalidate the representation immediately before committing response headers.
pub async fn Response::check(self : Response) -> Unit {
  if self.state.closed || self.owner.closing { raise Closed }
  if self.state.reading { raise Busy }
  self.state.reading=true
  defer { self.state.reading=false; self.state.idle.broadcast() }
  errdefer { self.state.reading=false; self.state.idle.broadcast(); self.close() }
  match self.state.body {
    FileRegion(file,_,_) => file.check() catch { e => raise map_native_error(e) }
    _ => ()
  }
}
///|
/// Read the next bounded chunk. Only successful EOF returns empty bytes.
pub async fn Response::read(self : Response, max_len? : Int = 65536) -> Bytes {
  if self.state.closed || self.owner.closing { raise Closed }
  if self.state.reading { raise Busy }
  if max_len <= 0 { raise InvalidRequest("max_len must be positive") }
  self.state.reading = true
  defer { self.state.reading = false; self.state.idle.broadcast() }
  errdefer { self.state.reading=false; self.state.idle.broadcast(); self.close() }
  let remaining = if self.state.body is Listing(_) { max_len.to_int64() } else { self.body_length() - self.state.cursor }
  let count = if remaining < max_len.to_int64() { remaining.to_int() } else { max_len }
  let count = if count > self.block_size { self.block_size } else { count }
  let chunk = match self.state.body {
    Empty => b""
    Bytes(b) => b[self.state.cursor.to_int():self.state.cursor.to_int()+count].to_owned()
    FileRegion(file, offset, _) => {
      file.check() catch { e => raise map_native_error(e) }
      file.read(offset+self.state.cursor, count) catch { e => raise map_native_error(e) }
    }
    Listing(stream) => stream.read(count)
  }
  if self.state.closed || self.owner.closing { raise Closed }
  self.state.cursor += chunk.length().to_int64()
  chunk
}
///|
/// Explicitly bounded convenience collection; normal server paths stream instead.
pub async fn Response::to_bytes(self : Response, max_bytes~ : Int) -> Bytes {
  errdefer self.close()
  if max_bytes < 0 || self.body_length()-self.state.cursor > max_bytes.to_int64() { raise Overloaded }
  let buf : Array[Byte] = []
  let mut reserved=0
  defer self.state.runtime.release(directory=false,reserved)
  for ;; {
    let chunk = self.read()
    if chunk.length() == 0 { break }
    if buf.length() > max_bytes - chunk.length() { raise Overloaded }
    // Array growth and the final contiguous copy coexist until return. Returned
    // bytes belong to the caller; engine budgets account for collection in flight.
    if chunk.length() > (2147483647-reserved)/4 { raise Overloaded }
    let charge=chunk.length()*4
    self.state.runtime.reserve(directory=false,charge) catch { e => raise map_native_error(e) }
    reserved+=charge
    for b in chunk { buf.push(b) }
  }
  Bytes::from_array(buf)
}
///|
pub async fn Response::close(self : Response) -> Unit {
  self.state.close()
  self.registry.remove(self.id)
}
///|
/// Write a body through a bounded writer; chunked is HTTP/1.1 framing only.
pub async fn Response::write_to(self : Response, writer : &@io.Writer, chunked? : Bool = false) -> Unit {
  for ;; {
    let chunk=self.read()
    if chunk.length()==0 { break }
    if chunked { writer.write(chunk.length().to_string(radix=16)+"\r\n") }
    writer.write(chunk)
    if chunked { writer.write("\r\n") }
  }
  if chunked { writer.write("0\r\n\r\n") }
}
///|
/// Send the remaining file through the socket's kernel transfer path, falling back
/// from the exact current offset when the platform reports unsupported operation.
pub async fn Response::send_to(self : Response, tcp : @socket.Tcp) -> Unit {
  match self.state.body {
    FileRegion(file, offset, length) => {
      if self.state.closed || self.owner.closing { raise Closed }
      if self.state.reading { raise Busy }
      self.state.reading = true
      defer { self.state.reading = false; self.state.idle.broadcast() }
      errdefer { self.state.reading=false; self.state.idle.broadcast(); self.close() }
      let mut kernel = true
      while self.state.cursor < length {
        if self.state.closed || self.owner.closing { raise Closed }
        let left = length-self.state.cursor
        let count = if left < self.block_size.to_int64() { left.to_int() } else { self.block_size }
        if kernel {
          let sent = file.send(tcp.fd(), offset+self.state.cursor, count) catch { e => raise map_native_error(e) }
          match sent {
            Some(n) => { self.state.cursor += n; if n == 0L { @async.sleep(1) } }
            None => kernel = false
          }
        } else {
          let chunk = file.read(offset+self.state.cursor, count) catch { e => raise map_native_error(e) }
          tcp.write(chunk)
          self.state.cursor += chunk.length().to_int64()
        }
        @async.pause()
      }
      file.check() catch { e => raise map_native_error(e) }
    }
    _ => for ;; { let chunk = self.read(); if chunk.length() == 0 { break }; tcp.write(chunk) }
  }
}
///|
fn StaticEngine::relative(self : StaticEngine, path : String) -> String raise {
  let root = normalize_root_join(self.config.root, "")
  if path == root || path == self.config.root { return "" }
  let prefix = if root.has_suffix("/") { root } else { root + "/" }
  if !path.has_prefix(prefix) { raise Forbidden("candidate outside root") }
  path[prefix.length():].to_owned()
}
///|
async fn StaticEngine::open_file(self : StaticEngine, path : String) -> @native.File {
  self.root.open(self.relative(path))
}
///|
async fn StaticEngine::exists(self : StaticEngine, path : String) -> Bool {
  let file = self.open_file(path) catch {
    @native.NativeError::Missing => return false
    e => raise e
  }
  file.close()
  true
}
///|
async fn StaticEngine::kind(self : StaticEngine, path : String) -> @fs.FileKind {
  let file = self.open_file(path)
  defer file.close()
  if file.kind == 2 { @fs.FileKind::Directory } else { @fs.FileKind::Regular }
}
///|
async fn StaticEngine::readdir(self : StaticEngine, path : String, include_hidden? : Bool = true) -> (Array[String], Int) {
  let dir = self.open_file(path)
  defer dir.close()
  // Reserve room for decoded names, entry records, maps, sort arrays and HTML row.
  let (names,charge)=dir.names(self.config.limits.directory_metadata_bytes.to_int64())
  (names.filter(name => include_hidden || !name.has_prefix(".")),charge)
}
