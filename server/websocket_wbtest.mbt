///|
test "N-22 RFC6455 handshake digest vector" {
  assert_eq(websocket_accept("dGhlIHNhbXBsZSBub25jZQ=="),"s3pPLMBiTxaQ9kYGzzhZRbK+xOo=")
}
