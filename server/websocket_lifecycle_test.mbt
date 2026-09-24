///|
async test "N-22 WebSocket upstream rejection never commits 101" {
  let listener=@socket.TcpServer(@socket.Addr::new(0x7F000001,0))
  defer listener.close()
  @async.with_task_group() <| group => {
    let peer=group.spawn(() => {
      let (tcp,_)=listener.accept()
      defer tcp.close()
      ignore(tcp.read_until("\r\n\r\n"))
      tcp.write("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: upgrade\r\nSec-WebSocket-Accept: invalid\r\n\r\n")
    })
    let config={..@core.Config::default("testdata/public"),websocket:true,proxy:Some("ws://127.0.0.1:\{listener.addr.port()}")}
    @server.with_server_at(config,0,async fn(server) {
      let tcp=@socket.Tcp::connect(@socket.Addr::new(0x7F000001,server.port()))
      defer tcp.close()
      tcp.write("GET /ws HTTP/1.1\r\nHost: localhost\r\nConnection: Upgrade\r\nUpgrade: websocket\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n\r\n")
      assert_true(tcp.read_until("\r\n").unwrap().has_prefix("HTTP/1.1 502 "))
    })
    peer.wait()
  }
}
///|
async test "N-22 WebSocket half-close drains the opposite direction" {
  let listener=@socket.TcpServer(@socket.Addr::new(0x7F000001,0))
  defer listener.close()
  @async.with_timeout(3000,() => {
    @async.with_task_group() <| group => {
      let peer=group.spawn(() => {
        let (tcp,_)=listener.accept()
        defer tcp.close()
        ignore(tcp.read_until("\r\n\r\n"))
        tcp.write("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=\r\n\r\n")
        assert_eq(tcp.read_some(),None)
        tcp.write(b"\x82\x04tail")
      })
      let config={..@core.Config::default("testdata/public"),websocket:true,proxy:Some("ws://127.0.0.1:\{listener.addr.port()}")}
      @server.with_server_at(config,0,async fn(server) {
        let tcp=@socket.Tcp::connect(@socket.Addr::new(0x7F000001,server.port()))
        defer tcp.close()
        tcp.write("GET /ws HTTP/1.1\r\nHost: localhost\r\nConnection: Upgrade\r\nUpgrade: websocket\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n\r\n")
        ignore(tcp.read_until("\r\n\r\n"))
        assert_true(@server.Transport::plain(tcp).shutdown_write())
        assert_eq(tcp.read_exactly(6),b"\x82\x04tail")
      })
      peer.wait()
    }
  })
}
