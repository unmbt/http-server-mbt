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
#cfg(not(platform="windows"))
fn http_server_tf_open_c(
  _sock : @types.Fd,
  _path : String,
  _offset : Int64,
  _length : Int64,
) -> Int64 {
  0L
}

///|
#cfg(not(platform="windows"))
fn http_server_tf_step_c(_state : Int64) -> Int {
  -1
}

///|
#cfg(not(platform="windows"))
fn http_server_tf_close_c(_state : Int64) -> Unit {
  ()
}

///|
#cfg(not(platform="windows"))
fn http_server_get_handle_count_c() -> UInt {
  0U
}

///|
/// Transmit a file region over a socket using Win32 TransmitFile zero-copy on Windows Native.
/// Returns 0 on success, or negative error code:
/// -1: file open error or invalid range
/// -2: client disconnected
/// -3: D-17 FILE_CHANGED (file modified or size changed during transfer)
/// -4: I/O or TransmitFile error
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
  let state = http_server_tf_open_c(sock, path, offset, length)
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
      continue
    } else if ret == 2 {
      @async.pause()
      continue
    } else {
      return ret
    }
  }
  0
}

///|
/// Get the current process open handle count for empirical handle leak verification.
pub fn get_handle_count() -> UInt {
  http_server_get_handle_count_c()
}
