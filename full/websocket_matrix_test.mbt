///|
async test "N-22 raw WebSocket frames survive all plain and TLS combinations" {
  let cert=@fs.read_file("testdata/tls/server_cert.pem").binary()
  // One large masked binary frame crosses four body blocks; control and
  // fragmented frames before it must be preserved without message decoding.
  let large=b"\x82\xff\x00\x00\x00\x00\x00\x04\x00\x00\x01\x02\x03\x04"+
    Bytes::makei(262144,i => (i%251).to_byte())
  for inbound_tls in [false,true] {
    for upstream_tls in [false,true] {
      let listener=@socket.TcpServer(@socket.Addr::new(0x7f000001,0),reuse_addr=true)
      defer listener.close()
      let upstream_config={..@core.Config::default("testdata/public"),cert_file:Some("testdata/tls/server_cert.pem"),key_file:Some("testdata/tls/server_key.pem")}
      let acceptor : &@server.Acceptor=if upstream_tls { @full.new_tls_acceptor(upstream_config) } else { @server.PlainAcceptor::new() }
      defer acceptor.close()
      let scheme=if upstream_tls { "wss" } else { "ws" }
      let config={..@core.Config::default("testdata/public"),
        cert_file:if inbound_tls {upstream_config.cert_file} else {None},
        key_file:if inbound_tls {upstream_config.key_file} else {None},
        ca_file:Some("testdata/tls/server_cert.pem"),websocket:true,
        proxy:Some("\{scheme}://localhost:\{listener.addr.port()}")}
      @async.with_task_group() <| tasks => {
        let echo=tasks.spawn(() => {
          let (tcp,_)=listener.accept()
          defer tcp.close()
          let transport=acceptor.accept(tcp)
          defer transport.close()
          let request=transport.reader.read_until("\r\n\r\n").unwrap()
          assert_true(request.contains("sec-websocket-protocol: sample"))
          transport.writer.write("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=\r\nSec-WebSocket-Protocol: sample\r\n\r\n")
          // Masked ping, fragmented binary, continuation: tunnel must preserve all bytes.
          let frames=b"\x89\x81\x01\x02\x03\x04\x79\x02\x81\x01\x02\x03\x04\x79\x80\x81\x01\x02\x03\x04\x78"
          assert_eq(transport.reader.read_exactly(frames.length()),frames)
          transport.writer.write(frames)
          assert_eq(transport.reader.read_exactly(large.length()),large)
          transport.writer.write(large)
        })
        @full.with_server_at(config,0,server => {
          let tcp=@socket.Tcp::connect_to_host("localhost",port=server.port())
          defer tcp.close()
          let tls_client=@tls.TlsAcceptor::new_client(ca=cert)
          defer tls_client.close()
          let client=if inbound_tls {
            let conn=tls_client.connect("localhost",reader=tcp,writer=tcp)
            @server.Transport::custom(conn,conn,close_fn=() => conn.close())
          } else { @server.Transport::plain(tcp) }
          defer client.close()
          let frames=b"\x89\x81\x01\x02\x03\x04\x79\x02\x81\x01\x02\x03\x04\x79\x80\x81\x01\x02\x03\x04\x78"
          client.writer.write("GET /socket HTTP/1.1\r\nHost: localhost\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Protocol: sample\r\n\r\n")
          // Send immediately to exercise parser pre-read preservation across upgrade.
          client.writer.write(frames)
          let response=client.reader.read_until("\r\n\r\n").unwrap()
          assert_true(response.contains("101 Switching Protocols"))
          assert_true(response.contains("sec-websocket-protocol: sample"))
          assert_eq(client.reader.read_exactly(frames.length()),frames)
          client.writer.write(large)
          assert_eq(client.reader.read_exactly(large.length()),large)
          echo.wait()
        })
      }
    }
  }
}
