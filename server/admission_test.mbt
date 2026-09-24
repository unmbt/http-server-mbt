///|
async test "N-23 idle admission resumes without cancelling the live accept handle" {
  @server.with_server_at(@core.Config::default("testdata/public"),0,async fn(server) {
    @async.sleep(450)
    @async.with_timeout(3000,() => {
      for _ in 0..<3 {
        let client=@socket.Tcp::connect(@socket.Addr::new(0x7F000001,server.port()))
        defer client.close()
        client.write("GET /hello.txt HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n")
        assert_true(client.read_until("\r\n\r\n").unwrap().contains("200 OK"))
        assert_eq(client.read_exactly(14),b"hello moonbit\n")
      }
    })
  })
}
