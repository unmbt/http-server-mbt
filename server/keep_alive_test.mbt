///|
async test "N-24 full HTTP/1.0 keep-alive acknowledgement and final close" {
  @async.with_timeout(3000, () => {
    @server.with_server_at(@core.Config::default("testdata/public"), 0, server => {
      let tcp = @socket.Tcp::connect_to_host("127.0.0.1", port=server.port())
      defer tcp.close()
      tcp.write(
        "GET /hello.txt HTTP/1.0\r\nHost: localhost\r\nConnection: keep-alive\r\n\r\n",
      )
      assert_true(
        tcp
        .read_until("\r\n\r\n")
        .unwrap()
        .to_lower()
        .contains("connection: keep-alive"),
      )
      assert_eq(tcp.read_exactly(14), b"hello moonbit\n")
      tcp.write(
        "GET /hello.txt HTTP/1.0\r\nHost: localhost\r\nConnection: close\r\n\r\n",
      )
      ignore(tcp.read_until("\r\n\r\n"))
      assert_eq(tcp.read_exactly(14), b"hello moonbit\n")
      assert_true(tcp.read_some() is None)
    })
  })
}
