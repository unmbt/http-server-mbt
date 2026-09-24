///|
/// A TLS acceptor implementing @server.Acceptor by wrapping @tls.TlsAcceptor.
pub struct TlsServerAcceptor {
  tls_acceptor : @tls.TlsAcceptor
}

///|
pub fn TlsServerAcceptor::new(
  tls_acceptor : @tls.TlsAcceptor,
) -> TlsServerAcceptor {
  { tls_acceptor, }
}

///|
/// Full-build upstream connector. Plain HTTP targets remain raw TCP; HTTPS
/// targets use the vendored MbedTLS client with SNI and certificate checks.
pub struct TlsUpstreamConnector {
  tls_acceptor : @tls.TlsAcceptor
}

///|
pub fn TlsUpstreamConnector::new(
  tls_acceptor : @tls.TlsAcceptor,
) -> TlsUpstreamConnector {
  { tls_acceptor, }
}

///|
pub impl @server.UpstreamConnector for TlsUpstreamConnector with fn connect(
  self,
  target,
) {
  let tcp = @socket.Tcp::connect_to_host(target.host(), port=target.port())
  errdefer tcp.close()
  if target.scheme() == "https" {
    let tls_conn = self.tls_acceptor.connect(
      target.host(),
      reader=tcp,
      writer=tcp,
    )
    @server.Transport::custom(tls_conn, tls_conn, shutdown_write_fn=() => tls_conn.shutdown_write(), close_fn=fn() {
      tls_conn.close()
      tcp.close()
    })
  } else {
    @server.Transport::plain(tcp)
  }
}

///|
pub impl @server.UpstreamConnector for TlsUpstreamConnector with fn close(self) {
  self.tls_acceptor.close()
}

///|
pub impl @server.Acceptor for TlsServerAcceptor with fn accept(self, tcp) {
  let tls_conn = self.tls_acceptor.accept(reader=tcp, writer=tcp)
  @server.Transport::custom(tls_conn, tls_conn, shutdown_write_fn=() => tls_conn.shutdown_write(), close_fn=fn() {
    tls_conn.close()
    tcp.close()
  })
}

///|
pub impl @server.Acceptor for TlsServerAcceptor with fn close(self) {
  self.tls_acceptor.close()
}

///|
pub impl @server.Acceptor for TlsServerAcceptor with fn is_tls(_self) {
  true
}

///|
/// Build the TLS acceptor from configured certificate/key files.
/// Part of the D-01 preflight: runs before the listener is created, so a
/// missing/unreadable/mismatching certificate prevents listening entirely.
pub async fn build_tls_acceptor(
  config : @core.Config,
) -> @tls.TlsAcceptor raise @core.ConfigError {
  @core.validate_tls(config)
  let cert_path = match config.cert_file {
    Some(p) => p
    None => ""
  }
  let key_path = match config.key_file {
    Some(p) => p
    None => ""
  }
  let cert = @fs.read_file(cert_path).binary() catch {
    err =>
      raise @core.ConfigError::InvalidTls(
        "cannot read cert_file \{cert_path}: \{err}",
      )
  }
  let key = @fs.read_file(key_path).binary() catch {
    err =>
      raise @core.ConfigError::InvalidTls(
        "cannot read key_file \{key_path}: \{err}",
      )
  }
  let passphrase = match config.key_passphrase {
    Some(p) => Some(@utf8.encode(p))
    None => None
  }
  try {
    match passphrase {
      Some(pass) => @tls.TlsAcceptor::new_server(cert, key, passphrase=pass)
      None => @tls.TlsAcceptor::new_server(cert, key)
    }
  } catch {
    err => raise tls_preflight_error(err)
  }
}

///|
/// Translate TLS preflight failures into configuration errors with
/// actionable messages (D-01: preflight failures prevent listening).
fn tls_preflight_error(err : Error) -> @core.ConfigError {
  match err {
    @tls.TlsError::TlsError(code=-15232, ..) => // MBEDTLS_ERR_PK_PASSWORD_MISMATCH
      @core.ConfigError::InvalidTls(
        "key passphrase mismatch (check --key-passphrase)",
      )
    @tls.TlsError::TlsError(code=-15360, ..) => // MBEDTLS_ERR_PK_PASSWORD_REQUIRED
      @core.ConfigError::InvalidTls(
        "key is encrypted: --key-passphrase is required",
      )
    @tls.TlsError::TlsError(code=-15616, ..) => // MBEDTLS_ERR_PK_KEY_INVALID_FORMAT
      @core.ConfigError::InvalidTls(
        "key parse failed: wrong key file or wrong passphrase",
      )
    @tls.TlsError::TlsError(code~, message~) =>
      @core.ConfigError::InvalidTls("\{message} (mbedtls \{code})")
    _ => @core.ConfigError::InvalidTls("\{err}")
  }
}

///|
/// Construct a new TLS acceptor implementing @server.Acceptor.
pub async fn new_tls_acceptor(
  config : @core.Config,
) -> &@server.Acceptor raise @core.ConfigError {
  let tls_acceptor = build_tls_acceptor(config)
  TlsServerAcceptor::new(tls_acceptor)
}

///|
/// Build the client TLS connector used by HTTPS upstream proxy targets.
/// Verification is fail-closed unless `secure=false` is explicit.
pub async fn build_upstream_connector(
  config : @core.Config,
) -> &@server.UpstreamConnector raise @core.ConfigError {
  let ca = match config.ca_file {
    Some(path) =>
      @fs.read_file(path).binary() catch {
        err =>
          raise @core.ConfigError::InvalidTls(
            "cannot read ca_file \{path}: \{err}",
          )
      }
    None => @utf8.encode(mozilla_roots)
  }
  let acceptor = try {
    if ca.length() == 0 {
      @tls.TlsAcceptor::new_client(insecure=!config.secure)
    } else {
      @tls.TlsAcceptor::new_client(ca~, insecure=!config.secure)
    }
  } catch {
    @tls.TlsError::TlsError(code~, message~) =>
      raise @core.ConfigError::InvalidTls(
        "upstream TLS: \{message} (mbedtls \{code})",
      )
    @tls.TlsError::TlsUnexpectedEof =>
      raise @core.ConfigError::InvalidTls(
        "upstream TLS: connection closed during handshake",
      )
  }
  TlsUpstreamConnector::new(acceptor)
}


///|
pub extend TlsUpstreamConnector with @unmbt/http-server-mbt/server.UpstreamConnector::{close, connect}

///|
pub extend TlsServerAcceptor with @unmbt/http-server-mbt/server.Acceptor::{accept, close, is_tls}
