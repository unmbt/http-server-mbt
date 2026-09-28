# libevent example dependency

Only the example links libevent; the shipped engine and Node addon do not.

- Version: libevent 2.1.12-stable
- Source: https://github.com/libevent/libevent/releases/download/release-2.1.12-stable/libevent-2.1.12-stable.tar.gz
- SHA-256: `92e6de1be9ec176428fd2367677e61ceffc2ee1cb119035037a27d346b0403bb`
- License: BSD-3-Clause and notices in the archive's `LICENSE`.
- Configuration: static event_core/event_extra; OpenSSL, samples and upstream test programs disabled for this example build.
- Source and license are retained under `target/libevent-2.1.12-stable`; the build driver verifies the archive before extraction.
