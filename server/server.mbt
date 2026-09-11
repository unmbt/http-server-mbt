///|
/// A library-managed HTTP server for static files.
pub struct Server {
  inner : @http.Server
  engine : @root.StaticEngine
}

///|
/// Start a server and run the handler until the scope exits.
pub async fn with_server(
  config : @core.Config,
  action : async (Server) -> Unit,
) -> Unit {
  with_server_at(config, 8080, action)
}

///|
/// Start a server on an explicit TCP port. Port validation is performed before
/// the listener is created by callers; this helper keeps the listener lifecycle
/// managed by the async scope.
pub async fn with_server_at(
  config : @core.Config,
  port : Int,
  action : async (Server) -> Unit,
) -> Unit {
  let engine = @root.StaticEngine::new(config)
  let listener = @http.Server::Server(@socket.Addr::new(0, port))
  let server = { inner: listener, engine, }
  defer listener.close()
  action(server)
  listener.run_forever((request, _body, conn) => {
    let meth = match request.meth {
      @http.RequestMethod::Get => @core.Method::Get
      @http.RequestMethod::Head => @core.Method::Head
      _ => @core.Method::Other(@debug.to_string(request.meth))
    }
    let headers : Map[String, String] = Map([])
    for key, value in request.headers {
      headers[key.to_string()] = value
    }
    let result = server.engine.handle({ meth, target: request.path, headers, })
    match result {
      @root.HandleResult::Handled(response) => {
        let out : Map[@http.CaseInsensitiveString, String] = Map([])
        for key, value in response.headers {
          out[@http.CaseInsensitiveString(key)] = value
        }
        conn.send_response(response.status, "OK", extra_headers=out)
        match response.body {
          Empty => ()
          Bytes(b) => conn.write(b)
          FileRegion(_) => {
            let bytes = response.read(offset=0, max_len=response.body.length())
            conn.write(bytes)
          }
        }
      }
      @root.HandleResult::Next => {
        conn.send_response(404, "Not Found")
        conn.write("Not Found")
      }
      @root.HandleResult::Error(_) => {
        conn.send_response(500, "Internal Server Error")
        conn.write("Internal Server Error")
      }
    }
  })
}

///|
/// Stop accepting new connections.
pub fn Server::stop(self : Server) -> Unit {
  self.inner.close()
}

///|
/// Return the configured static engine for embedded use.
pub fn Server::engine(self : Server) -> @root.StaticEngine {
  self.engine
}
