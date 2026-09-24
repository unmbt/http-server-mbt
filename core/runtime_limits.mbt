///|
/// D-05/D-06: finite Native resources. Budgets include all instances sharing an owner.
pub(all) struct RuntimeLimits {
  file_workers : Int
  queued_operations : Int
  connections : Int
  body_block_bytes : Int
  body_buffer_bytes : Int
  directory_metadata_bytes : Int
} derive(Debug, Eq)

///|
pub fn RuntimeLimits::default() -> RuntimeLimits {
  { file_workers: 4, queued_operations: 256, connections: 1024,
    body_block_bytes: 65536, body_buffer_bytes: 67108864,
    directory_metadata_bytes: 67108864 }
}

///|
pub fn RuntimeLimits::validate(self : RuntimeLimits) -> Unit raise ConfigError {
  if self.file_workers < 1 || self.file_workers > 64 ||
    self.queued_operations < 1 || self.connections < 1 ||
    self.body_block_bytes < 1 || self.body_block_bytes > 1048576 ||
    self.body_buffer_bytes < self.body_block_bytes * 2 || self.directory_metadata_bytes < 1 {
    raise InvalidLimits("positive capacities required; file_workers <= 64, body_block_bytes <= 1 MiB; body budget must hold both native and delivered blocks")
  }
}


///|
pub extend RuntimeLimits with Debug::{to_repr}

///|
pub extend RuntimeLimits with Eq::{not_equal, equal}
