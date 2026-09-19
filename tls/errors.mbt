///|
/// TLS layer error. `code` is the raw MbedTLS/PSA error code (negative) or a
/// bridge-specific code; `message` is the library-provided description.
pub suberror TlsError {
  TlsError(code~ : Int, message~ : String)
  /// Underlying transport reached EOF without a TLS close_notify: a
  /// truncated flow, rejected instead of reporting clean EOF (RFC 8446 6.1).
  TlsUnexpectedEof
} derive(Debug)

///|
impl Show for TlsError with fn output(self, logger) {
  match self {
    TlsError(code~, message~) =>
      logger.write_string("tls error \{code}: \{message}")
    TlsUnexpectedEof =>
      logger.write_string("tls error: connection closed without close_notify")
  }
}

///|
/// Bridge error convention (see tls/tls_bridge.c header): a returned value
/// `ret < -1000` encodes the real code as `-(1000000 + |code|)`; PSA statuses
/// from global init are encoded as `-(100000 + status)`.
fn TlsError::from_bridge(ret : Int) -> TlsError {
  let real = if ret <= -1000000 {
    // Encoded mbedtls code: -(1000000 + |code|); recover the negative code.
    ret + 1000000
  } else if ret <= -100000 {
    // Encoded PSA status: -(100000 + status); statuses are positive.
    -(ret + 100000)
  } else {
    ret
  }
  TlsError(code=real, message=strerror(real))
}

///|
fn strerror(code : Int) -> String {
  @utf8.decode_lossy(tls_strerror_c(code))
}
