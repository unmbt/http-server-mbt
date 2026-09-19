// Raw FFI surface for the MbedTLS bridge (tls/tls_bridge.c).
// Conventions are documented in the bridge header; MoonBit wrappers live in
// acceptor.mbt / conn.mbt.
//
// Length conventions:
// - cert/key/ca buffers: length includes the trailing NUL (MbedTLS PEM
//   parsing requires NUL-terminated input).
// - passphrase: raw byte length, without any terminator.
// - hostname: length includes the trailing NUL; 0 means "not provided".

///|
type AcceptorObj

///|
type ConnObj

///|
extern "c" fn tls_global_init_c() -> Int = "http_server_tls_global_init"

///|
extern "c" fn tls_strerror_c(code : Int) -> Bytes = "http_server_tls_strerror"

///|
extern "c" fn tls_conn_count_c() -> Int = "http_server_tls_conn_count"

///|
extern "c" fn tls_acceptor_count_c() -> Int = "http_server_tls_acceptor_count"

///|
#borrow(cert, key, pass)
extern "c" fn tls_acceptor_new_server_c(
  cert : Bytes,
  cert_len : Int,
  key : Bytes,
  key_len : Int,
  pass : Bytes,
  pass_len : Int,
) -> Int64 = "http_server_tls_acceptor_new_server"

///|
#borrow(ca)
extern "c" fn tls_acceptor_new_client_c(
  ca : Bytes,
  ca_len : Int,
  insecure : Int,
) -> Int64 = "http_server_tls_acceptor_new_client"

///|
#borrow(obj)
extern "c" fn tls_acceptor_close_obj_c(obj : AcceptorObj) -> Unit = "http_server_tls_acceptor_close_obj"

///|
extern "c" fn tls_acceptor_wrap_c(handle : Int64) -> AcceptorObj = "http_server_tls_acceptor_wrap"

///|
#borrow(hostname)
extern "c" fn tls_conn_new_c(
  acceptor : Int64,
  hostname : Bytes,
  hostname_len : Int,
) -> Int64 = "http_server_tls_conn_new"

///|
#borrow(obj)
extern "c" fn tls_conn_close_obj_c(obj : ConnObj) -> Unit = "http_server_tls_conn_close_obj"

///|
extern "c" fn tls_conn_wrap_c(handle : Int64) -> ConnObj = "http_server_tls_conn_wrap"

///|
#borrow(buf)
extern "c" fn tls_feed_array_c(
  handle : Int64,
  buf : FixedArray[Byte],
  len : Int,
) -> Int = "http_server_tls_feed"

///|
extern "c" fn tls_in_space_c(handle : Int64) -> Int = "http_server_tls_in_space"

///|
#borrow(buf)
extern "c" fn tls_take_output_c(
  handle : Int64,
  buf : FixedArray[Byte],
  cap : Int,
) -> Int = "http_server_tls_take_output"

///|
extern "c" fn tls_output_pending_c(handle : Int64) -> Int = "http_server_tls_output_pending"

///|
extern "c" fn tls_handshake_c(handle : Int64) -> Int = "http_server_tls_handshake"

///|
#borrow(buf)
extern "c" fn tls_read_c(
  handle : Int64,
  buf : FixedArray[Byte],
  offset : Int,
  cap : Int,
) -> Int = "http_server_tls_read"

///|
#borrow(buf)
extern "c" fn tls_write_c(
  handle : Int64,
  buf : Bytes,
  offset : Int,
  len : Int,
) -> Int = "http_server_tls_write"

///|
extern "c" fn tls_shutdown_c(handle : Int64) -> Int = "http_server_tls_shutdown"
