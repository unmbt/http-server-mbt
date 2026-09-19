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
/// Non-Windows C-ABI backends (native/llvm): real sendfile on Linux
/// (transmit_file_linux.c), graceful stubs on other Unix so callers degrade
/// to the bounded-buffer path. The path is passed as UTF-8 null-terminated
/// Bytes for POSIX open(2).
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
/// Non-C-ABI targets (e.g. wasm): graceful placeholders with the same
/// signatures, so the server package stays interface-evaluable everywhere.
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
/// Open the platform zero-copy backend. Windows consumes the UTF-16 String
/// directly (wchar_t*); other platforms encode to UTF-8 Bytes first.
#cfg(platform="windows")
#borrow(path)
fn tf_backend_open(
  sock : @types.Fd,
  path : String,
  offset : Int64,
  length : Int64,
) -> Int64 {
  let _ = @utf8.encode("")
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
/// Transmit a file region over a socket using platform zero-copy:
/// Win32 TransmitFile on Windows Native, sendfile(2) on Linux.
/// Returns 0 on success, or negative error code:
/// -1: file open error or invalid range
/// -2: client disconnected
/// -3: D-17 FILE_CHANGED (file modified or size changed during transfer)
/// -4: I/O or transfer error
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
      continue
    } else if ret == 2 {
      @async.sleep(2)
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
