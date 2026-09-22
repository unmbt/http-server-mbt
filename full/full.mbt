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
  let upstream_connector : &@server.UpstreamConnector? = if config.has_proxy() &&
    proxy_targets_include_https(config) {
    Some(build_upstream_connector(config))
  } else {
    None
  }
  @server.with_server_at_with_connector(
    config,
    port,
    acceptor?,
    upstream_connector?,
    action,
  )
}

///|
/// Resolve proxy rules before the listener is created so an HTTPS target in a
/// JSON file receives the same MbedTLS connector as an inline target. A file
/// read failure is left to the normal proxy rule loader; this probe only
/// decides whether the client TLS configuration is needed.
async fn proxy_targets_include_https(config : @core.Config) -> Bool {
  if config.proxy_targets_include_https() {
    return true
  }
  match config.proxy_config {
    None => false
    Some(value) => {
      let is_file = @fs.exists(value) catch { _ => false }
      let content = if is_file {
        @fs.read_file(value).text() catch {
          _ => value
        }
      } else {
        value
      }
      content.contains("https://")
    }
  }
}

///|
/// Start a full server with default port 8080.
pub async fn with_server(
  config : @core.Config,
  action : async (@server.Server) -> Unit,
) -> Unit {
  with_server_at(config, 8080, action)
}
