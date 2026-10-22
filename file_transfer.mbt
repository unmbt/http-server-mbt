///|
/// Process handle count for Native resource probes.
pub fn get_handle_count() -> UInt32 {
  @native.process_handles()
}
