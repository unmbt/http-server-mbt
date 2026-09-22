///|
#cfg(platform="windows")
#borrow(path)
extern "C" fn http_server_tf_open_c(
  sock : @types.Fd,
  path : String,
  offset : Int64,
  length : Int64,
) -> Int64 = "http_server_tf_open"

///|
#cfg(platform="windows")
extern "C" fn http_server_tf_step_c(state : Int64) -> Int = "http_server_tf_step"

///|
#cfg(platform="windows")
extern "C" fn http_server_tf_close_c(state : Int64) -> Unit = "http_server_tf_close"

///|
#cfg(platform="windows")
extern "C" fn http_server_get_handle_count_c() -> UInt = "http_server_get_handle_count"

///|
#cfg(all(not(platform="windows"), any(target="native", target="llvm")))
#borrow(path)
extern "C" fn http_server_tf_open_c(
  sock : @types.Fd,
  path : Bytes,
  offset : Int64,
  length : Int64,
) -> Int64 = "http_server_tf_open"

///|
#cfg(all(not(platform="windows"), any(target="native", target="llvm")))
extern "C" fn http_server_tf_step_c(state : Int64) -> Int = "http_server_tf_step"

///|
#cfg(all(not(platform="windows"), any(target="native", target="llvm")))
extern "C" fn http_server_tf_close_c(state : Int64) -> Unit = "http_server_tf_close"

///|
#cfg(all(not(platform="windows"), any(target="native", target="llvm")))
extern "C" fn http_server_get_handle_count_c() -> UInt = "http_server_get_handle_count"

///|
#cfg(all(not(platform="windows"), not(any(target="native", target="llvm"))))
fn http_server_tf_open_c(
  _sock : @types.Fd,
  _path : Bytes,
  _offset : Int64,
  _length : Int64,
) -> Int64 {
  0L
}

///|
#cfg(all(not(platform="windows"), not(any(target="native", target="llvm"))))
fn http_server_tf_step_c(_state : Int64) -> Int {
  -1
}

///|
#cfg(all(not(platform="windows"), not(any(target="native", target="llvm"))))
fn http_server_tf_close_c(_state : Int64) -> Unit {
  ()
}

///|
#cfg(all(not(platform="windows"), not(any(target="native", target="llvm"))))
fn http_server_get_handle_count_c() -> UInt {
  0U
}

///|
#cfg(platform="windows")
#borrow(path)
fn tf_backend_open(
  sock : @types.Fd,
  path : String,
  offset : Int64,
  length : Int64,
) -> Int64 {
  http_server_tf_open_c(sock, path, offset, length)
}

///|
#cfg(not(platform="windows"))
#borrow(path)
fn tf_backend_open(
  sock : @types.Fd,
  path : String,
  offset : Int64,
  length : Int64,
) -> Int64 {
  http_server_tf_open_c(sock, @utf8.encode(path), offset, length)
}

///|
/// Send a file region through the platform kernel transfer backend.
/// Returns zero on success and a negative backend code on failure.
pub async fn transmit_file(
  sock : @types.Fd,
  path : String,
  offset : Int64,
  length : Int64,
) -> Int {
  if offset < 0L || length < 0L {
    return -1
  }
  if length == 0L {
    return 0
  }
  let state = tf_backend_open(sock, path, offset, length)
  if state == 0L {
    return -1
  }
  defer http_server_tf_close_c(state)
  for ;; {
    let ret = http_server_tf_step_c(state)
    if ret == 0 {
      return 0
    } else if ret == 1 {
      @async.pause()
    } else if ret == 2 {
      @async.sleep(2)
    } else {
      return ret
    }
  }
  0
}

///|
/// Return the process handle count used by native resource probes.
pub fn get_handle_count() -> UInt {
  http_server_get_handle_count_c()
}
