///|
/// Test-client decoder independent of the production framing implementation.
/// C016/C022/C042 continue asserting the full directory HTML after D-06 streaming.
async fn read_test_chunked_body(conn : @socket.Tcp) -> Bytes {
  let bytes : Array[Byte]=[]
  for ;; {
    let line=conn.read_until("\r\n").unwrap()
    let n=@string.parse_int(line,base=16)
    if n==0 { assert_eq(conn.read_exactly(2),b"\r\n"); break }
    assert_true(n>0 && n<=65536)
    let part=conn.read_exactly(n)
    for byte in part { bytes.push(byte) }
    assert_eq(conn.read_exactly(2),b"\r\n")
  }
  Bytes::from_array(bytes)
}
