///|
async fn response_head(tcp : @socket.Tcp) -> String {
  tcp.read_until("\r\n\r\n").unwrap()
}

///|
async test "D-20 thin fixed and chunked bodies preserve pipelined request boundaries" {
  @async.with_timeout(4000, async fn() {
    @plain.with_server_at(@core.Config::default("testdata/public"), 0, async fn(
      server,
    ) {
      let fixed = @socket.Tcp::connect_to_host("127.0.0.1", port=server.port())
      fixed.write(
        "GET /hello.txt HTTP/1.1\r\nHost: localhost\r\nContent-Length: 3\r\nConnection: close\r\n\r\nabc",
      )
      assert_true(response_head(fixed).contains("200 OK"))
      assert_eq(fixed.read_exactly(14), b"hello moonbit\n")
      fixed.close()
      let chunked = @socket.Tcp::connect_to_host(
        "127.0.0.1",
        port=server.port(),
      )
      chunked.write(
        "GET /hello.txt HTTP/1.1\r\nHost: localhost\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n3;x=y\r\nabc\r\n0\r\nX-Trailer: done\r\n\r\n",
      )
      assert_true(response_head(chunked).contains("200 OK"))
      assert_eq(chunked.read_exactly(14), b"hello moonbit\n")
      chunked.close()
    })
  })
}

///|
async test "D-20 thin rejects ambiguous framing without aborting service" {
  @async.with_timeout(4000, async fn() {
    @plain.with_server_at(@core.Config::default("testdata/public"), 0, async fn(
      server,
    ) {
      for
        framing in [
          "Content-Length: 0\r\nContent-Length: 0\r\n", "Content-Length: 0\r\nTransfer-Encoding: chunked\r\n",
          "Transfer-Encoding: chunked\r\nContent-Length: 0\r\n", "Content-Length: -1\r\n",
          "Content-Length: 99999999999999999999\r\n",
        ] {
        let tcp = @socket.Tcp::connect_to_host("127.0.0.1", port=server.port())
        tcp.write(
          "GET /hello.txt HTTP/1.1\r\nHost: localhost\r\n\{framing}\r\n",
        )
        tcp.close()
      }
      let tcp = @socket.Tcp::connect_to_host("127.0.0.1", port=server.port())
      defer tcp.close()
      tcp.write(
        "GET /hello.txt HTTP/1.0\r\nHost: localhost\r\nRange: bytes=0-4\r\n\r\n",
      )
      assert_true(response_head(tcp).contains("206 Partial Content"))
      assert_eq(tcp.read_exactly(5), b"hello")
      tcp.close()
    })
  })
}

///|
async test "D-20 thin idle timeout and HEAD delegated errors close cleanly" {
  @async.with_timeout(3000, async fn() {
    let config = {
      ..@core.Config::default("testdata/public"),
      idle_timeout_ms: 100,
      handle_error: false,
    }
    @plain.with_server_at(config, 0, async fn(server) {
      let tcp = @socket.Tcp::connect_to_host("127.0.0.1", port=server.port())
      defer tcp.close()
      tcp.write(
        "HEAD /missing-unlikely HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n",
      )
      assert_true(response_head(tcp).contains("404 Not Found"))
    })
  })
}
