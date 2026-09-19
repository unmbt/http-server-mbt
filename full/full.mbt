///|
/// Start a full HTTP/HTTPS server on an explicit TCP port.
/// If config.has_tls() is true, builds and injects a TlsServerAcceptor.
/// Otherwise runs with default PlainAcceptor.
pub async fn with_server_at(
  config : @core.Config,
  port : Int,
  action : async (@server.Server) -> Unit,
) -> Unit {
  let acceptor : &@server.Acceptor? = if config.has_tls() {
    let tls_acc = build_tls_acceptor(config)
    Some(TlsServerAcceptor::new(tls_acc))
  } else {
    None
  }
  @server.with_server_at(config, port, acceptor?, action)
}

///|
/// Start a full server with default port 8080.
pub async fn with_server(
  config : @core.Config,
  action : async (@server.Server) -> Unit,
) -> Unit {
  with_server_at(config, 8080, action)
}
