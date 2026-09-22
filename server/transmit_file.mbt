///|
/// Compatibility facade for the historical server API. The native transfer
/// backend is owned by the root static package so thin and full share it.
pub async fn transmit_file(
  sock : @types.Fd,
  path : String,
  offset : Int64,
  length : Int64,
) -> Int {
  @root.transmit_file(sock, path, offset, length)
}

///|
pub fn get_handle_count() -> UInt {
  @root.get_handle_count()
}
