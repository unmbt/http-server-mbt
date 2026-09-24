// TLS connection transport: bridges the MbedTLS connection object to the
// moonbitlang/async I/O world. The connection owns two bounded ciphertext
// rings inside the C bridge; ciphertext moves between those rings and the
// underlying socket through this transport, with WANT_READ/WANT_WRITE mapped
// to async waits (D-05 bounded-buffer path).

///|
/// A TLS connection over an existing transport (e.g. a TCP connection).
/// Implements `@io.Reader` and `@io.Writer`, so it can feed the HTTP layer.
/// Owned by the acceptor side of the connection loop; `close` releases the
/// underlying MbedTLS state (a GC finalizer is registered as a backstop).
#warnings("-alert_internal")
pub struct TlsConn {
  handle : Int64
  obj : ConnObj
  reader : &@io.Reader
  writer : &@io.Writer
  rb : @io.ReaderBuffer
  in_scratch : FixedArray[Byte]
  out_scratch : FixedArray[Byte]
  input_gate : @async.Mutex
  output_gate : @async.Mutex
  mut closed : Bool
}

///|
const RECORD_CAP : Int = 16384

///|
const DRAIN_CAP : Int = 16384 + 512

///|
/// ReaderBuffer and its constructor are marked internal by moonbitlang/async,
/// but implementing the `@io.Reader` trait requires them; the marker is
/// warning-level and the usage below only wraps an always-empty cache buffer.
#warnings("-alert_internal")
fn TlsConn::create(
  acceptor_handle : Int64,
  hostname : Bytes,
  reader : &@io.Reader,
  writer : &@io.Writer,
) -> TlsConn raise TlsError {
  let hostname_len = if hostname.length() == 0 {
    0
  } else {
    hostname.length() + 1
  }
  let handle = tls_conn_new_c(acceptor_handle, hostname, hostname_len)
  if handle <= 0 {
    raise TlsError::from_bridge(handle.to_int())
  }
  {
    handle,
    obj: tls_conn_wrap_c(handle),
    reader,
    writer,
    rb: @io.ReaderBuffer::new(),
    in_scratch: FixedArray::make(RECORD_CAP, b'\x00'),
    out_scratch: FixedArray::make(DRAIN_CAP, b'\x00'),
    input_gate: @async.Mutex(),
    output_gate: @async.Mutex(),
    closed: false,
  }
}

///|
/// Server-side handshake for an accepted transport.
pub async fn TlsAcceptor::accept(
  self : TlsAcceptor,
  reader~ : &@io.Reader,
  writer~ : &@io.Writer,
) -> TlsConn {
  let conn = TlsConn::create(self.handle, b"", reader, writer)
  errdefer conn.close()
  conn.handshake()
  conn
}

///|
/// Client-side handshake. `hostname` is used for SNI and certificate
/// verification.
pub async fn TlsAcceptor::connect(
  self : TlsAcceptor,
  hostname : String,
  reader~ : &@io.Reader,
  writer~ : &@io.Writer,
) -> TlsConn {
  let conn = TlsConn::create(
    self.handle,
    @utf8.encode(hostname),
    reader,
    writer,
  )
  errdefer conn.close()
  conn.handshake()
  conn
}

///|
/// Drive the handshake to completion, moving ciphertext between the bridge
/// rings and the underlying transport as requested.
async fn TlsConn::handshake(self : TlsConn) -> Unit {
  for ;; {
    let r = tls_handshake_c(self.handle)
    if r == 0 {
      break
    }
    if r == -1 {
      self.drain_output()
      guard self.feed_input() else { raise TlsUnexpectedEof }
    } else if r == -2 {
      self.drain_output()
    } else if r < 0 {
      raise TlsError::from_bridge(r)
    }
  }
  self.drain_output()
}

///|
/// Drain pending ciphertext from the bridge ring to the underlying writer.
async fn TlsConn::drain_output(self : TlsConn) -> Unit {
  self.output_gate.acquire()
  defer self.output_gate.release()
  guard !self.closed else { raise TlsUnexpectedEof }
  for ;; {
    let pending = tls_output_pending_c(self.handle)
    guard pending > 0 else { return }
    let n = tls_take_output_c(self.handle, self.out_scratch, pending)
    guard n > 0 else { return }
    let bytes = self.out_scratch.unsafe_reinterpret_as_bytes()
    self.writer.write(bytes[0:n])
  }
}

