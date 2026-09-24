///|
async test "N-12 embedded roots reject private CA and explicit roots replace trust" {
  let origin={..@core.Config::default("testdata/public"),cert_file:Some("testdata/tls/server_cert.pem"),key_file:Some("testdata/tls/server_key.pem")}
  @full.with_server_at(origin,0,async fn(server) {
    let upstream="https://localhost:\{server.port()}"
    for (ca,secure,expected) in [(None,true,502),(Some("testdata/tls/server_cert.pem"),true,200),(Some("testdata/tls/other_cert.pem"),true,502),(None,false,200)] {
      let config={..@core.Config::default("testdata/public"),proxy:Some(upstream),proxy_all:Some(upstream),ca_file:ca,secure}
      @full.with_server_at(config,0,async fn(proxy) {
        let conn=@socket.Tcp::connect_to_host("localhost",port=proxy.port())
        defer conn.close()
        conn.write("GET /hello.txt HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n")
        let head=conn.read_until("\r\n\r\n").unwrap()
        assert_true(head.has_prefix("HTTP/1.1 \{expected} "))
        if expected==200 { assert_eq(conn.read_exactly(14),b"hello moonbit\n") }
      })
    }
  })
}
///|
async test "N-12 expired trusted certificate fails secure validation" {
  let origin={..@core.Config::default("testdata/public"),cert_file:Some("testdata/tls/expired_cert.pem"),key_file:Some("testdata/tls/server_key.pem")}
  @full.with_server_at(origin,0,async fn(server) {
    let upstream="https://localhost:\{server.port()}"
    let config={..@core.Config::default("testdata/public"),proxy:Some(upstream),proxy_all:Some(upstream),ca_file:Some("testdata/tls/expired_cert.pem")}
    @full.with_server_at(config,0,async fn(proxy) {
      let conn=@socket.Tcp::connect_to_host("localhost",port=proxy.port())
      defer conn.close()
      conn.write("GET /hello.txt HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n")
      assert_true(conn.read_until("\r\n").unwrap().has_prefix("HTTP/1.1 502 "))
    })
  })
}
