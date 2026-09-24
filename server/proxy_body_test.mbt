///|
async test "N-22 proxy forwards fixed and chunked bodies without losing preread bytes" {
  for (framing,wire) in [("Content-Length: 11\r\n","hello world"),("Transfer-Encoding: chunked\r\nTrailer: X-Checksum\r\n","5\r\nhello\r\n6;foo=bar\r\n world\r\n0\r\nX-Checksum: ok\r\n\r\n")] {
    let listener=@socket.TcpServer(@socket.Addr::new(0x7F000001,0))
    defer listener.close()
    @async.with_task_group() <| group => {
      let received=group.spawn(() => {
        let (tcp,_)=listener.accept()
        defer tcp.close()
        let request=@framing.Connection::new(tcp)
        let head=request.read_request()
        assert_eq(head.request.meth,@core.Method::Other("POST"))
        let body : Array[Byte]=[]
        let block=FixedArray::make(3,b'\x00')
        for ;; {
          let n=request.read_body(block)
          if n==0 { break }
          for i in 0..<n { body.push(block[i]) }
        }
        assert_eq(Bytes::from_array(body),b"hello world")
        assert_eq(head.request.headers.get("trailer"),None)
        tcp.write("HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok")
      })
      let url="http://127.0.0.1:\{listener.addr.port()}"
      let config={..@core.Config::default("testdata/public"),proxy:Some(url),proxy_all:Some(url)}
      @server.with_server_at(config,0,async fn(proxy) {
        let tcp=@socket.Tcp::connect(@socket.Addr::new(0x7F000001,proxy.port()))
        defer tcp.close()
        tcp.write("POST /echo HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n"+framing+"\r\n"+wire)
        assert_true(tcp.read_until("\r\n\r\n").unwrap().has_prefix("HTTP/1.1 200 "))
        assert_eq(tcp.read_exactly(2),b"ok")
      })
      received.wait()
    }
  }
}
