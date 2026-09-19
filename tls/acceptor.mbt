///|
/// Shared TLS configuration: server-side certificate/key material or
/// client-side trust roots. Built once at startup (D-01 preflight) and
/// reused for every connection. Owned by the creator; call `close` when done
/// (a GC finalizer is registered as a backstop).
pub struct TlsAcceptor {
  handle : Int64
  obj : AcceptorObj
  mut closed : Bool
}

///|
/// Initialize the PSA crypto subsystem. Idempotent; must succeed before any
/// acceptor is created.
pub fn tls_global_init() -> Unit raise TlsError {
  let ret = tls_global_init_c()
  if ret != 0 {
    raise TlsError::from_bridge(ret)
  }
}

///|
/// Build a server acceptor from PEM/DER buffers. The certificate may be a
/// full chain (leaf first). `passphrase` is required for encrypted keys.
pub fn TlsAcceptor::new_server(
  cert_pem : Bytes,
  key_pem : Bytes,
  passphrase? : Bytes,
) -> TlsAcceptor raise TlsError {
  tls_global_init()
  let pass = match passphrase {
    Some(b) => b
    None => b""
  }
  // +1: MbedTLS PEM parsing wants NUL-terminated buffers.
  let handle = tls_acceptor_new_server_c(
    cert_pem,
    cert_pem.length() + 1,
    key_pem,
    key_pem.length() + 1,
    pass,
    pass.length(),
  )
  if handle <= 0 {
    raise TlsError::from_bridge(handle.to_int())
  }
  { handle, obj: tls_acceptor_wrap_c(handle), closed: false, }
}

///|
/// Build a client acceptor. Verification requires `ca_pem` (explicit CA or
/// embedded trust root); `insecure=true` disables verification and is only
/// meant for the explicit `secure=false` configuration escape (AD-09).
pub fn TlsAcceptor::new_client(
  ca? : Bytes,
  insecure? : Bool = false,
) -> TlsAcceptor raise TlsError {
  tls_global_init()
  let ca = match ca {
    Some(b) => b
    None => b""
  }
  let handle = tls_acceptor_new_client_c(
    ca,
    if ca.length() == 0 {
      0
    } else {
      ca.length() + 1
    },
    if insecure {
      1
    } else {
      0
    },
  )
  if handle <= 0 {
    raise TlsError::from_bridge(handle.to_int())
  }
  { handle, obj: tls_acceptor_wrap_c(handle), closed: false, }
}

///|
/// Release the underlying configuration. Idempotent.
pub fn TlsAcceptor::close(self : TlsAcceptor) -> Unit {
  if !self.closed {
    self.closed = true
    tls_acceptor_close_obj_c(self.obj)
  }
}

///|
/// Number of live acceptor objects (leak probe for resource tests).
pub fn tls_acceptor_count() -> Int {
  tls_acceptor_count_c()
}
