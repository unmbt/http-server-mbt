///|
#external
type Pool
///|
pub extern "C" fn process_handles() -> UInt = "hs_io_process_handles"
///|
#external
priv type Job
///|
#external
type Handle
///|
extern "C" fn pool_new(workers : Int, capacity : Int, notify : @types.Fd, body : Int, directory : Int) -> Pool = "hs_io_pool_new"
///|
extern "C" fn reserve(pool : Pool, directory : Bool, bytes : Int) -> Bool = "hs_io_reserve"
///|
extern "C" fn release(pool : Pool, directory : Bool, bytes : Int) = "hs_io_release"
///|
extern "C" fn connection_limit(pool : Pool, limit : Int) = "hs_io_connection_limit"
///|
pub extern "C" fn try_acquire_connection() -> Bool = "hs_io_connection_acquire"
///|
pub extern "C" fn release_connection() = "hs_io_connection_release"
///|
pub fn connection_available() -> Bool {
  if !try_acquire_connection() { return false }
  release_connection()
  true
}
///|
pub extern "C" fn try_acquire_body(bytes : Int) -> Bool = "hs_io_body_acquire"
///|
pub extern "C" fn release_body(bytes : Int) = "hs_io_body_release"
///|
pub extern "C" fn shutdown_write(socket : @types.Fd) -> Bool = "hs_io_shutdown_write"
///|
extern "C" fn pool_free(pool : Pool) = "hs_io_pool_free"
///|
extern "C" fn acknowledge(pool : Pool) = "hs_io_ack"
///|
#borrow(path)
extern "C" fn submit(pool : Pool, operation : Int, file : Handle, path : Bytes, offset : Int64, length : Int, socket : @types.Fd) -> Job = "hs_io_submit"
///|
extern "C" fn job_null(job : Job) -> Bool = "hs_io_null"
///|
extern "C" fn pool_null(pool : Pool) -> Bool = "hs_io_null"
///|
extern "C" fn done(job : Job) -> Bool = "hs_io_done"
///|
extern "C" fn cancel(job : Job) = "hs_io_cancel"
///|
extern "C" fn code(job : Job) -> Int = "hs_io_code"
///|
extern "C" fn value(job : Job) -> Int64 = "hs_io_value"
///|
extern "C" fn take_file(job : Job) -> Handle = "hs_io_take_file"
///|
extern "C" fn bytes(job : Job) -> Bytes = "hs_io_bytes"
///|
extern "C" fn names_count(job : Job) -> Int = "hs_io_names_count"
///|
extern "C" fn take_directory_charge(job : Job) -> Int = "hs_io_take_directory_charge"
///|
extern "C" fn name(job : Job, index : Int) -> Bytes = "hs_io_name"
///|
extern "C" fn job_free(job : Job) = "hs_io_job_free"
///|
extern "C" fn file_free(file : Handle) = "hs_io_file_free"
///|
extern "C" fn file_kind(file : Handle) -> Int = "hs_io_file_kind"
///|
extern "C" fn file_size(file : Handle) -> Int64 = "hs_io_file_size"
///|
extern "C" fn file_time(file : Handle) -> Int64 = "hs_io_file_time"
///|
extern "C" fn no_file() -> Handle = "hs_io_no_file"
///|
#cfg(platform="windows")
extern "C" fn no_socket() -> @types.Fd = "hs_io_no_file"
///|
#cfg(not(platform="windows"))
fn no_socket() -> @types.Fd { 0 }

///|
pub suberror NativeError {
  FileChanged
  Forbidden
  Missing
  Io
  Overloaded
  Closed
  Busy
  Unsupported
}

///|
pub struct Runtime {
  pool : Pool
  reader : @pipe.PipeRead
  writer : @pipe.PipeWrite
  gate : @async.Mutex
  idle : @async.CondVar
  mut active : Int
  mut closing : Bool
  mut closed : Bool
  priv jobs : Map[Int, Job]
  mut next_id : Int
}

///|
pub fn Runtime::new(workers~ : Int, capacity~ : Int, body_bytes? : Int = 67108864, directory_bytes? : Int = 67108864, connections? : Int = 1024) -> Runtime raise {
  let (reader, writer) = @pipe.pipe()
  let pool = pool_new(workers, capacity, writer.fd(), body_bytes, directory_bytes)
  if pool_null(pool) {
    reader.close()
    writer.close()
    raise Overloaded
  }
  connection_limit(pool,connections)
  { pool, reader, writer, gate: @async.Mutex(), idle: @async.CondVar::Cond(), active: 0, closing: false, closed: false, jobs: Map([]), next_id: 0 }
}
///|
pub fn Runtime::reserve(self : Runtime, directory~ : Bool, bytes : Int) -> Unit raise {
  if self.closing { raise Closed }
  if !reserve(self.pool,directory,bytes) { raise Overloaded }
}
///|
pub fn Runtime::release(self : Runtime, directory~ : Bool, bytes : Int) -> Unit {
  if !self.closed { release(self.pool,directory,bytes) }
}

