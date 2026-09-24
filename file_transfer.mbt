///|
/// Process handle count for Native resource probes.
pub fn get_handle_count() -> UInt { @native.process_handles() }
