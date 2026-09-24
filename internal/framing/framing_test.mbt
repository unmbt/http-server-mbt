///|
async test "N-22 framing preserves pipelined bytes with fixed and chunked bodies" {
  for body in ["Content-Length: 3\r\n\r\nabc", "Transfer-Encoding: chunked\r\n\r\n3;x=1\r\nabc\r\n0\r\nX-Trace: yes\r\n\r\n"] {
    let source=@io.MemoryReader(writer => writer.write("POST / HTTP/1.1\r\nHost: local\r\n"+body+"GET /next HTTP/1.0\r\n\r\n"))
    defer source.close()
    let conn=@framing.Connection::new(source)
    assert_eq(conn.read_request().request.target,"/")
    conn.drain()
    let head=conn.read_request()
    assert_eq(head.request.target,"/next")
    assert_false(head.keep_alive)
  }
}
///|
async test "N-22 framing rejects conflicting lengths and oversized headers" {
  for headers in ["Content-Length: 0\r\nTransfer-Encoding: chunked\r\n", "Content-Length: 0\r\nContent-Length: 0\r\n", "Content-Length: -1\r\n", "Bad Header: x\r\n", "X-Large: "+String::make(16385,'a')+"\r\n"] {
    let source=@io.MemoryReader(writer => writer.write("GET / HTTP/1.1\r\n"+headers+"\r\n"))
    defer source.close()
    let conn=@framing.Connection::new(source)
    let rejected=try { ignore(conn.read_request()); false } catch { @framing.ProtocolError::Invalid | @framing.ProtocolError::Limit => true; _ => false }
    assert_true(rejected)
  }
}