///|
async fn Runtime::wait(self : Runtime, job : Job) -> Unit {
  while !done(job) {
    self.gate.acquire()
    let result = try {
      if !done(job) { ignore(self.reader.read_exactly(1)); acknowledge(self.pool) }
      Ok(())
    } catch { e => Err(e) }
    self.gate.release()
    match result { Ok(_) => (); Err(e) => raise e }
  }
}

///|
async fn[T] Runtime::run(self : Runtime, job : Job, extract : (Job) -> T) -> T {
  if job_null(job) { raise Overloaded }
  let id = self.next_id
  self.next_id += 1
  self.jobs[id] = job
  self.active += 1
  defer {
    self.jobs.remove(id)
    job_free(job)
    self.active -= 1
    self.idle.broadcast()
  }
  errdefer {
    cancel(job)
    @async.protect_from_cancel(() => self.wait(job))
  }
  self.wait(job)
  match code(job) {
    0 => extract(job)
    -3 => raise FileChanged
    -5 => raise Forbidden
    -6 => raise Missing
    -7 => raise Overloaded
    -9 => raise Closed
    -8 => raise Unsupported
    _ => raise Io
  }
}

///|
pub fn Runtime::stop(self : Runtime) -> Unit {
  self.closing = true
  for job in self.jobs.values() { cancel(job) }
}

///|
pub async fn Runtime::close(self : Runtime) -> Unit {
  if self.closed { return }
  self.closing = true
  for job in self.jobs.values() { cancel(job) }
  @async.protect_from_cancel(() => {
    while self.active > 0 { self.idle.wait() }
    if !self.closed {
      self.closed = true
      pool_free(self.pool)
      self.reader.close()
      self.writer.close()
    }
  })
}

///|
pub struct File {
  runtime : Runtime
  handle : Handle
  kind : Int
  size : Int64
  mtime : Int64
  mut closed : Bool
  mut closing : Bool
  mut active : Int
  idle : @async.CondVar
  priv jobs : Map[Int, Job]
  mut next_id : Int
}

///|
fn File::wrap(runtime : Runtime, handle : Handle) -> File {
  { runtime, handle, kind: file_kind(handle), size: file_size(handle), mtime: file_time(handle), closed: false, closing: false, active: 0, idle: @async.CondVar::Cond(), jobs: Map([]), next_id: 0 }
}

///|
pub async fn Runtime::open_root(self : Runtime, path : String) -> File {
  if self.closing { raise Closed }
  if path.contains("\u0000") { raise Forbidden }
  let handle = self.run(submit(self.pool, 0, no_file(), @utf8.encode(path), 0L, 0, no_socket()), take_file)
  File::wrap(self, handle)
}

///|
async fn[T] File::run(self : File, operation : Int, path : String, offset : Int64, length : Int, sock : @types.Fd, extract : (Job) -> T) -> T {
  if self.closing || self.runtime.closing { raise Closed }
  let job = submit(self.runtime.pool, operation, self.handle, @utf8.encode(path), offset, length, sock)
  if job_null(job) { raise Overloaded }
  let id = self.next_id
  self.next_id += 1
  self.jobs[id] = job
  self.active += 1
  defer { self.jobs.remove(id); self.active -= 1; self.idle.broadcast() }
  self.runtime.run(job, extract)
}

///|
pub async fn File::open(self : File, relative : String) -> File {
  if relative.contains("\u0000") || relative.has_prefix("/") || relative.has_prefix("\\") || relative.contains(":") { raise Forbidden }
  for part in relative.split("/") { if part == ".." { raise Forbidden } }
  let handle = self.run(0, relative, 0L, 0, no_socket(), take_file)
  File::wrap(self.runtime, handle)
}

///|
pub async fn File::check(self : File) -> Unit {
  self.run(2, "", 0L, 0, no_socket(), _ => ())
}

///|
pub async fn File::read(self : File, offset : Int64, length : Int) -> Bytes {
  self.run(1, "", offset, length, no_socket(), bytes)
}

///|
pub async fn File::names(self : File, budget : Int64) -> (Array[String], Int) {
  if self.active > 0 { raise Busy }
  self.run(3, "", budget, 0, no_socket(), job => {
    let names=Array::makei(names_count(job), i => @utf8.decode_lossy(name(job, i)))
    (names,take_directory_charge(job))
  })
}

///|
/// None means the kernel path is unsupported before sending any of this chunk.
pub async fn File::send(self : File, socket : @types.Fd, offset : Int64, length : Int) -> Int64? {
  Some(self.run(4, "", offset, length, socket, value)) catch {
    Unsupported => None
    e => raise e
  }
}

///|
pub async fn File::close(self : File) -> Unit {
  self.closing = true
  for job in self.jobs.values() { cancel(job) }
  @async.protect_from_cancel(() => {
    while self.active > 0 { self.idle.wait() }
    if !self.closed { self.closed = true; file_free(self.handle) }
  })
}