///|
/// Pull one chunk of ciphertext from the underlying reader into the bridge
/// input ring. Returns false when the transport reached EOF.
async fn TlsConn::feed_input(self : TlsConn) -> Bool {
  self.input_gate.acquire()
  defer self.input_gate.release()
  guard !self.closed else { raise TlsUnexpectedEof }
  let space = tls_in_space_c(self.handle)
  guard space > 0 else { return true }
  let cap = @cmp.minimum(space, self.in_scratch.length())
  let n = self.reader.read(self.in_scratch, offset=0, max_len=cap)
  guard !self.closed else { raise TlsUnexpectedEof }
  if n <= 0 {
    return false
  }
  let r = tls_feed_array_c(self.handle, self.in_scratch, n)
  guard r == n else { raise TlsError::from_bridge(r) }
  true
}

///|
/// TLS close_notify. Best-effort: returns false when the peer did not
/// acknowledge a clean shutdown; never raises.
pub async fn TlsConn::shutdown(self : TlsConn) -> Bool {
  let mut clean = false
  for ;; {
    let r = tls_shutdown_c(self.handle)
    if r == 0 {
      clean = true
      break
    }
    if r == -1 {
      let fed = self.feed_input() catch { _ => false }
      if !fed {
        break
      }
    } else if r == -2 {
      let _ = self.drain_output() catch { _ => return false }
    } else {
      break
    }
  }
  let _ = self.drain_output() catch { _ => return false }
  clean
}
///|
/// Send close_notify without consuming peer input; safe alongside one reader.
pub async fn TlsConn::shutdown_write(self : TlsConn) -> Bool {
  if self.closed { return false }
  for ;; {
    let result=tls_shutdown_c(self.handle)
    if result==0 { self.drain_output();return true }
    if result!= -2 { return false }
    self.drain_output()
  }
}

///|
/// Release the underlying MbedTLS connection state. Idempotent; the
/// connection must not be used afterwards.
pub fn TlsConn::close(self : TlsConn) -> Unit {
  if !self.closed {
    self.closed = true
    tls_conn_close_obj_c(self.obj)
  }
}

///|
/// Whether the connection state has been released.
pub fn TlsConn::is_closed(self : TlsConn) -> Bool {
  self.closed
}

///|
/// Number of live connection objects (leak probe for resource tests).
pub fn tls_conn_count() -> Int {
  tls_conn_count_c()
}

///|
#warnings("-alert_internal")
pub impl @io.Reader for TlsConn with fn _get_internal_buffer(self) {
  self.rb
}

///|
pub impl @io.Reader for TlsConn with fn _direct_read(
  self,
  buf,
  offset~,
  max_len~,
) {
  guard !self.closed else { raise TlsUnexpectedEof }
  if max_len <= 0 {
    return 0
  }
  for ;; {
    let r = tls_read_c(self.handle, buf, offset, max_len)
    if r > 0 {
      return r
    }
    if r == 0 {
      // Clean EOF: peer sent close_notify.
      self.drain_output()
      return 0
    }
    if r == -1 {
      self.drain_output()
      guard self.feed_input() else {
        // Underlying EOF without close_notify: reject as truncated flow
        // rather than reporting a clean EOF (RFC 8446 section 6.1).
        raise TlsUnexpectedEof
      }
    } else if r == -2 {
      self.drain_output()
    } else if r < 0 {
      raise TlsError::from_bridge(r)
    }
  }
}

///|
pub impl @io.Writer for TlsConn with fn write_once(self, buf, offset~, len~) {
  guard !self.closed else { raise TlsUnexpectedEof }
  if len <= 0 {
    return 0
  }
  for ;; {
    let r = tls_write_c(self.handle, buf, offset, len)
    if r >= 0 {
      self.drain_output()
      return r
    }
    if r == -1 {
      guard self.feed_input() else { raise TlsUnexpectedEof }
    } else if r == -2 {
      self.drain_output()
    } else if r < 0 {
      raise TlsError::from_bridge(r)
    }
  }
}


///|
pub extend TlsConn with @moonbitlang/async/io.Reader::{read, read_some, _direct_read, drop, read_all, read_until, read_exactly, _get_internal_buffer}

///|
pub extend TlsConn with @moonbitlang/async/io.Writer::{write_once, write, write_reader}
