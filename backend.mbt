///|
/// Return whether the Linux io_uring experiment can be initialized in this
/// process. Other platforms always return false.
pub fn io_uring_available() -> Bool {
  @native.io_uring_available()
}

///|
/// Return the io_uring capability bitset observed at startup.
///
/// Bits are setup (0), IORING_OP_READ (1), IORING_OP_SEND (2), and
/// IORING_OP_ASYNC_CANCEL (3). A zero value means the probe was unavailable.
pub fn io_uring_capabilities() -> UInt32 {
  @native.io_uring_capabilities()
}
