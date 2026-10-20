///|
/// D-05: stable platform default, with explicit Linux experiments.
/// IoUringFile keeps epoll networking and sendfile, replacing buffered file reads.
/// IoUring uses completion-based incoming TCP and bounded read/send bodies.
/// Auto may select IoUring only after startup capability checks succeed.
pub(all) enum IoBackend {
  Platform
  Auto
  Epoll
  Kqueue
  Iocp
  IoUring
  IoUringFile
} derive(Debug, Eq)

///|
pub extend IoBackend with Eq::{not_equal, equal}

///|
pub extend IoBackend with Debug::{to_repr}

///|
pub fn IoBackend::parse(value : String) -> IoBackend raise ConfigError {
  match value {
    "platform" => Platform
    "auto" => Auto
    "epoll" => Epoll
    "kqueue" => Kqueue
    "iocp" => Iocp
    "io_uring" => IoUring
    "io_uring-file" => IoUringFile
    _ => raise InvalidBackend("unknown I/O backend: " + value)
  }
}

///|
pub impl Show for IoBackend with fn output(self, logger) {
  logger.write_string(
    match self {
      Platform => "platform"
      Auto => "auto"
      Epoll => "epoll"
      Kqueue => "kqueue"
      Iocp => "iocp"
      IoUring => "io_uring"
      IoUringFile => "io_uring-file"
    },
  )
}

///|
pub extend IoBackend with Show::{to_string, output}
